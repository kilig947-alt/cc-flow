import Foundation
import XCTest
@testable import CC_FLOW

final class SessionCompletionStateEvaluatorTests: XCTestCase {
    func testOpenCodeAssistantHookMessageQualifiesForCompletionNotificationAfterIdle() {
        var session = SessionState(
            sessionId: "opencode:session-1",
            cwd: "/tmp/project",
            provider: .opencode,
            phase: .processing
        )
        let event = HookEvent(
            sessionId: session.sessionId,
            cwd: session.cwd,
            event: "message.part.updated",
            status: "processing",
            provider: .opencode,
            clientInfo: .default(for: .opencode),
            pid: nil,
            tty: nil,
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: "message.part.updated",
            message: "选哪个？",
            messageId: "message-1",
            messageRole: "assistant"
        )

        SessionStore.applyOpenCodeHookMessage("选哪个？", event: event, to: &session)
        session.phase = .waitingForInput

        XCTAssertEqual(session.conversationInfo.lastMessageRole, "assistant")
        XCTAssertEqual(session.chatItems.last?.type, .assistant("选哪个？"))
        XCTAssertTrue(SessionCompletionStateEvaluator.isCompletedReadySession(session))
        XCTAssertTrue(
            SessionCompletionNotificationPolicy.shouldQueueCompletedNotification(
                for: session,
                previousPhase: .processing,
                isEnabled: true
            )
        )
    }

    func testFollowUpDeliveryRouteUsesTmuxEvidence() {
        var directSession = SessionState(sessionId: "tmux", cwd: "/tmp", provider: .claude)
        directSession.isInTmux = true
        let fallbackSession = SessionState(sessionId: "plain", cwd: "/tmp", provider: .codex)

        XCTAssertEqual(FollowUpMessageDeliveryRoute.resolve(for: directSession), .direct)
        XCTAssertEqual(FollowUpMessageDeliveryRoute.resolve(for: fallbackSession), .focusPasteAndSubmit)
    }

    func testReturnToSessionDistinguishesTerminalFromApp() {
        let terminalSession = SessionState(
            sessionId: "terminal-return",
            cwd: "/tmp/project",
            provider: .codex,
            clientInfo: SessionClientInfo(
                kind: .codex,
                terminalBundleIdentifier: "com.mitchellh.ghostty"
            ),
            tty: "ttys010"
        )
        let appSession = SessionState(
            sessionId: "app-return",
            cwd: "/tmp/project",
            provider: .codex,
            clientInfo: SessionClientInfo(
                kind: .codex,
                bundleIdentifier: "com.openai.codex"
            )
        )

        XCTAssertTrue(SessionLauncher.isTerminalBacked(terminalSession))
        XCTAssertFalse(SessionLauncher.isTerminalBacked(appSession))
    }

    func testCompletedAssistantReplyRejectsToolOnlyTail() {
        let session = SessionState(
            sessionId: "tool-tail",
            cwd: "/tmp/project",
            phase: .waitingForInput,
            chatItems: [
                ChatHistoryItem(id: "1", type: .assistant("我先去执行工具。"), timestamp: Date(timeIntervalSince1970: 1)),
                ChatHistoryItem(
                    id: "2",
                    type: .toolCall(
                        ToolCallItem(
                            name: "Read",
                            input: ["path": "/tmp/project/file.swift"],
                            status: .success,
                            result: "done",
                            structuredResult: nil,
                            subagentTools: []
                        )
                    ),
                    timestamp: Date(timeIntervalSince1970: 2)
                )
            ],
            conversationInfo: ConversationInfo(
                summary: nil,
                lastMessage: "我先去执行工具。",
                lastMessageRole: "assistant",
                lastToolName: "Read",
                firstUserMessage: "看看这个文件",
                lastUserMessageDate: nil
            )
        )

        XCTAssertFalse(SessionCompletionStateEvaluator.hasCompletedAssistantReply(for: session))
        XCTAssertFalse(SessionCompletionStateEvaluator.isCompletedReadySession(session))
    }

    func testCompletedReadySessionRequiresWaitingForInputAssistantReply() {
        let session = SessionState(
            sessionId: "assistant-tail",
            cwd: "/tmp/project",
            phase: .waitingForInput,
            chatItems: [
                ChatHistoryItem(id: "1", type: .user("修一下完成提示"), timestamp: Date(timeIntervalSince1970: 1)),
                ChatHistoryItem(id: "2", type: .assistant("已经修好了。"), timestamp: Date(timeIntervalSince1970: 2))
            ],
            conversationInfo: ConversationInfo(
                summary: nil,
                lastMessage: "已经修好了。",
                lastMessageRole: "assistant",
                lastToolName: nil,
                firstUserMessage: "修一下完成提示",
                lastUserMessageDate: nil
            )
        )

        XCTAssertTrue(SessionCompletionStateEvaluator.hasCompletedAssistantReply(for: session))
        XCTAssertTrue(SessionCompletionStateEvaluator.isCompletedReadySession(session))
    }

