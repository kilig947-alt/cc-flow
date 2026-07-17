import XCTest
@testable import CC_FLOW

final class CompactBroadcastCoordinatorTests: XCTestCase {
    func testSidesAdvanceIndependently() {
        var state = CompactBroadcastQueueState()
        state.enqueue(makeBroadcast(key: "feature-a", side: .leftFeature))
        state.enqueue(makeBroadcast(key: "session-a", side: .session))
        state.enqueue(makeBroadcast(key: "feature-b", side: .leftFeature))

        XCTAssertEqual(state.activeLeftFeature?.deduplicationKey, "feature-a")
        XCTAssertEqual(state.activeSession?.deduplicationKey, "session-a")
        XCTAssertEqual(state.queuedCount(for: .leftFeature), 1)

        state.consume(.leftFeature)

        XCTAssertEqual(state.activeLeftFeature?.deduplicationKey, "feature-b")
        XCTAssertEqual(state.activeSession?.deduplicationKey, "session-a")
    }

    func testSameTargetReplacesActiveBroadcast() {
        var state = CompactBroadcastQueueState()
        state.enqueue(makeBroadcast(key: "session-a", side: .session, summary: "old"))
        state.enqueue(makeBroadcast(key: "session-a", side: .session, summary: "new"))

        XCTAssertEqual(state.activeSession?.summary, "new")
        XCTAssertEqual(state.queuedCount(for: .session), 0)
    }

    func testClearDropsBothActiveItemsAndQueues() {
        var state = CompactBroadcastQueueState()
        state.enqueue(makeBroadcast(key: "feature-a", side: .leftFeature))
        state.enqueue(makeBroadcast(key: "feature-b", side: .leftFeature))
        state.enqueue(makeBroadcast(key: "session-a", side: .session))

        state.clear()

        XCTAssertNil(state.activeLeftFeature)
        XCTAssertNil(state.activeSession)
        XCTAssertEqual(state.queuedCount(for: .leftFeature), 0)
        XCTAssertEqual(state.queuedCount(for: .session), 0)
    }

    func testExpiredAndInvalidQueuedItemsAreSkippedWhenAdvancing() {
        let now = Date()
        var state = CompactBroadcastQueueState()
        let active = makeBroadcast(key: "active", side: .session, createdAt: now)
        let expired = makeBroadcast(key: "expired", side: .session, createdAt: now.addingTimeInterval(-10))
        let invalid = makeBroadcast(key: "invalid", side: .session, createdAt: now)
        let valid = makeBroadcast(key: "valid", side: .session, createdAt: now)

        state.enqueue(active, now: now)
        state.enqueue(expired, now: now.addingTimeInterval(-10))
        state.enqueue(invalid, now: now)
        state.enqueue(valid, now: now)
        state.consume(.session, now: now) { $0 != invalid.target }

        XCTAssertEqual(state.activeSession?.deduplicationKey, "valid")
    }

    private func makeBroadcast(
        key: String,
        side: CompactBroadcastSide,
        summary: String = "summary",
        createdAt: Date = Date()
    ) -> CompactBroadcast {
        let target: CompactBroadcastTarget = side == .leftFeature
            ? .leftFeature(id: key)
            : .session(stableID: key)
        return CompactBroadcast(
            deduplicationKey: key,
            side: side,
            target: target,
            iconName: "bell.fill",
            summary: summary,
            createdAt: createdAt
        )
    }
}
