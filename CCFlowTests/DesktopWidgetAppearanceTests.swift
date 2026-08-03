import AppKit
import XCTest
@testable import CC_FLOW

@MainActor
final class DesktopWidgetAppearanceTests: XCTestCase {
    func testDesktopWidgetPanelForcesDarkAppearance() {
        let panel = DesktopWidgetPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300)
        )

        XCTAssertEqual(panel.appearance?.name, .darkAqua)
    }

    func testReminderAgendaItemCarriesDisplayableDetails() {
        let url = URL(string: "https://example.com/details")!
        let reminder = ReminderAgendaItem(
            id: "reminder-1",
            title: "提交报告",
            dueDate: Date(timeIntervalSince1970: 1_720_008_000),
            priority: 1,
            notes: "附上本周数据",
            url: url,
            calendarName: "工作"
        )

        XCTAssertEqual(reminder.notes, "附上本周数据")
        XCTAssertEqual(reminder.url, url)
        XCTAssertEqual(reminder.calendarName, "工作")
    }

    func testBottomResizeUpwardKeepsTopEdgeFixed() {
        let start = NSRect(x: 100, y: 100, width: 500, height: 400)
        let resized = DesktopWidgetFrameResizer.resizedFrame(
            from: start,
            edge: .bottom,
            translation: CGSize(width: 0, height: -120),
            minimumSize: NSSize(width: 320, height: 220)
        )

        XCTAssertEqual(resized.maxY, start.maxY)
        XCTAssertEqual(resized.height, 280)
        XCTAssertEqual(resized.minY, 220)
    }

    func testDesktopWidgetResizeClampsSizeWithoutMovingAnchoredEdges() {
        let start = NSRect(x: 100, y: 100, width: 500, height: 400)
        let resized = DesktopWidgetFrameResizer.resizedFrame(
            from: start,
            edge: .bottomLeft,
            translation: CGSize(width: 400, height: -300),
            minimumSize: NSSize(width: 320, height: 220)
        )

        XCTAssertEqual(resized.maxX, start.maxX)
        XCTAssertEqual(resized.maxY, start.maxY)
        XCTAssertEqual(resized.size, NSSize(width: 320, height: 220))
    }

    func testOnlyWebBackedFeaturesSupportHeaderDoubleClickReload() {
        XCTAssertTrue(LeftFeatureKind.webURL(url: "https://example.com").supportsDesktopWidgetReload)
        XCTAssertTrue(LeftFeatureKind.customArea(areaID: "area").supportsDesktopWidgetReload)
        XCTAssertTrue(LeftFeatureKind.mineradio(pageURL: "https://mineradio.art").supportsDesktopWidgetReload)
        XCTAssertFalse(LeftFeatureKind.calendar.supportsDesktopWidgetReload)
    }
}
