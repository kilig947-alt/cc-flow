import AppKit
import SwiftUI

/// A separate, non-key surface for the menu-bar strip. It is deliberately not a
/// child window: AppKit child-window ordering would couple its level to the editor.
final class NotchHeaderPanel: NSPanel {
    weak var contentPanel: NotchPanel?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            NSApp.activate(ignoringOtherApps: true)
            contentPanel?.makeKey()
        }
        super.sendEvent(event)
    }
}

/// Keeps a layout slot in the original view while hosting ONLY the header in its
/// own window. There is still one NotchView lifecycle and one expanded content tree.
struct NotchHeaderSurface<Content: View>: NSViewRepresentable {
    var horizontalOutset: CGFloat
    var topCornerRadius: CGFloat
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NotchHeaderAnchorView {
        NotchHeaderAnchorView()
    }

    func updateNSView(_ view: NotchHeaderAnchorView, context: Context) {
        view.horizontalOutset = horizontalOutset
        view.setContent(AnyView(AppLocalizedRootView {
            content()
                .padding(.horizontal, horizontalOutset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .clipShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: 0))
                .preferredColorScheme(.dark)
        }))
    }

    static func dismantleNSView(_ view: NotchHeaderAnchorView, coordinator: ()) {
        view.tearDown()
    }
}

private final class NotchHeaderHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchHeaderAnchorView: NSView {
    var horizontalOutset: CGFloat = 0
    private let panel = NotchHeaderPanel()
    private let host = NotchHeaderHostingView(rootView: AnyView(EmptyView()))
    private var observations: [NSObjectProtocol] = []
    private var tornDown = false
    private var frameSyncScheduled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        panel.contentView = host
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setContent(_ content: AnyView) {
        host.rootView = content
        needsLayout = true
        // SwiftUI updates the representable before committing its frame.
        scheduleFrameSync()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        detach()
        guard let owner = window as? NotchPanel, !tornDown else { return }
        panel.contentPanel = owner
        owner.menuBarHeaderPanel = panel
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: owner, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncFrame() }
            })
        }
        syncFrame()
    }

    override func layout() {
        super.layout()
        syncFrame()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        scheduleFrameSync()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleFrameSync()
    }

    private func scheduleFrameSync() {
        guard !tornDown, !frameSyncScheduled else { return }
        frameSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameSyncScheduled = false
            self.syncFrame()
        }
    }

    private func syncFrame() {
        guard !tornDown, let owner = window as? NotchPanel, bounds.width > 0, bounds.height > 0 else {
            panel.orderOut(nil)
            return
        }
        let frame = owner.convertToScreen(convert(bounds, to: nil)).insetBy(dx: -horizontalOutset, dy: 0)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        owner.refreshHeaderVisibility()
    }

    private func detach() {
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
        if let owner = panel.contentPanel, owner.menuBarHeaderPanel === panel {
            owner.menuBarHeaderPanel = nil
            owner.refreshHeaderVisibility()
        }
        panel.contentPanel = nil
        panel.orderOut(nil)
    }

    func tearDown() {
        tornDown = true
        detach()
        host.rootView = AnyView(EmptyView())
        panel.contentView = nil
        panel.close()
    }
}
