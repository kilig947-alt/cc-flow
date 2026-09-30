//
//  NotchWindow.swift
//  CCFlow
//
//  Transparent window that overlays the notch area.
//  Mouse-event ignoring is managed dynamically by NotchWindowController
//  based on real-time mouse position — when the cursor is inside the
//  Flow Island content area, ignoresMouseEvents is set to false so
//  SwiftUI buttons can respond; when the cursor is outside, it is set
//  to true so clicks pass through to windows behind the panel.
//

import AppKit

// Use NSPanel subclass for non-activating behavior
class NotchPanel: NSPanel {
    weak var menuBarHeaderPanel: NotchHeaderPanel?
    private var expandedPresentation = false

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Floating panel behavior
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true

        // Transparent configuration
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        // Match NotchView's dark theme at the AppKit boundary as well, including
        // embedded web views when the panel changes level or keyboard focus.
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = false

        // CRITICAL: Prevent window from moving during space switches
        isMovable = false

        // Window behavior - stays on all spaces, above menu bar
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        // Compact presentation stays above the menu bar. Expanded, interactive content
        // uses the floating tier instead; IME window levels vary between input methods.
        level = .statusBar

        // Enable tooltips even when app is inactive (needed for panel windows)
        allowsToolTipsWhenApplicationIsInactive = true

        // Default: ignore all mouse events.
        // NotchWindowController dynamically toggles this to false when
        // the mouse is inside the actual content area and the panel is opened.
        ignoresMouseEvents = true

        isReleasedWhenClosed = true
        acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func setExpandedPresentation(_ expanded: Bool) {
        expandedPresentation = expanded
        refreshHeaderVisibility()
    }

    func refreshHeaderVisibility() {
        // During expansion the original single surface owns the whole animation.
        // Lower the body only after the replacement header has a usable frame.
        let headerReady = expandedPresentation && menuBarHeaderPanel.map { !$0.frame.isEmpty } == true
        if headerReady && isVisible {
            if let header = menuBarHeaderPanel, !header.isVisible { header.orderFrontRegardless() }
        } else {
            menuBarHeaderPanel?.orderOut(nil)
        }
        let target: NSWindow.Level = headerReady ? .floating : .statusBar
        if level != target { level = target }
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        refreshHeaderVisibility()
    }

    override func orderOut(_ sender: Any?) {
        menuBarHeaderPanel?.orderOut(sender)
        super.orderOut(sender)
    }

    override func close() {
        menuBarHeaderPanel?.orderOut(nil)
        menuBarHeaderPanel?.close()
        super.close()
    }

    override func sendEvent(_ event: NSEvent) {
        #if DEBUG
        if [.leftMouseDown, .leftMouseUp].contains(event.type),
           let controller = windowController as? NotchWindowController,
           controller.viewModel.contentType == .customExpanded,
           LeftFeatureStore.shared.expandedActiveFeature?.id == LeftFeature.giflowID {
            let hit = contentView.flatMap { view in
                view.hitTest(view.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
            }
            GiflowInteractionDiagnostics.record("panel \(event.type.rawValue) window=\(windowNumber) point=\(event.locationInWindow) active=\(NSApp.isActive) key=\(isKeyWindow) ignores=\(ignoresMouseEvents) hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
        }
        #endif
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            if !isKeyWindow {
                makeKey()
            }
        }
        super.sendEvent(event)
    }
}
