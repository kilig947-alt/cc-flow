import AppKit
import SwiftUI
import Combine

/// 自定义十字准星与辅助
private enum GiflowCursorHelper {
    static let crosshair: NSCursor = {
        let size = NSSize(width: 25, height: 25)
        let image = NSImage(size: size)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.clear(CGRect(origin: .zero, size: size))

            // 1. 白色外光圈轮廓（确保在深色背景下清晰可见）
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(3.0)
            context.setLineCap(.round)

            // 水平两翼
            context.move(to: CGPoint(x: 2, y: 12.5))
            context.addLine(to: CGPoint(x: 8.5, y: 12.5))
            context.move(to: CGPoint(x: 16.5, y: 12.5))
            context.addLine(to: CGPoint(x: 23, y: 12.5))

            // 垂直两翼
            context.move(to: CGPoint(x: 12.5, y: 2))
            context.addLine(to: CGPoint(x: 12.5, y: 8.5))
            context.move(to: CGPoint(x: 12.5, y: 16.5))
            context.addLine(to: CGPoint(x: 12.5, y: 23))
            context.strokePath()

            // 2. 内部深色细线
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.4)
            context.move(to: CGPoint(x: 2, y: 12.5))
            context.addLine(to: CGPoint(x: 8.5, y: 12.5))
            context.move(to: CGPoint(x: 16.5, y: 12.5))
            context.addLine(to: CGPoint(x: 23, y: 12.5))
            context.move(to: CGPoint(x: 12.5, y: 2))
            context.addLine(to: CGPoint(x: 12.5, y: 8.5))
            context.move(to: CGPoint(x: 12.5, y: 16.5))
            context.addLine(to: CGPoint(x: 12.5, y: 23))
            context.strokePath()

            // 3. 中心红色精准对心瞄点
            context.setFillColor(NSColor.systemRed.cgColor)
            context.fillEllipse(in: CGRect(x: 11, y: 11, width: 3, height: 3))
        }
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 12.5, y: 12.5))
    }()
}

/// 支持成为 Key 窗口的覆盖 Panel
private final class GiflowOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 选区交互与录制蒙版窗口控制器
@MainActor
final class GiflowOverlayController: NSObject {
    static let shared = GiflowOverlayController()

    private var overlayWindows: [GiflowOverlayPanel] = []
    private var actionPopoverWindow: NSWindow?
    private var isCursorPushed = false

    private(set) var currentRect: CGRect?
    private(set) var currentKind: GiflowSelectionKind?

    var onConfirmSelection: ((CGRect, GiflowSelectionKind) -> Void)?
    var onCancelSelection: (() -> Void)?
    var onDiscardRecording: (() -> Void)?
    var onSaveRecording: ((GiflowMediaFormat) -> Void)?

    private override init() {
        super.init()
    }

    /// 启动选区模式
    func startSelection(kind: GiflowSelectionKind) {
        closeAll()
        currentKind = kind

        guard let screens = NSScreen.screens as [NSScreen]?, !screens.isEmpty else { return }

        // 激活应用以保证鼠标光标生效
        NSApp.activate(ignoringOtherApps: true)
        pushCrosshairCursor()

        let mouseLocation = NSEvent.mouseLocation

        // 为每个显示器创建覆盖窗口
        for screen in screens {
            let window = GiflowOverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver + 2
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true

            let selectionView = GiflowSelectionCanvasView(
                screenFrame: screen.frame,
                kind: kind,
                onSelectionFinished: { [weak self] rect, screenPoint in
                    self?.handleSelectionFinished(rect: rect, on: screen, at: screenPoint, kind: kind)
                },
                onRedragRequested: { [weak self] in
                    self?.hideActionPopover()
                },
                onCancelRequested: { [weak self] in
                    self?.closeAll()
                    self?.onCancelSelection?()
                }
            )
            window.contentView = selectionView

            // 如果当前显示器包含鼠标，则设为 Key Window
            if screen.frame.contains(mouseLocation) {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }

            window.invalidateCursorRects(for: selectionView)
            overlayWindows.append(window)
        }

        // 如果是全屏模式，默认直接选中当前鼠标所在屏幕
        if kind == .fullScreen {
            let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? screens[0]
            currentRect = activeScreen.frame
            showFullScreenConfirm(on: activeScreen, at: mouseLocation)
        }
    }

    func pushCrosshairCursor() {
        if !isCursorPushed {
            GiflowCursorHelper.crosshair.push()
            isCursorPushed = true
        }
        GiflowCursorHelper.crosshair.set()
    }

    func popCrosshairCursor() {
        if isCursorPushed {
            NSCursor.pop()
            isCursorPushed = false
        }
        NSCursor.arrow.set()
    }

