import XCTest
@testable import CC_FLOW

final class NotificationDeliveryPolicyTests: XCTestCase {
    func testUndeliveredIDsRemainAvailableUntilAcknowledged() {
        var state = SessionPendingDeliveryState()
        let current: Set<String> = ["session-a"]

        XCTAssertEqual(state.undelivered(currentIDs: current), current)
        XCTAssertEqual(state.undelivered(currentIDs: current), current)

        state.acknowledge(current)

        XCTAssertTrue(state.undelivered(currentIDs: current).isEmpty)
    }

    func testDisappearedIDsArePrunedAndCanNotifyAgainLater() {
        var state = SessionPendingDeliveryState()
        state.acknowledge(["session-a"])

        XCTAssertTrue(state.undelivered(currentIDs: []).isEmpty)
        XCTAssertEqual(state.undelivered(currentIDs: ["session-a"]), ["session-a"])
    }

    func testExplicitDiscardAcknowledgesCurrentIDs() {
        var state = SessionPendingDeliveryState()
        state.discard(["session-a", "session-b"])

        XCTAssertTrue(state.undelivered(currentIDs: ["session-a", "session-b"]).isEmpty)
    }
}
