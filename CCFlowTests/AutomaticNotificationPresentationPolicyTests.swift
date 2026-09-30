import XCTest
@testable import CC_FLOW

final class AutomaticNotificationPresentationPolicyTests: XCTestCase {
    func testOpenFeatureDiscardsEveryPriorityInsteadOfDeferring() {
        for mode in [NotificationPresentationMode.active, .quiet] {
            for priority in [AutomaticNotificationPriority.standard, .manualAttention] {
                for fullscreen in [false, true] {
                    XCTAssertEqual(resolve(mode: mode, open: true, fullscreen: fullscreen,
                                           featureOpen: true, priority: priority), .discard)
                }
            }
        }
    }

    func testLeavingFeatureAllowsNewNotificationsWithoutReplayingDiscardedDelivery() {
        var delivery = SessionPendingDeliveryState()
        XCTAssertEqual(resolve(mode: .active, open: true, featureOpen: true), .discard)
        delivery.discard(["old"])
        XCTAssertEqual(resolve(mode: .active), .expand)
        XCTAssertEqual(delivery.undelivered(currentIDs: ["old", "new"]), ["new"])
    }

    func testActiveExpandsWithoutSmartSuppression() {
        XCTAssertEqual(resolve(mode: .active), .expand)
    }

    func testActiveDowngradesToBroadcastWhenSmartSuppressedAndClosed() {
        XCTAssertEqual(resolve(mode: .active, smart: true), .broadcast)
    }

    func testActiveAlreadyOpenRoutesNormallyDespiteSmartSuppression() {
        XCTAssertEqual(resolve(mode: .active, smart: true, open: true), .expand)
    }

    func testManualAttentionBypassesTerminalSmartSuppression() {
        XCTAssertEqual(
            resolve(mode: .active, smart: true, priority: .manualAttention),
            .expand
        )
    }

    func testManualAttentionStillHonorsExplicitQuietAndSafetySuppression() {
        XCTAssertEqual(
            resolve(mode: .quiet, smart: true, priority: .manualAttention),
            .broadcast
        )
        XCTAssertEqual(
            resolve(mode: .active, smart: true, fullscreen: true, priority: .manualAttention),
            .defer
        )
        XCTAssertEqual(
            resolve(mode: .active, smart: true, muted: true, priority: .manualAttention),
            .discard
        )
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
        muted: Bool = false,
        featureOpen: Bool = false,
        priority: AutomaticNotificationPriority = .standard
    ) -> AutomaticNotificationPresentationDecision {
        AutomaticNotificationPresentationPolicy.resolve(
            mode: mode,
            smartSuppressionTriggered: smart,
            isPanelOpen: open,
            isFullscreenSuppressed: fullscreen,
            isReminderMuted: muted,
            isLeftFeatureOpen: featureOpen,
            priority: priority
        )
    }
}