    /// 选区完成，在鼠标上方弹出操作浮层
    private func handleSelectionFinished(
        rect: CGRect,
        on screen: NSScreen,
        at screenPoint: CGPoint,
        kind: GiflowSelectionKind
    ) {
        currentRect = rect
        showActionPopover(for: rect, on: screen, at: screenPoint, kind: kind)
    }

    /// 弹出「确认 / 取消 / 重新拖拽」浮动面板
    private func showActionPopover(
        for rect: CGRect,
        on screen: NSScreen,
        at screenPoint: CGPoint,
        kind: GiflowSelectionKind
    ) {
        hideActionPopover()
        popCrosshairCursor()

        let popoverView = GiflowSelectionActionPopupView(
            kind: kind,
            rect: rect,
            onConfirm: { [weak self] in
                guard let self = self, let confirmedRect = self.currentRect else { return }
                self.hideActionPopover()
                self.popCrosshairCursor()
                self.onConfirmSelection?(confirmedRect, kind)
            },
            onCancel: { [weak self] in
                self?.closeAll()
                self?.onCancelSelection?()
            },
            onRedrag: { [weak self] in
                self?.hideActionPopover()
                self?.pushCrosshairCursor()
                for window in self?.overlayWindows ?? [] {
                    (window.contentView as? GiflowSelectionCanvasView)?.resetSelection()
                }
            }
        )

        let hostingView = NSHostingView(rootView: popoverView)
        let fittingSize = hostingView.fittingSize

        // 计算弹窗位置：鼠标停留点上方或选区上方居中
        var popoverOrigin = CGPoint(
            x: screenPoint.x - fittingSize.width / 2,
            y: screenPoint.y + 18
        )

        // 避免超出屏幕顶部
        if popoverOrigin.y + fittingSize.height > screen.frame.maxY - 20 {
            popoverOrigin.y = screenPoint.y - fittingSize.height - 18
        }
        // 限制在屏幕水平范围内
        popoverOrigin.x = max(screen.frame.minX + 16, min(popoverOrigin.x, screen.frame.maxX - fittingSize.width - 16))

        let popWindow = NSPanel(
            contentRect: CGRect(origin: popoverOrigin, size: fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        popWindow.level = .screenSaver + 3
        popWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        popWindow.isOpaque = false
        popWindow.backgroundColor = .clear
        popWindow.hasShadow = false
        popWindow.contentView = hostingView
        popWindow.orderFrontRegardless()

        self.actionPopoverWindow = popWindow
    }

    /// 全屏模式确认浮层
    private func showFullScreenConfirm(on screen: NSScreen, at mousePoint: CGPoint) {
        showActionPopover(for: screen.frame, on: screen, at: mousePoint, kind: .fullScreen)
    }

    /// 切换到「录制中非阻塞蒙版」状态（完全不拦截任何鼠标和键盘事件）
    func transitionToRecordingOverlay(rect: CGRect, kind: GiflowSelectionKind) {
        hideActionPopover()
        popCrosshairCursor()
        currentRect = rect

        for window in overlayWindows {
            // 关键：开启鼠标穿透，用户可完全正常操作屏幕任意位置
            window.ignoresMouseEvents = true
            if let canvasView = window.contentView as? GiflowSelectionCanvasView {
                canvasView.setRecordingMode(recordingRect: rect, kind: kind)
            }
        }
    }

    /// 录制中快捷键再次触发或点击时，在鼠标位置弹出「放弃 / 保存」
    func showRecordingControlMenu(at mousePoint: CGPoint? = nil) {
        hideActionPopover()

        let point = mousePoint ?? NSEvent.mouseLocation
        let menuView = GiflowRecordingControlPopupView(
            onSaveGIF: { [weak self] in
                self?.hideActionPopover()
                self?.onSaveRecording?(.gif)
            },
            onSaveMP4: { [weak self] in
                self?.hideActionPopover()
                self?.onSaveRecording?(.mp4)
            },
            onDiscard: { [weak self] in
                self?.closeAll()
                self?.onDiscardRecording?()
            }
        )

        let hostingView = NSHostingView(rootView: menuView)
        let size = hostingView.fittingSize

        var origin = CGPoint(x: point.x - size.width / 2, y: point.y + 18)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            if origin.y + size.height > screen.frame.maxY - 20 {
                origin.y = point.y - size.height - 18
            }
            origin.x = max(screen.frame.minX + 16, min(origin.x, screen.frame.maxX - size.width - 16))
        }

        let popWindow = NSPanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        popWindow.level = .screenSaver + 3
        popWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        popWindow.isOpaque = false
        popWindow.backgroundColor = .clear
        popWindow.hasShadow = false
        popWindow.contentView = hostingView
        popWindow.orderFrontRegardless()

        self.actionPopoverWindow = popWindow
    }

    func hideActionPopover() {
        actionPopoverWindow?.orderOut(nil)
        actionPopoverWindow = nil
    }

    /// 关闭所有覆盖窗口
    func closeAll() {
        popCrosshairCursor()
        hideActionPopover()
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        currentRect = nil
        currentKind = nil
    }
}

// MARK: - 选区绘制与蒙版画布视图

private final class GiflowSelectionCanvasView: NSView {
    private let screenFrame: CGRect
    private let kind: GiflowSelectionKind
    private let onSelectionFinished: (CGRect, CGPoint) -> Void
    private let onRedragRequested: () -> Void
    private let onCancelRequested: () -> Void

