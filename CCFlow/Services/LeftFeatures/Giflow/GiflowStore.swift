import Foundation
import AppKit
import Combine
import SwiftUI
import AVFoundation

/// Giflow 业务数据与录制生命周期管理中心
@MainActor
final class GiflowStore: ObservableObject {
    static let shared = GiflowStore()

    @Published private(set) var recordings: [GiflowRecordingItem] = []
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isPreparing: Bool = false
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var isExporting: Bool = false
    @Published private(set) var exportProgress: Double = 0.0
    @Published private(set) var lastExportedItem: GiflowRecordingItem?

    @Published var settings: GiflowSettings {
        didSet {
            saveSettings()
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private let settingsKey = "giflow.settings"

    private init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(GiflowSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }

        setupBindings()
        setupOverlayHandlers()
        loadRecordings()
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func setupBindings() {
        let manager = GiflowRecordingManager.shared

        manager.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] val in self?.isRecording = val }
            .store(in: &cancellables)

        manager.$isPreparing
            .receive(on: RunLoop.main)
            .sink { [weak self] val in self?.isPreparing = val }
            .store(in: &cancellables)

        manager.$elapsedSeconds
            .receive(on: RunLoop.main)
            .sink { [weak self] val in self?.elapsedSeconds = val }
            .store(in: &cancellables)
    }

    private func setupOverlayHandlers() {
        let overlay = GiflowOverlayController.shared

        overlay.onConfirmSelection = { [weak self] rect, kind in
            self?.handleSelectionConfirmed(rect: rect, kind: kind)
        }

        overlay.onCancelSelection = { [weak self] in
            Task { @MainActor in
                await self?.discardRecording()
            }
        }

        overlay.onSaveRecording = { [weak self] format in
            Task { @MainActor in
                await self?.stopRecording(format: format)
            }
        }

        overlay.onDiscardRecording = { [weak self] in
            Task { @MainActor in
                await self?.discardRecording()
            }
        }
    }

    // MARK: - 录制触发与快捷键处理

    /// 区域截取 (⌥ + 5)
    func triggerSelectionCapture() {
        if isRecording {
            GiflowOverlayController.shared.showRecordingControlMenu()
        } else {
            GiflowOverlayController.shared.startSelection(kind: .area)
        }
    }

    /// 全屏截取 (⌥ + 6)
    func triggerFullScreenCapture() {
        if isRecording {
            GiflowOverlayController.shared.showRecordingControlMenu()
        } else {
            GiflowOverlayController.shared.startSelection(kind: .fullScreen)
        }
    }

    /// 打开录制结果列表 (⌥ + 7)
    func openRecordingsList() {
        LeftFeatureStore.shared.expandedActiveFeatureID = LeftFeature.giflowID
        NotificationCenter.default.post(
            name: .ccFlowOpenLeftFeatureShortcut,
            object: nil,
            userInfo: ["featureID": LeftFeature.giflowID]
        )
    }

    private func handleSelectionConfirmed(rect: CGRect, kind: GiflowSelectionKind) {
        GiflowOverlayController.shared.transitionToRecordingOverlay(rect: rect, kind: kind)

        let captureMode: GiflowCaptureMode
        switch kind {
        case .area:
            captureMode = .selection(rect)
        case .fullScreen:
            let displayID = CGMainDisplayID()
            captureMode = .fullScreen(displayID: displayID, bounds: rect)
        }

        Task {
            do {
                try await GiflowRecordingManager.shared.startRecording(mode: captureMode, settings: self.settings)
            } catch {
                GiflowOverlayController.shared.closeAll()
            }
        }
    }

    /// 停止录制并启动后台导出（支持指定 GIF 或 MP4 格式）
    func stopRecording(format: GiflowMediaFormat = .gif) async {
        GiflowOverlayController.shared.closeAll()

        guard let result = await GiflowRecordingManager.shared.stopRecording() else {
            return
        }

        let captureBounds = GiflowOverlayController.shared.currentRect ?? NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestampStr = formatter.string(from: Date())
        let ext = format.fileExtension
        let filename = "Giflow-\(timestampStr).\(ext)"
        let outputURL = BridgeRuntimePaths.giflowDirectoryURL.appendingPathComponent(filename)

        isExporting = true
        exportProgress = 0.0

        let currentSettings = self.settings

        Task.detached(priority: .userInitiated) {
            do {
                let item: GiflowRecordingItem
                if format == .mp4 {
                    item = try await GiflowExporter.exportMP4(
                        samples: result.samples,
                        clicks: result.clicks,
                        keys: result.keys,
                        captureBounds: captureBounds,
                        outputURL: outputURL,
                        settings: currentSettings
                    ) { progress in
                        Task { @MainActor in
                            GiflowStore.shared.exportProgress = progress
                        }
                    }
                } else {
                    item = try await GiflowExporter.exportGIF(
                        samples: result.samples,
                        clicks: result.clicks,
                        keys: result.keys,
                        captureBounds: captureBounds,
                        outputURL: outputURL,
                        settings: currentSettings
                    ) { progress in
                        Task { @MainActor in
                            GiflowStore.shared.exportProgress = progress
                        }
                    }
                }

                await MainActor.run {
                    self.isExporting = false
                    self.exportProgress = 1.0
                    self.lastExportedItem = item
                    self.recordings.insert(item, at: 0)
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.exportProgress = 0.0
                }
            }
        }
    }