    func testCompletedReadySessionFallsBackToAssistantConversationStateWithoutHistoryItems() {
        let session = SessionState(
            sessionId: "assistant-fallback",
            cwd: "/tmp/project",
            previewText: "最终答复",
            phase: .waitingForInput,
            conversationInfo: ConversationInfo(
                summary: nil,
                lastMessage: "最终答复",
                lastMessageRole: "assistant",
                lastToolName: nil,
                firstUserMessage: "给我最终结果",
                lastUserMessageDate: nil
            )
        )

        XCTAssertTrue(SessionCompletionStateEvaluator.hasCompletedAssistantReply(for: session))
        XCTAssertTrue(SessionCompletionStateEvaluator.isCompletedReadySession(session))
    }

    func testIdleAssistantReplyIsNotCompletedReadySession() {
        let session = SessionState(
            sessionId: "claude-idle-final",
            cwd: "/tmp/project",
            provider: .trae,
            phase: .idle,
            chatItems: [
                ChatHistoryItem(id: "1", type: .assistant("Done"), timestamp: Date(timeIntervalSince1970: 1))
            ]
        )

        XCTAssertTrue(SessionCompletionStateEvaluator.hasCompletedAssistantReply(for: session))
        XCTAssertFalse(SessionCompletionStateEvaluator.isCompletedReadySession(session))
    }

    func testCompletedReadySessionRejectsQuestionInterventionEvenWithAssistantReply() {
        let session = SessionState(
            sessionId: "question-intervention",
            cwd: "/tmp/project",
            intervention: SessionIntervention(
                id: "question-1",
                kind: .question,
                title: "需要补充信息",
                message: "请选择环境",
                options: [],
                questions: [],
                supportsSessionScope: false,
                metadata: [:]
            ),
            phase: .waitingForInput,
            chatItems: [
                ChatHistoryItem(id: "1", type: .assistant("还差一个问题需要你回答。"), timestamp: Date(timeIntervalSince1970: 1))
            ],
            conversationInfo: ConversationInfo(
                summary: nil,
                lastMessage: "还差一个问题需要你回答。",
                lastMessageRole: "assistant",
                lastToolName: nil,
                firstUserMessage: "继续",
                lastUserMessageDate: nil
            )
        )

        XCTAssertTrue(SessionCompletionStateEvaluator.hasCompletedAssistantReply(for: session))
        XCTAssertFalse(SessionCompletionStateEvaluator.isCompletedReadySession(session))
    }

    func testCompletionNotificationPolicyIgnoresOldUntrackedEndedSessions() {
        let now = Date()
        let session = SessionState(
            sessionId: "old-ended",
            cwd: "/tmp/project",
            phase: .ended,
            lastActivity: now,
            createdAt: now.addingTimeInterval(-2 * 60 * 60)
        )

        XCTAssertFalse(
            SessionCompletionNotificationPolicy.shouldQueueEndedNotification(
                for: session,
                previousPhase: nil,
                isEnabled: true,
                now: now
            )
        )
    }

    func testCompletionNotificationPolicyAllowsRecentUntrackedCompletedSessions() {
        let now = Date()
        let session = SessionState(
            sessionId: "recent-completed",
            cwd: "/tmp/project",
            phase: .waitingForInput,
            chatItems: [
                ChatHistoryItem(id: "assistant", type: .assistant("Done"), timestamp: now)
            ],
            createdAt: now.addingTimeInterval(-5)
        )

        XCTAssertTrue(
            SessionCompletionNotificationPolicy.shouldQueueCompletedNotification(
                for: session,
                previousPhase: nil,
                isEnabled: true,
                now: now
            )
        )
    }

    func testCompletionNotificationPolicyRejectsFakeNewUntrackedCompletedSessionWithOldActivity() {
        let now = Date()
        let session = SessionState(
            sessionId: "fake-new-completed",
            cwd: "/tmp/project",
            provider: .trae,
            clientInfo: SessionClientInfo.default(for: .trae),
            phase: .idle,
            chatItems: [
                ChatHistoryItem(id: "assistant", type: .assistant("Done earlier"), timestamp: now.addingTimeInterval(-3_600))
            ],
            lastActivity: now.addingTimeInterval(-3_600),
            createdAt: now.addingTimeInterval(-5)
        )

        XCTAssertFalse(
            SessionCompletionNotificationPolicy.shouldQueueCompletedNotification(
                for: session,
                previousPhase: nil,
                isEnabled: true,
                now: now
            )
        )
    }

    func testCompletionNotificationPolicyAllowsTrackedEndedTransition() {
        let session = SessionState(
            sessionId: "tracked-ended",
            cwd: "/tmp/project",
            phase: .ended,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(
            SessionCompletionNotificationPolicy.shouldQueueEndedNotification(
                for: session,
                previousPhase: .processing,
                isEnabled: true
            )
        )
    }
}