    private var isDragging = false
    private var dragStartPoint: CGPoint?
    private var dragCurrentPoint: CGPoint?
    private var selectedRect: CGRect?

    private var isRecording = false
    private var recordingRect: CGRect?
    private var trackingArea: NSTrackingArea?

    init(
        screenFrame: CGRect,
        kind: GiflowSelectionKind,
        onSelectionFinished: @escaping (CGRect, CGPoint) -> Void,
        onRedragRequested: @escaping () -> Void,
        onCancelRequested: @escaping () -> Void
    ) {
        self.screenFrame = screenFrame
        self.kind = kind
        self.onSelectionFinished = onSelectionFinished
        self.onRedragRequested = onRedragRequested
        self.onCancelRequested = onCancelRequested
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    func resetSelection() {
        isDragging = false
        dragStartPoint = nil
        dragCurrentPoint = nil
        selectedRect = nil
        isRecording = false
        recordingRect = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func setRecordingMode(recordingRect: CGRect, kind: GiflowSelectionKind) {
        self.isRecording = true
        self.recordingRect = recordingRect
        self.needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !isRecording {
            addCursorRect(bounds, cursor: GiflowCursorHelper.crosshair)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if !isRecording {
            GiflowCursorHelper.crosshair.set()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if !isRecording {
            GiflowCursorHelper.crosshair.set()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if !isRecording {
            GiflowCursorHelper.crosshair.set()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC 键取消
            onCancelRequested()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !isRecording, kind == .area else { return }
        GiflowCursorHelper.crosshair.set()
        let loc = convert(event.locationInWindow, from: nil)
        dragStartPoint = loc
        dragCurrentPoint = loc
        isDragging = true
        selectedRect = nil
        onRedragRequested()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isRecording, isDragging, let start = dragStartPoint else { return }
        GiflowCursorHelper.crosshair.set()
        let loc = convert(event.locationInWindow, from: nil)
        dragCurrentPoint = loc
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !isRecording, isDragging, let start = dragStartPoint, let current = dragCurrentPoint else { return }
        isDragging = false

        let minX = min(start.x, current.x)
        let maxX = max(start.x, current.x)
        let minY = min(start.y, current.y)
        let maxY = max(start.y, current.y)

        let width = max(16, maxX - minX)
        let height = max(16, maxY - minY)

        // 转换为屏幕全局坐标
        let localRect = CGRect(x: minX, y: minY, width: width, height: height)
        let globalRect = CGRect(
            x: screenFrame.minX + localRect.minX,
            y: screenFrame.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )

        selectedRect = localRect
        needsDisplay = true

        let mouseScreenPoint = NSEvent.mouseLocation
        onSelectionFinished(globalRect, mouseScreenPoint)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if isRecording {
            drawRecordingOverlay(context: context)
            return
        }

        if kind == .fullScreen {
            drawFullScreenGuide(context: context)
            return
        }

        if isDragging, let start = dragStartPoint, let current = dragCurrentPoint {
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: max(2, abs(current.x - start.x)),
                height: max(2, abs(current.y - start.y))
            )
            drawSelectionBox(context: context, rect: rect, showDimensions: true)
        } else if let rect = selectedRect {
            drawSelectionBox(context: context, rect: rect, showDimensions: true)
        } else {
            // 触发进入区域截取后，立即绘制柔和蒙版与操作提示
            drawIdleSelectionHint(context: context)
        }
    }

    /// 刚按下 Alt+5 时的初始全屏柔和蒙版与提示
    private func drawIdleSelectionHint(context: CGContext) {
        context.saveGState()

        // 柔和暗色遮罩
        context.setFillColor(NSColor(white: 0, alpha: 0.12).cgColor)
        context.fill(bounds)

        // 绘制顶部中心提示气泡
        let hintText = "拖拽选择录制区域 · ESC 取消"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attrStr = NSAttributedString(string: hintText, attributes: attrs)
        let textSize = attrStr.size()

        let badgeRect = CGRect(
            x: (bounds.width - textSize.width - 24) / 2,
            y: bounds.height - 80,
            width: textSize.width + 24,
            height: textSize.height + 12
        )

        let bgPath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeRect.height / 2, yRadius: badgeRect.height / 2)
        NSColor(white: 0.1, alpha: 0.85).setFill()
        bgPath.fill()

        attrStr.draw(at: CGPoint(x: badgeRect.minX + 12, y: badgeRect.minY + 6))

        context.restoreGState()
    }

    private func drawSelectionBox(context: CGContext, rect: CGRect, showDimensions: Bool) {
        context.saveGState()

        // 选区外部柔和微暗蒙版（降低灰度）
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(rect)
        context.addPath(path)
        context.setFillColor(NSColor(white: 0, alpha: 0.10).cgColor)
        context.fillPath(using: .evenOdd)

        // 优雅高对比度虚线外框
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.8)
        context.setLineDash(phase: 0, lengths: [5, 4])
        context.stroke(rect)

        // 细微半透明内描边
        context.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 4, lengths: [5, 4])
        context.stroke(rect.insetBy(dx: -1, dy: -1))

        // 尺寸文字标签
        if showDimensions, rect.width > 60, rect.height > 30 {
            let dimText = "\(Int(rect.width)) × \(Int(rect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let attrStr = NSAttributedString(string: dimText, attributes: attrs)
            let textSize = attrStr.size()
            let badgeRect = CGRect(
                x: rect.midX - textSize.width / 2 - 6,
                y: rect.minY - textSize.height - 8 > 5 ? rect.minY - textSize.height - 8 : rect.minY + 6,
                width: textSize.width + 12,
                height: textSize.height + 4
            )
            let bgPath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
            NSColor(white: 0.12, alpha: 0.9).setFill()
            bgPath.fill()
            attrStr.draw(at: CGPoint(x: badgeRect.minX + 6, y: badgeRect.minY + 2))
        }

        context.restoreGState()
    }

    private func drawFullScreenGuide(context: CGContext) {
        context.saveGState()

        // 柔和微暗蒙版
        context.setFillColor(NSColor(white: 0, alpha: 0.08).cgColor)
        context.fill(bounds)

        let rect = bounds.insetBy(dx: 4, dy: 4)
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(2.5)
        context.setLineDash(phase: 0, lengths: [8, 6])
        context.stroke(rect)

        context.restoreGState()
    }

    private func drawRecordingOverlay(context: CGContext) {
        guard let globalRect = recordingRect else { return }

        // 转换回本地窗口坐标
        let localRect = CGRect(
            x: globalRect.minX - screenFrame.minX,
            y: globalRect.minY - screenFrame.minY,
            width: globalRect.width,
            height: globalRect.height
        )

        context.saveGState()

        // 录制中选区外极轻微暗调蒙版（降低灰度，极度轻柔，完全不阻碍视线）
        let path = CGMutablePath()
        path.addRect(bounds)
        if bounds.intersects(localRect) {
            path.addRect(localRect.intersection(bounds))
        }
        context.addPath(path)
        context.setFillColor(NSColor(white: 0, alpha: 0.05).cgColor)
        context.fillPath(using: .evenOdd)

        // 录制边框：精致细虚线红色边框
        if bounds.intersects(localRect) {
            let intersectRect = localRect
            context.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(1.8)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(intersectRect)
        }

        context.restoreGState()
    }
}

// MARK: - 选区操作浮窗视图 (SwiftUI)

private struct GiflowSelectionActionPopupView: View {
    let kind: GiflowSelectionKind
    let rect: CGRect
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onRedrag: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 尺寸标签胶囊
            HStack(spacing: 4) {
                Image(systemName: kind == .fullScreen ? "macwindow" : "crop")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Text(kind == .fullScreen ? "全屏" : "\(Int(rect.width)) × \(Int(rect.height))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())

            // 确认按钮
            Button(action: onConfirm) {
                HStack(spacing: 4) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 12))
                    Text("确认录制")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [Color.red, Color(red: 0.85, green: 0.1, blue: 0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if kind == .area {
                Button(action: onRedrag) {
                    Text("重新选择")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Button(action: onCancel) {
                Text("取消")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(white: 0.12).opacity(0.92))
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        )
    }
}

// MARK: - 录制中控制浮窗视图 (SwiftUI)

private struct GiflowRecordingControlPopupView: View {
    let onSaveGIF: () -> Void
    let onSaveMP4: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("录制中")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.leading, 4)

            Button(action: onSaveGIF) {
                HStack(spacing: 4) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 11))
                    Text("保存为 GIF")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [Color.red, Color(red: 0.85, green: 0.1, blue: 0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onSaveMP4) {
                HStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 11))
                    Text("保存为 MP4")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color(red: 0.1, green: 0.4, blue: 0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onDiscard) {
                HStack(spacing: 3) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                    Text("放弃")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(white: 0.12).opacity(0.92))
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        )
    }
}
