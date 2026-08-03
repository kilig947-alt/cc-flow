import AppKit
import SwiftUI

/// 管理由左侧功能部署出的桌面小组件。窗口位于桌面图标之上、普通应用之下，
/// 因而始终属于桌面层；每个功能最多保留一个实例。
@MainActor
final class DesktopWidgetController: NSObject, NSWindowDelegate {
    static let shared = DesktopWidgetController()

    private struct Record: Codable {
        let featureID: String
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        var frame: NSRect {
            NSRect(x: x, y: y, width: width, height: height)
        }

        init(featureID: String, frame: NSRect) {
            self.featureID = featureID
            x = frame.origin.x
            y = frame.origin.y
            width = frame.width
            height = frame.height
        }
    }

    private enum Keys {
        static let widgets = "desktopLeftFeatureWidgets"
    }

    private var windows: [String: DesktopWidgetPanel] = [:]
    private var didRestore = false

    func deploy(featureID: String, revealDesktop: Bool) {
        guard let feature = LeftFeatureStore.shared.features.first(where: {
            $0.id == featureID && $0.isEnabled
        }) else { return }

        if let existing = windows[featureID] {
            existing.orderFrontRegardless()
        } else {
            let frame = defaultFrame(for: feature)
            let panel = makePanel(featureID: featureID, frame: frame)
            windows[featureID] = panel
            panel.orderFrontRegardless()
            persist()
        }

        if revealDesktop {
            // macOS 没有公开的“显示桌面”API；隐藏其他应用是无需辅助功能权限的稳定方式。
            NSApp.hideOtherApplications(nil)
        }
    }

    func restorePersistedWidgets() {
        guard !didRestore else { return }
        didRestore = true

        for record in persistedRecords() {
            guard LeftFeatureStore.shared.features.contains(where: {
                $0.id == record.featureID && $0.isEnabled
            }) else { continue }
            let panel = makePanel(featureID: record.featureID, frame: visibleFrame(record.frame))
            windows[record.featureID] = panel
            panel.orderFrontRegardless()
        }
        persist()
    }

    func remove(featureID: String) {
        guard let panel = windows.removeValue(forKey: featureID) else { return }
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
        CustomAreaWebViewCache.shared.evict(for: .desktopWidget(featureID: featureID))
        persist()
    }

    func windowDidMove(_ notification: Notification) {
        persist()
    }

    func windowDidResize(_ notification: Notification) {
        persist()
    }

