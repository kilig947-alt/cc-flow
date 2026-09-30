import AppKit
import XCTest
import SwiftUI
@testable import CC_FLOW

@MainActor
final class NotchPanelTests: XCTestCase {
    func testSplitSurfacesPreserveDarkAppearanceUnderLightSystemTheme() {
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { NSApp.appearance = previousAppearance }
        let content = NotchPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        content.isReleasedWhenClosed = false
        let header = NotchHeaderPanel()
        let nativeContent = NSView()
        content.contentView = nativeContent
        defer { content.close(); header.close() }

        for expanded in [false, true, false] {
            content.setExpandedPresentation(expanded)
            for appearance in [content.effectiveAppearance, header.effectiveAppearance, nativeContent.effectiveAppearance] {
                XCTAssertEqual(appearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
            }
        }
    }

    func testExpandedPanelKeepsFloatingAboveAppsAndRestoresCompactLevel() {
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                               styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let spaces = panel.collectionBehavior
        XCTAssertEqual(panel.level, .statusBar)

        panel.setExpandedPresentation(true)
        XCTAssertEqual(panel.level, .statusBar, "Opening animation must stay on one surface until the header is ready")
        let header = NotchHeaderPanel()
        header.contentPanel = panel
        panel.menuBarHeaderPanel = header
        panel.refreshHeaderVisibility()
        XCTAssertEqual(panel.level, .statusBar, "An unlaid-out header must not trigger the handoff")
        header.setFrame(NSRect(x: 0, y: 468, width: 900, height: 32), display: false)
        panel.refreshHeaderVisibility()
        XCTAssertEqual(panel.level, .floating)
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertLessThan(panel.level.rawValue, NSWindow.Level.popUpMenu.rawValue)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertEqual(panel.collectionBehavior, spaces)
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))

        // Repeated presentation updates must not raise an editing panel again.
        panel.setExpandedPresentation(true)
        XCTAssertEqual(panel.level, .floating)
        panel.setExpandedPresentation(false)
        XCTAssertEqual(panel.level, .statusBar)
    }
    func testMenuBarHeaderHasIndependentLevelAndFollowsContentVisibility() {
        let content = NotchPanel(contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 500),
                                 styleMask: .borderless, backing: .buffered, defer: false)
        content.isReleasedWhenClosed = false
        let header = NotchHeaderPanel()
        header.setFrame(NSRect(x: -10000, y: -9500, width: 900, height: 32), display: false)
        header.contentPanel = content
        content.menuBarHeaderPanel = header
        defer { content.close() }

        content.setExpandedPresentation(true)
        content.orderFrontRegardless()
        XCTAssertEqual(content.level, .floating)
        XCTAssertEqual(header.level, .statusBar)
        XCTAssertGreaterThan(header.level.rawValue, NSWindow.Level.mainMenu.rawValue)
        XCTAssertNil(header.parent, "Child windows must not couple the two levels")
        XCTAssertFalse(header.canBecomeKey, "Header clicks must not steal the editor's keyboard focus")
        XCTAssertTrue(header.isVisible)

        content.setExpandedPresentation(false)
        XCTAssertFalse(header.isVisible)
        XCTAssertEqual(content.level, .statusBar)
        content.setExpandedPresentation(true)
        XCTAssertTrue(header.isVisible)
        content.orderOut(nil)
        XCTAssertFalse(header.isVisible)
        content.orderFrontRegardless()
        XCTAssertTrue(header.isVisible)
        content.close()
        XCTAssertFalse(header.isVisible)
    }

    func testHeaderAnchorMapsToScreenAndDetachesWithoutLeavingAWindow() throws {
        let content = NotchPanel(contentRect: NSRect(x: 200, y: 300, width: 900, height: 500),
                                 styleMask: .borderless, backing: .buffered, defer: false)
        content.isReleasedWhenClosed = false
        defer { content.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        content.contentView = root
        let anchor = NotchHeaderAnchorView(frame: NSRect(x: 100, y: 468, width: 700, height: 32))
        anchor.horizontalOutset = 20
        anchor.setContent(AnyView(Text("Feature switcher")))
        root.addSubview(anchor)
        anchor.layout()
        let header = try XCTUnwrap(content.menuBarHeaderPanel)
        XCTAssertEqual(header.frame, NSRect(x: 280, y: 768, width: 740, height: 32))
        XCTAssertFalse(header.ignoresMouseEvents)
        XCTAssertTrue(header.contentView?.acceptsFirstMouse(for: nil) == true)
        let originalFrame = header.frame
        anchor.setFrameOrigin(NSPoint(x: 80, y: 468))
        anchor.setFrameSize(NSSize(width: 740, height: 32))
        XCTAssertEqual(header.frame, originalFrame, "Do not expose partial origin/size updates before layout commits")
        anchor.layout()
        XCTAssertEqual(header.frame, NSRect(x: 260, y: 768, width: 780, height: 32))
        anchor.tearDown()
        XCTAssertNil(content.menuBarHeaderPanel)
        XCTAssertFalse(header.isVisible)
        XCTAssertNil(header.contentView)
    }

}
