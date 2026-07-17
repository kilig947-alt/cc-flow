import XCTest
@testable import CC_FLOW

final class CompactBroadcastCoordinatorTests: XCTestCase {
    func testLatestSameSideBroadcastReplacesImmediatelyAndConsumeClears() {
        var state = CompactBroadcastQueueState()
        state.enqueue(makeBroadcast(key: "feature-a", side: .leftFeature))
        state.enqueue(makeBroadcast(key: "session-a", side: .session))
        state.enqueue(makeBroadcast(key: "feature-b", side: .leftFeature))

        XCTAssertEqual(state.activeLeftFeature?.deduplicationKey, "feature-b")
        XCTAssertEqual(state.activeSession?.deduplicationKey, "session-a")

        state.consume(.leftFeature)

        XCTAssertNil(state.activeLeftFeature)
        XCTAssertEqual(state.activeSession?.deduplicationKey, "session-a")
    }

    func testSameTargetReplacesActiveBroadcast() {
        var state = CompactBroadcastQueueState()
        state.enqueue(makeBroadcast(key: "session-a", side: .session, summary: "old"))
        state.enqueue(makeBroadcast(key: "session-a", side: .session, summary: "new"))

        XCTAssertEqual(state.activeSession?.summary, "new")
    }

    func testClearDropsBothActiveSlots() {
        var state = CompactBroadcastQueueState()
        state.enqueue(makeBroadcast(key: "feature-a", side: .leftFeature))
        state.enqueue(makeBroadcast(key: "feature-b", side: .leftFeature))
        state.enqueue(makeBroadcast(key: "session-a", side: .session))

        state.clear()

        XCTAssertNil(state.activeLeftFeature)
        XCTAssertNil(state.activeSession)
    }

    func testExpiredAndInvalidNewBroadcastsDoNotReplaceCurrentSlot() {
        let now = Date()
        var state = CompactBroadcastQueueState()
        let active = makeBroadcast(key: "active", side: .session, createdAt: now)
        let expired = makeBroadcast(key: "expired", side: .session, createdAt: now.addingTimeInterval(-10))
        let invalid = makeBroadcast(key: "invalid", side: .session, createdAt: now)

        state.enqueue(active, now: now)
        state.enqueue(expired, now: now)
        state.enqueue(invalid, now: now) { $0 != invalid.target }

        XCTAssertEqual(state.activeSession?.deduplicationKey, "active")
    }

    @MainActor
    func testReplacementGetsItsOwnDismissalLifetimeAndHasNoSuccessor() async throws {
        let coordinator = CompactBroadcastCoordinator(displayDuration: 0.1)
        coordinator.enqueue(makeBroadcast(key: "old", side: .session))
        try await Task.sleep(for: .milliseconds(60))

        coordinator.enqueue(makeBroadcast(key: "new", side: .session))
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(coordinator.activeSession?.deduplicationKey, "new")

        try await Task.sleep(for: .milliseconds(70))
        XCTAssertNil(coordinator.activeSession)
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
