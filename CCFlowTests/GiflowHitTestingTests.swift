import AppKit
import SwiftUI
import XCTest
@testable import CC_FLOW

@MainActor
final class GiflowHitTestingTests: XCTestCase {
    func testUnchangedGIFDoesNotReloadOnParentUpdates() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gif-refresh-\(UUID()).gif")
        try Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let view = GifImageView(url: url)
        let imageView = view.makeImageView()
        let original = try XCTUnwrap(imageView.image)
        for _ in 0..<100 { view.loadImage(into: imageView) }
        XCTAssertTrue(imageView.image === original, "Unrelated state updates must preserve the image and animation timeline")
        GifImageView(url: url.appendingPathExtension("missing")).loadImage(into: imageView)
        XCTAssertNil(imageView.image, "Changing source must not leave the old image visible")
    }

    func testPanelHitTestingUsesActualParentCoordinates() throws {
        let host = PassThroughHostingView(rootView: VStack {
            Button("复制") {}.frame(width: 80, height: 30)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        let window = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 1714, height: 1100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.hitTestRect = { CGRect(x: 407, y: 600, width: 900, height: 500) }
        host.layoutSubtreeIfNeeded()
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 857, y: 1085), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        XCTAssertTrue(host.acceptsFirstMouse(for: event), "Nonactivating panel controls must accept the first click")
        let point = host.superview!.convert(CGPoint(x: 857, y: 1085), from: nil)
        XCTAssertNotNil(host.hitTest(point), "Visible top button must receive clicks")
    }

    func testNativeGIFThumbnailDoesNotStealButtonHitWhenItsFrameOverlaps() {
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 850, height: 70))
        let button = NSButton(frame: CGRect(x: 790, y: 20, width: 60, height: 30))
        parent.addSubview(button)
        let thumbnail = GifImageView(url: URL(fileURLWithPath: "/nonexistent-thumbnail.gif")).makeImageView()
        // The live click trace hit NSImageView at the action buttons: simulate that
        // oversized native frame independently of SwiftUI's visual clipping.
        thumbnail.frame = CGRect(x: 0, y: -300, width: 1210, height: 817)
        parent.addSubview(thumbnail)

        XCTAssertTrue(parent.hitTest(CGPoint(x: 820, y: 35)) === button,
                      "A decorative GIF view must let the underlying button receive the click")
        XCTAssertNil(thumbnail.hitTest(CGPoint(x: 40, y: 35)),
                     "SwiftUI owns thumbnail dragging; the native image must not track mouse events")
    }
}