    private func makePanel(featureID: String, frame: NSRect) -> DesktopWidgetPanel {
        let panel = DesktopWidgetPanel(contentRect: frame)
        panel.identifier = NSUserInterfaceItemIdentifier(featureID)
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: DesktopWidgetRootView(
                featureID: featureID,
                onClose: { [weak self] in
                    self?.remove(featureID: featureID)
                },
                onResizeBegan: { [weak panel] in
                    panel?.beginInteractiveResize()
                },
                onResize: { [weak panel] edge, translation in
                    panel?.updateInteractiveResize(edge: edge, translation: translation)
                },
                onResizeEnded: { [weak panel] in
                    panel?.endInteractiveResize()
                }
            )
        )
        return panel
    }

    private func defaultFrame(for feature: LeftFeature) -> NSRect {
        let screen = ScreenSelector.shared.selectedScreen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(max(360, feature.resolvedExpandedWidth * 0.58), min(680, visible.width - 40))
        let height = min(max(260, feature.resolvedExpandedHeight * 0.72), min(560, visible.height - 40))
        return NSRect(
            x: visible.maxX - width - 28,
            y: visible.maxY - height - 28,
            width: width,
            height: height
        )
    }

    private func visibleFrame(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first else { return frame }
        let visible = screen.visibleFrame
        let width = min(max(frame.width, 320), visible.width)
        let height = min(max(frame.height, 220), visible.height)
        let x = min(max(frame.minX, visible.minX), visible.maxX - width)
        let y = min(max(frame.minY, visible.minY), visible.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func persistedRecords() -> [Record] {
        guard let data = UserDefaults.standard.data(forKey: Keys.widgets),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return records
    }

    private func persist() {
        let records = windows.map { featureID, window in
            Record(featureID: featureID, frame: window.frame)
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Keys.widgets)
    }
}

final class DesktopWidgetPanel: NSPanel {
    private var interactiveResizeStartFrame: NSRect?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        minSize = NSSize(width: 320, height: 220)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func beginInteractiveResize() {
        interactiveResizeStartFrame = frame
    }

    func updateInteractiveResize(edge: DesktopWidgetResizeEdge, translation: CGSize) {
        guard let startFrame = interactiveResizeStartFrame else { return }
        let resizedFrame = DesktopWidgetFrameResizer.resizedFrame(
            from: startFrame,
            edge: edge,
            translation: translation,
            minimumSize: minSize
        )
        setFrame(resizedFrame, display: true)
    }

    func endInteractiveResize() {
        interactiveResizeStartFrame = nil
    }
}

enum DesktopWidgetResizeEdge {
    case top
    case bottom
    case left
    case right
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var changesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    var changesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
    var changesTop: Bool { self == .top || self == .topLeft || self == .topRight }
    var changesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
}

enum DesktopWidgetFrameResizer {
    /// SwiftUI drag translations use a top-left coordinate system, while NSWindow frames use
    /// a bottom-left coordinate system. Keep the edge opposite the dragged handle anchored.
    static func resizedFrame(
        from frame: NSRect,
        edge: DesktopWidgetResizeEdge,
        translation: CGSize,
        minimumSize: NSSize
    ) -> NSRect {
        var width = frame.width
        var height = frame.height

        if edge.changesLeft { width = frame.width - translation.width }
        if edge.changesRight { width = frame.width + translation.width }
        if edge.changesTop { height = frame.height - translation.height }
        if edge.changesBottom { height = frame.height + translation.height }

        width = max(minimumSize.width, width)
        height = max(minimumSize.height, height)

        let x = edge.changesLeft ? frame.maxX - width : frame.minX
        let y = edge.changesBottom ? frame.maxY - height : frame.minY
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private struct DesktopWidgetRootView: View {
    let featureID: String
    let onClose: () -> Void
    let onResizeBegan: () -> Void
    let onResize: (DesktopWidgetResizeEdge, CGSize) -> Void
    let onResizeEnded: () -> Void

    @ObservedObject private var featureStore = LeftFeatureStore.shared
    @State private var webReloadGeneration: UInt64 = 0
    @State private var isBorderless = true
    @State private var isPointerInside = false

    private var feature: LeftFeature? {
        featureStore.features.first(where: { $0.id == featureID })
    }

    private var showsWindowChrome: Bool {
        !isBorderless || isPointerInside
    }

    var body: some View {
        Group {
            if let feature {
                featureLayout(feature)
            } else {
                Text("功能已不可用")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isBorderless ? 0 : 0.12),
                    lineWidth: 1
                )
        )
        .overlay {
            DesktopWidgetResizeOverlay(
                showsIndicators: showsWindowChrome,
                onResizeBegan: onResizeBegan,
                onResize: onResize,
                onResizeEnded: onResizeEnded
            )
        }
        .padding(isBorderless ? 0 : 1)
        .onHover { isInside in
            withAnimation(.easeOut(duration: 0.16)) {
                isPointerInside = isInside
            }
        }
    }

    @ViewBuilder
    private func featureLayout(_ feature: LeftFeature) -> some View {
        if isBorderless {
            ZStack(alignment: .top) {
                featureContent(feature)
                if showsWindowChrome {
                    header(feature)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
        } else {
            VStack(spacing: 0) {
                header(feature)
                featureContent(feature)
            }
        }
    }

    private func featureContent(_ feature: LeftFeature) -> some View {
        DesktopWidgetFeatureContent(
            feature: feature,
            reloadGeneration: webReloadGeneration,
            isBorderless: isBorderless
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ feature: LeftFeature) -> some View {
        HStack(spacing: 8) {
            FeatureIconView(feature: feature, size: 13, color: .white.opacity(0.9))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    reload(feature)
                }
                .help(feature.kind.supportsDesktopWidgetReload ? "双击刷新" : feature.displayName)
            Text(feature.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isBorderless.toggle()
                }
            } label: {
                Image(systemName: isBorderless ? "rectangle.inset.filled" : "rectangle")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help(isBorderless ? "固定显示窗口边框" : "切换为无边框模式")
            if feature.kind.supportsDesktopWidgetReload {
                Button {
                    reload(feature)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("刷新网页")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("移除桌面小组件")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(isBorderless ? Color.black.opacity(0.72) : Color.white.opacity(0.045))
    }

    private func reload(_ feature: LeftFeature) {
        guard feature.kind.supportsDesktopWidgetReload else { return }
        webReloadGeneration &+= 1
    }
}

private struct DesktopWidgetFeatureContent: View {
    let feature: LeftFeature
    let reloadGeneration: UInt64
    let isBorderless: Bool

    @ObservedObject private var customAreaStore = CustomAreaStore.shared

    var body: some View {
        if feature.kind.supportsDesktopWidgetReload {
            content
                .padding(isBorderless ? 0 : 6)
        } else {
            GeometryReader { proxy in
                ScrollView(.vertical) {
                    content
                        .frame(
                            width: proxy.size.width,
                            height: max(proxy.size.height, 420),
                            alignment: .top
                        )
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch feature.kind {
        case .usage: UsageExpandedView()
        case .systemMonitor: SystemMonitorFeatureView(compact: false)
        case .calendar: CalendarFeatureView(compact: false)
        case .github: GitHubFeatureView(compact: false)
        case .fileCards, .naturalSearch: FileCardsFeatureView(compact: false)
        case .downloadMonitor: DownloadMonitorFeatureView(compact: false)
        case .browserResources: BrowserResourcesFeatureView(compact: false)
        case .mailAssistant: MailAssistantFeatureView(compact: false)
        case .music: MusicExpandedView()
        case .shelf: ShelfExpandedView()
        case .customArea(let areaID):
            if let area = customAreaStore.areas.first(where: { $0.id == areaID }) {
                webView(source: .localArea(area))
            } else {
                unavailable("自定义 HTML 目录不可用")
            }
        case .webURL(let urlString):
            if let url = URL(string: urlString) { webView(source: .remoteURL(url)) }
            else { unavailable("网站 URL 无效") }
        case .newsnow(let baseURL):
            if let url = URL(string: baseURL) { webView(source: .remoteURL(url)) }
            else { unavailable("网站 URL 无效") }
        case .mineradio(let pageURL):
            if let url = URL(string: pageURL) { webView(source: .mineradio(url)) }
            else { unavailable("网站 URL 无效") }
        }
    }

    private func webView(source: CustomAreaWebView.ContentSource) -> some View {
        CustomAreaWebView(
            source: source,
            cacheKey: .desktopWidget(featureID: feature.id),
            keepsAlive: true,
            keepsCrossDomainLoginInWebView: feature.keepsCrossDomainLoginInWebView,
            loadsMineradioBridge: feature.loadsMineradioBridge,
            entryReloadGeneration: reloadGeneration
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: isBorderless ? 18 : 12,
                style: .continuous
            )
        )
    }

    private func unavailable(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension LeftFeatureKind {
    var supportsDesktopWidgetReload: Bool {
        switch self {
        case .customArea, .webURL, .newsnow, .mineradio: true
        default: false
        }
    }
}

private struct DesktopWidgetResizeOverlay: View {
    let showsIndicators: Bool
    let onResizeBegan: () -> Void
    let onResize: (DesktopWidgetResizeEdge, CGSize) -> Void
    let onResizeEnded: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let edgeThickness: CGFloat = 9
            let cornerSize: CGFloat = 20

            ZStack {
                handle(.top, cursor: .resizeUpDown)
                    .frame(width: max(0, width - cornerSize * 2), height: edgeThickness)
                    .position(x: width / 2, y: edgeThickness / 2)
                handle(.bottom, cursor: .resizeUpDown)
                    .frame(width: max(0, width - cornerSize * 2), height: edgeThickness)
                    .position(x: width / 2, y: height - edgeThickness / 2)
                handle(.left, cursor: .resizeLeftRight)
                    .frame(width: edgeThickness, height: max(0, height - cornerSize * 2))
                    .position(x: edgeThickness / 2, y: height / 2)
                handle(.right, cursor: .resizeLeftRight)
                    .frame(width: edgeThickness, height: max(0, height - cornerSize * 2))
                    .position(x: width - edgeThickness / 2, y: height / 2)

                cornerHandle(.topLeft)
                    .position(x: cornerSize / 2, y: cornerSize / 2)
                cornerHandle(.topRight)
                    .position(x: width - cornerSize / 2, y: cornerSize / 2)
                cornerHandle(.bottomLeft, showsIndicator: showsIndicators)
                    .position(x: cornerSize / 2, y: height - cornerSize / 2)
                cornerHandle(.bottomRight, showsIndicator: showsIndicators)
                    .position(x: width - cornerSize / 2, y: height - cornerSize / 2)
            }
        }
    }

    private func cornerHandle(
        _ edge: DesktopWidgetResizeEdge,
        showsIndicator: Bool = false
    ) -> some View {
        DesktopWidgetResizeHandle(
            edge: edge,
            cursor: .crosshair,
            showsIndicator: showsIndicator,
            onResizeBegan: onResizeBegan,
            onResize: onResize,
            onResizeEnded: onResizeEnded
        )
        .frame(width: 20, height: 20)
    }

    private func handle(_ edge: DesktopWidgetResizeEdge, cursor: NSCursor) -> some View {
        DesktopWidgetResizeHandle(
            edge: edge,
            cursor: cursor,
            showsIndicator: false,
            onResizeBegan: onResizeBegan,
            onResize: onResize,
            onResizeEnded: onResizeEnded
        )
    }
}

private struct DesktopWidgetResizeHandle: View {
    let edge: DesktopWidgetResizeEdge
    let cursor: NSCursor
    let showsIndicator: Bool
    let onResizeBegan: () -> Void
    let onResize: (DesktopWidgetResizeEdge, CGSize) -> Void
    let onResizeEnded: () -> Void

    @State private var isDragging = false

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
            if showsIndicator {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .onHover { isInside in
            if isInside { cursor.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        onResizeBegan()
                    }
                    onResize(edge, value.translation)
                }
                .onEnded { _ in
                    guard isDragging else { return }
                    isDragging = false
                    onResizeEnded()
                }
        )
    }
}
