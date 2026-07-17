import XCTest
@testable import CC_FLOW

final class SessionManualAttentionTrackerTests: XCTestCase {
    func testPeekDoesNotConsumeUntilAcknowledged() {
        var tracker = SessionManualAttentionTracker()
        let session = makeApprovalSession(toolUseId: "tool-1")

        XCTAssertEqual(tracker.nextAttentionSession(from: [session])?.stableId, session.stableId)
        XCTAssertEqual(tracker.nextAttentionSession(from: [session])?.stableId, session.stableId)

        tracker.acknowledge(session)

        XCTAssertNil(tracker.nextAttentionSession(from: [session]))
    }

    func testAcknowledgingOneSimultaneousSessionAdvancesToTheOther() {
        var tracker = SessionManualAttentionTracker()
        let older = makeApprovalSession(sessionId: "older", toolUseId: "tool-1", receivedAt: Date(timeIntervalSince1970: 1))
        let newer = makeApprovalSession(sessionId: "newer", toolUseId: "tool-2", receivedAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(tracker.nextAttentionSession(from: [older, newer])?.stableId, newer.stableId)
        tracker.acknowledge(newer)
        XCTAssertEqual(tracker.nextAttentionSession(from: [older, newer])?.stableId, older.stableId)
    }

    func testTerminalRoutedPromptTriggersAttentionNotification() {
        var tracker = SessionManualAttentionTracker()
        let session = SessionState(
            sessionId: "terminal-routed-question",
            cwd: "/tmp/project",
            suppressInAppPromptControls: true,
            phase: .waitingForInput
        )

        XCTAssertEqual(
            tracker.consumeNewAttentionSession(from: [session])?.stableId,
            session.stableId
        )
        XCTAssertNil(tracker.consumeNewAttentionSession(from: [session]))
    }

    func testApprovalToolUseRefreshInSameSessionTriggersAttentionAgain() {
        var tracker = SessionManualAttentionTracker()
        let firstApproval = makeApprovalSession(toolUseId: "tool-1")
        let secondApproval = makeApprovalSession(toolUseId: "tool-2")

        XCTAssertEqual(
            tracker.consumeNewAttentionSession(from: [firstApproval])?.stableId,
            firstApproval.stableId
        )
        XCTAssertNil(tracker.consumeNewAttentionSession(from: [firstApproval]))
        XCTAssertEqual(
            tracker.consumeNewAttentionSession(from: [secondApproval])?.stableId,
            secondApproval.stableId
        )
    }

    private func makeApprovalSession(
        sessionId: String = "trae-session",
        toolUseId: String,
        receivedAt: Date = Date()
    ) -> SessionState {
        SessionState(
            sessionId: sessionId,
            cwd: "/tmp/project",
            provider: .trae,
            clientInfo: SessionClientInfo(
                kind: .trae,
                profileID: "trae",
                name: "TRAE"
            ),
            phase: .waitingForApproval(PermissionContext(
                toolUseId: toolUseId,
                toolName: "ExitPlanMode",
                toolInput: ["plan": AnyCodable("Plan text")],
                receivedAt: receivedAt
            ))
        )
    }
}
