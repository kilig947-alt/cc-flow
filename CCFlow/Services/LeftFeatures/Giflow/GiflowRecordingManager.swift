import Foundation
import CoreGraphics
import AppKit
import Combine
import ScreenCaptureKit
import CoreMedia
import VideoToolbox

/// 屏幕录制与事件捕获管理器
@MainActor
final class GiflowRecordingManager: NSObject, ObservableObject {
    static let shared = GiflowRecordingManager()

    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var activeCaptureMode: GiflowCaptureMode?

    // 录制采集数据
    private(set) var capturedSamples: [GiflowCapturedSample] = []
    private(set) var clickEvents: [GiflowClickEvent] = []
    private(set) var keyEvents: [GiflowKeyEvent] = []

    private var recordingStartTime: Date?
    private var durationTimer: Timer?

    // 全局事件监听器句柄
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    // ScreenCaptureKit 录制流
    private var scStream: SCStream?
    private var streamDelegate: GiflowSCStreamDelegate?

    // 定时抓取 Fallback (备用机制)
    private var fallbackTimer: Timer?
    private var targetDisplayID: CGDirectDisplayID = CGMainDisplayID()

    private override init() {
        super.init()
    }

    /// 开始录制
    func startRecording(mode: GiflowCaptureMode, settings: GiflowSettings = .default) async throws {
        guard !isRecording else { return }

        isPreparing = true
        activeCaptureMode = mode
        capturedSamples.removeAll()
        clickEvents.removeAll()
        keyEvents.removeAll()
        elapsedSeconds = 0

        let startTime = Date()
        self.recordingStartTime = startTime

        // 1. 安装鼠标和键盘全局/局部监听器
        installEventMonitors(startTime: startTime)

        // 2. 启动屏幕捕获流
        do {
            try await startScreenCapture(mode: mode, settings: settings)
        } catch {
            // 如果 ScreenCaptureKit 失败，尝试 fallback 抓取
            startFallbackCapture(mode: mode, settings: settings)
        }

        // 3. 启动计时器
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.recordingStartTime else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(start))
            }
        }

        isPreparing = false
        isRecording = true
    }

    /// 停止录制并返回采集的数据集
    func stopRecording() async -> (samples: [GiflowCapturedSample], clicks: [GiflowClickEvent], keys: [GiflowKeyEvent], duration: TimeInterval)? {
        guard isRecording else { return nil }

        isRecording = false
        isPreparing = false
        durationTimer?.invalidate()
        durationTimer = nil

        uninstallEventMonitors()
        await stopScreenCapture()
        stopFallbackCapture()

        let totalDuration = Date().timeIntervalSince(recordingStartTime ?? Date())
        let resultSamples = capturedSamples
        let resultClicks = clickEvents
        let resultKeys = keyEvents

        // 清理缓存
        capturedSamples.removeAll()
        clickEvents.removeAll()
        keyEvents.removeAll()
        recordingStartTime = nil
        activeCaptureMode = nil
        elapsedSeconds = 0

        guard !resultSamples.isEmpty else { return nil }
        return (resultSamples, resultClicks, resultKeys, totalDuration)
    }

    /// 放弃录制并丢弃数据
    func discardRecording() async {
        guard isRecording || isPreparing else { return }

        isRecording = false
        isPreparing = false
        durationTimer?.invalidate()
        durationTimer = nil

        uninstallEventMonitors()
        await stopScreenCapture()
        stopFallbackCapture()

        capturedSamples.removeAll()
        clickEvents.removeAll()
        keyEvents.removeAll()
        recordingStartTime = nil
        activeCaptureMode = nil
        elapsedSeconds = 0
    }

    // MARK: - 事件监听

    private func installEventMonitors(startTime: Date) {
        uninstallEventMonitors()

        // 鼠标点击监听 (Global)
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleClickEvent(event, startTime: startTime)
        }
        // 鼠标点击监听 (Local)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleClickEvent(event, startTime: startTime)
            return event
        }

        // 键盘按键监听 (Global)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event, startTime: startTime)
        }
        // 键盘按键监听 (Local)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event, startTime: startTime)
            return event
        }
    }

    private func handleClickEvent(_ event: NSEvent, startTime: Date) {
        let mouseLocation = NSEvent.mouseLocation
        let elapsed = Date().timeIntervalSince(startTime)
        let isRight = event.type == .rightMouseDown
        let click = GiflowClickEvent(screenPoint: mouseLocation, timestamp: elapsed, isRightClick: isRight)
        Task { @MainActor in
            self.clickEvents.append(click)
        }
    }

    private func handleKeyEvent(_ event: NSEvent, startTime: Date) {
        let elapsed = Date().timeIntervalSince(startTime)
        let display = Self.formatKeyEvent(event)
        guard !display.isEmpty else { return }

        let keyEvent = GiflowKeyEvent(displayText: display, timestamp: elapsed)
        Task { @MainActor in
            self.keyEvents.append(keyEvent)
        }
    }

    private func uninstallEventMonitors() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    // MARK: - ScreenCaptureKit 录制

    private func startScreenCapture(mode: GiflowCaptureMode, settings: GiflowSettings) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "Giflow", code: -1, userInfo: [NSLocalizedDescriptionKey: "未检测到可捕获的显示器"])
        }
        self.targetDisplayID = display.displayID

        let currentPID = getpid()
        let excludingWindows = content.windows.filter { window in
            window.owningApplication?.processID == currentPID
        }
        let filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
        let config = SCStreamConfiguration()

        let bounds = mode.bounds
        config.width = max(100, Int(bounds.width * settings.maxScaleFactor))
        config.height = max(100, Int(bounds.height * settings.maxScaleFactor))
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.targetFPS))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        // 仅在 selection 模式下裁剪特定区域
        if case .selection(let selRect) = mode {
            // ScreenCaptureKit 坐标系：左上角原点
            // NSScreen 坐标系：左下角原点
            let screenHeight = CGFloat(display.height)
            let sckY = screenHeight - selRect.maxY
            config.sourceRect = CGRect(
                x: max(0, selRect.minX),
                y: max(0, sckY),
                width: selRect.width,
                height: selRect.height
            )
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let delegate = GiflowSCStreamDelegate { [weak self] sample in
            Task { @MainActor in
                self?.appendSample(sample)
            }
        }
        self.streamDelegate = delegate
        try stream.addStreamOutput(delegate, type: SCStreamOutputType.screen, sampleHandlerQueue: DispatchQueue(label: "ai.ccflow.giflow.stream", qos: .userInteractive))
        try await stream.startCapture()
        self.scStream = stream
    }

    private func stopScreenCapture() async {
        if let stream = scStream {
            try? await stream.stopCapture()
            scStream = nil
            streamDelegate = nil
        }
    }

    // MARK: - Fallback 捕获 (备用定时抓帧)

    private func startFallbackCapture(mode: GiflowCaptureMode, settings: GiflowSettings) {
        let interval = 1.0 / Double(settings.targetFPS)
        let bounds = mode.bounds

        fallbackTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.recordingStartTime else { return }
                let elapsed = Date().timeIntervalSince(start)

                // 抓取全屏并裁剪
                if let image = CGWindowListCreateImage(
                    bounds,
                    .optionOnScreenOnly,
                    kCGNullWindowID,
                    .bestResolution
                ) {
                    let sample = GiflowCapturedSample(image: image, timestamp: elapsed)
                    self.appendSample(sample)
                }
            }
        }
    }

    private func stopFallbackCapture() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func appendSample(_ sample: GiflowCapturedSample) {
        capturedSamples.append(sample)
    }

    // MARK: - 按键格式化辅助

    static func formatKeyEvent(_ event: NSEvent) -> String {
        var parts: [String] = []

        let flags = event.modifierFlags
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        let keyCode = Int(event.keyCode)
        let keyName: String
        switch keyCode {
        case 36: keyName = "⏎ Return"
        case 48: keyName = "⇥ Tab"
        case 49: keyName = "Space"
        case 51: keyName = "⌫ Delete"
        case 53: keyName = "⎋ Esc"
        case 123: keyName = "←"
        case 124: keyName = "→"
        case 125: keyName = "↓"
        case 126: keyName = "↑"
        default:
            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                let upper = chars.uppercased()
                if upper.count == 1, upper.unicodeScalars.first?.isASCII == true {
                    keyName = upper
                } else if !chars.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) {
                    keyName = chars
                } else {
                    keyName = "Key \(keyCode)"
                }
            } else {
                keyName = "Key \(keyCode)"
            }
        }

        parts.append(keyName)
        return parts.joined(separator: " ")
    }
}

// MARK: - ScreenCaptureKit Stream Output Delegate

private final class GiflowSCStreamDelegate: NSObject, SCStreamOutput {
    private let onSample: (GiflowCapturedSample) -> Void
    private let context = CIContext()
    private var firstTimestamp: CMTime?

    init(onSample: @escaping (GiflowCapturedSample) -> Void) {
        self.onSample = onSample
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }

        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
        let pts = sampleBuffer.presentationTimeStamp

        if firstTimestamp == nil {
            firstTimestamp = pts
        }

        let elapsed = pts.seconds - (firstTimestamp?.seconds ?? pts.seconds)

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let sample = GiflowCapturedSample(image: cgImage, timestamp: max(0, elapsed))
            onSample(sample)
        }
    }
}
