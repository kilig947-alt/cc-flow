import XCTest
@testable import CC_FLOW

@MainActor
final class SessionAuditStoreTests: XCTestCase {
    func testAuditModeIsSessionLocalAndDefaultsToPartial() {
        let store = SessionAuditStore.shared
        let firstSessionID = "audit-mode-a-\(UUID().uuidString)"
        let secondSessionID = "audit-mode-b-\(UUID().uuidString)"

        XCTAssertEqual(store.mode(for: firstSessionID), .partial)
        XCTAssertTrue(store.allowsAutomaticPresentation(for: firstSessionID))
        store.setMode(.skipped, for: firstSessionID)
        XCTAssertEqual(store.mode(for: firstSessionID), .skipped)
        XCTAssertFalse(store.allowsAutomaticPresentation(for: firstSessionID))
        XCTAssertEqual(store.mode(for: secondSessionID), .partial)
    }

    func testRecordsRoundTripAndRemainGroupedBySession() throws {
        let first = SessionAuditRecord(
            sessionId: "session-a",
            createdAt: Date(timeIntervalSince1970: 10),
            kind: .approval,
            platformName: "Codex",
            requestTitle: "Bash",
            requestContent: "npm install",
            submittedMessage: "允许",
            resultLabel: "已允许"
        )
        let second = SessionAuditRecord(
            sessionId: "session-b",
            createdAt: Date(timeIntervalSince1970: 20),
            kind: .question,
            platformName: "Claude Code",
            requestTitle: "请选择",
            requestContent: "A 或 B",
            submittedMessage: "A",
            resultLabel: "已回答"
        )

        let records = [
            "session-a": [first],
            "session-b": [second],
        ]
        let data = try XCTUnwrap(SessionAuditStore.encodedData(records))
        let decoded = SessionAuditStore.decodedRecords(from: data)

        XCTAssertEqual(decoded["session-a"], [first])
        XCTAssertEqual(decoded["session-b"], [second])
        XCTAssertNil(decoded["missing"])
    }

    func testSecretQuestionAnswerIsRedactedFromAuditMessage() {
        let question = SessionInterventionQuestion(
            id: "password",
            header: "Password",
            prompt: "请输入密码",
            detail: nil,
            options: [],
            allowsMultiple: false,
            allowsOther: true,
            isSecret: true
        )

        let message = SessionMonitor.auditAnswerMessage(
            questions: [question],
            answers: ["password": ["super-secret"]],
            preferredMessage: "super-secret"
        )

        XCTAssertEqual(message, "请输入密码：[已隐藏敏感回答]")
        XCTAssertFalse(message.contains("super-secret"))
    }
}
