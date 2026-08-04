import XCTest
@testable import CC_FLOW

final class HookEventResponseRoutingTests: XCTestCase {
    func testTerminalRoutedPermissionRequestStillExpectsResponse() {
        let event = HookEvent(
            sessionId: "claude-session",
            cwd: "/tmp/project",
            event: "PermissionRequest",
            status: "waiting_for_approval",
            provider: .trae,
            clientInfo: SessionClientInfo(kind: .trae, name: "TRAE"),
            pid: nil,
            tty: nil,
            tool: "Edit",
            toolInput: nil,
            toolUseId: nil,
            notificationType: nil,
            message: nil,
            suppressInAppPrompt: true
        )

        XCTAssertTrue(event.expectsResponse)
    }

    func testTerminalRoutedAskUserQuestionDoesNotExpectResponse() {
        let event = HookEvent(
            sessionId: "claude-session",
            cwd: "/tmp/project",
            event: "PreToolUse",
            status: "waiting_for_input",
            provider: .trae,
            clientInfo: SessionClientInfo(kind: .trae, name: "TRAE"),
            pid: nil,
            tty: nil,
            tool: "AskUserQuestion",
            toolInput: ["questions": AnyCodable([["question": "Pick one"]])],
            toolUseId: "question-tool",
            notificationType: nil,
            message: nil,
            suppressInAppPrompt: true
        )

        XCTAssertFalse(event.expectsResponse)
    }

    func testAutoApprovingPermissionDoesNotExposeIslandIntervention() {
        let approval = SessionIntervention(
            id: "tool-1",
            kind: .approval,
            title: "Approval Needed",
            message: "Run Bash?",
            options: [],
            questions: [],
            supportsSessionScope: true,
            metadata: [:]
        )
        let event = HookEvent(
            sessionId: "auto-approved-session",
            cwd: "/tmp/project",
            event: "PermissionRequest",
            status: "waiting_for_approval",
            provider: .codex,
            clientInfo: SessionClientInfo(kind: .codex, name: "Codex"),
            pid: nil,
            tty: nil,
            tool: "Bash",
            toolInput: nil,
            toolUseId: "tool-1",
            notificationType: nil,
            message: nil,
            bridgeIntervention: approval,
            isAutoApproving: true
        )

        XCTAssertNil(event.intervention)
        XCTAssertEqual(event.sessionPhase.isWaitingForApproval, true)
    }
}