    /// 将已有的录制项另存为 MP4（作为全新独立任务加入列表，不删除或覆盖旧项）
    func convertItemToMP4(_ item: GiflowRecordingItem) {
        guard !isExporting, item.format == .gif else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestampStr = formatter.string(from: Date())
        let outputFilename = "\(item.name)-\(timestampStr).mp4"
        let outputURL = BridgeRuntimePaths.giflowDirectoryURL.appendingPathComponent(outputFilename)

        isExporting = true
        exportProgress = 0.0

        Task.detached(priority: .userInitiated) {
            do {
                let newItem = try await GiflowExporter.convertGIFToMP4(
                    gifURL: item.fileURL,
                    outputURL: outputURL
                ) { progress in
                    Task { @MainActor in
                        GiflowStore.shared.exportProgress = progress
                    }
                }

                await MainActor.run {
                    self.isExporting = false
                    self.exportProgress = 1.0
                    self.lastExportedItem = newItem
                    self.recordings.insert(newItem, at: 0)
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.exportProgress = 0.0
                }
            }
        }
    }

    /// 放弃录制
    func discardRecording() async {
        GiflowOverlayController.shared.closeAll()
        await GiflowRecordingManager.shared.discardRecording()
    }

    // MARK: - 录制结果历史与管理

    func loadRecordings() {
        let dir = BridgeRuntimePaths.giflowDirectoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let mediaFiles = files.filter { ["gif", "mp4"].contains($0.pathExtension.lowercased()) }

        var items: [GiflowRecordingItem] = []
        for url in mediaFiles {
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let size = Int64(resourceValues?.fileSize ?? 0)
            let date = resourceValues?.creationDate ?? Date()
            let isMP4 = url.pathExtension.lowercased() == "mp4"

            var width = 0
            var height = 0
            var duration: TimeInterval = 0

            if isMP4 {
                let asset = AVURLAsset(url: url)
                if let track = asset.tracks(withMediaType: .video).first {
                    let transformedSize = track.naturalSize.applying(track.preferredTransform)
                    width = Int(abs(transformedSize.width))
                    height = Int(abs(transformedSize.height))
                }
                duration = CMTimeGetSeconds(asset.duration)
                if duration.isNaN { duration = 0 }
            } else {
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                    let frameCount = CGImageSourceGetCount(source)
                    if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                        width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
                        height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
                        if let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                            let delay = gifDict[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1
                            duration = Double(frameCount) * delay
                        }
                    }
                }
            }

            let item = GiflowRecordingItem(
                id: url.lastPathComponent,
                name: url.deletingPathExtension().lastPathComponent,
                fileURL: url,
                createdAt: date,
                fileSize: size,
                duration: duration,
                width: width,
                height: height,
                fps: 15
            )
            items.append(item)
        }

        // 按创建时间倒序
        recordings = items.sorted { $0.createdAt > $1.createdAt }
    }

    /// 复制媒体动图/视频到剪贴板（支持在微信、飞书、Slack、Finder、终端等任意场景下直接粘贴）
    func copyMediaToClipboard(item: GiflowRecordingItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // 1. 写入标准 NSURL 对象 (public.file-url, public.url)
        pasteboard.writeObjects([item.fileURL as NSURL])

        // 2. 写入 NSFilenamesPboardType (Finder、微信、飞书、Slack、QQ 等各类原生应用识别文件粘贴的核心类型)
        pasteboard.setPropertyList([item.fileURL.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))

        // 3. 写入文件路径纯文本 (纯文本编辑器/终端中粘贴时得到文件绝对路径)
        pasteboard.setString(item.fileURL.path, forType: .string)

        // 4. 如果是 GIF 动图，额外写入动图与图片原始数据 (备忘录/即时通讯工具可直接作为图片插入)
        if item.format == .gif, let data = try? Data(contentsOf: item.fileURL) {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType("public.image"))
        }

        // 5. 如果是 MP4 视频，额外声明 public.mpeg-4 / public.movie 类型标识
        if item.format == .mp4 {
            pasteboard.setString(item.fileURL.absoluteString, forType: NSPasteboard.PasteboardType("public.mpeg-4"))
        }
    }

    /// 在 Finder 中定位文件
    func revealInFinder(item: GiflowRecordingItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
    }

    /// 删除录制项
    func deleteItem(item: GiflowRecordingItem) {
        try? FileManager.default.removeItem(at: item.fileURL)
        recordings.removeAll { $0.id == item.id }
    }

    /// 重命名录制项
    func renameItem(item: GiflowRecordingItem, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }

        let ext = item.fileURL.pathExtension
        let newURL = item.fileURL.deletingLastPathComponent().appendingPathComponent("\(trimmed).\(ext)")
        do {
            try FileManager.default.moveItem(at: item.fileURL, to: newURL)
            if let index = recordings.firstIndex(where: { $0.id == item.id }) {
                recordings[index] = GiflowRecordingItem(
                    id: newURL.lastPathComponent,
                    name: trimmed,
                    fileURL: newURL,
                    createdAt: item.createdAt,
                    fileSize: item.fileSize,
                    duration: item.duration,
                    width: item.width,
                    height: item.height,
                    fps: item.fps
                )
            }
        } catch {}
    }
}
