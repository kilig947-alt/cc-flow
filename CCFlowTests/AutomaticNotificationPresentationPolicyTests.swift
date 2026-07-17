import XCTest
@testable import CC_FLOW

final class AutomaticNotificationPresentationPolicyTests: XCTestCase {
    func testActiveExpandsWithoutSmartSuppression() {
        XCTAssertEqual(resolve(mode: .active), .expand)
    }

    func testActiveDowngradesToBroadcastWhenSmartSuppressedAndClosed() {
        XCTAssertEqual(resolve(mode: .active, smart: true), .broadcast)
    }

    func testActiveAlreadyOpenRoutesNormallyDespiteSmartSuppression() {
        XCTAssertEqual(resolve(mode: .active, smart: true, open: true), .expand)
    }

    func testQuietBroadcastsRegardlessOfSmartSuppression() {
        XCTAssertEqual(resolve(mode: .quiet), .broadcast)
        XCTAssertEqual(resolve(mode: .quiet, smart: true), .broadcast)
    }

    func testQuietDefersWhilePanelIsOpen() {
        XCTAssertEqual(resolve(mode: .quiet, open: true), .defer)
    }

    func testFullscreenDefersAndReminderMuteDiscards() {
        XCTAssertEqual(resolve(mode: .active, fullscreen: true), .defer)
        XCTAssertEqual(resolve(mode: .quiet, fullscreen: true), .defer)
        XCTAssertEqual(resolve(mode: .active, muted: true), .discard)
        XCTAssertEqual(resolve(mode: .quiet, muted: true), .discard)
    }

    func testFullscreenRecoveryRestoresModeSpecificDelivery() {
        XCTAssertEqual(resolve(mode: .active, fullscreen: true), .defer)
        XCTAssertEqual(resolve(mode: .active, fullscreen: false), .expand)

        XCTAssertEqual(resolve(mode: .quiet, fullscreen: true), .defer)
        XCTAssertEqual(resolve(mode: .quiet, fullscreen: false), .broadcast)
    }

    private func resolve(
        mode: NotificationPresentationMode,
        smart: Bool = false,
        open: Bool = false,
        fullscreen: Bool = false,
        muted: Bool = false
    ) -> AutomaticNotificationPresentationDecision {
        AutomaticNotificationPresentationPolicy.resolve(
            mode: mode,
            smartSuppressionTriggered: smart,
            isPanelOpen: open,
            isFullscreenSuppressed: fullscreen,
            isReminderMuted: muted
        )
    }
}
