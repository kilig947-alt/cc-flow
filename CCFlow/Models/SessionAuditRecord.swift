import Foundation

enum SessionAuditKind: String, Codable, Sendable {
    case approval
    case question
}

struct SessionAuditRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let sessionId: String
    let createdAt: Date
    let kind: SessionAuditKind
    let platformName: String
    let requestTitle: String
    let requestContent: String
    let submittedMessage: String
    let resultLabel: String

    /// Scoped compatibility for audit records written before stable localization keys.
    /// Request content and submitted messages remain verbatim historical data.
    nonisolated var resultLabelKey: String {
        let legacyKeys: [String: String] = [
            "已跳过 · 自动允许": "session.skipped_automatically_allowed",
            "自动允许": "session.automatically_allow",
            "允许相同操作 · 自动": "session.allow_matching_actions_automatic",
            "外部已允许": "session.allowed_externally",
            "允许本会话所有操作": "session.allow_all_actions_in_this_session",
            "允许相同操作 · 手动": "session.allow_matching_actions_manual",
            "已允许": "session.allowed",
            "已拒绝": "common.denied",
            "已跳过 · 自动": "session.skipped_automatic",
            "已跳过": "session.skipped",
            "已回答": "session.answered",
            "允许相同操作": "session.allow_matching_actions",
            "自动允许相同操作": "session.automatically_allow_matching_actions",
        ]
        let key = legacyKeys[resultLabel] ?? resultLabel
        switch key {
        case "session.allow_matching_actions": return "session.allow_matching_actions_manual"
        case "session.automatically_allow_matching_actions": return "session.allow_matching_actions_automatic"
        default: return key
        }
    }

    nonisolated init(
        id: UUID = UUID(),
        sessionId: String,
        createdAt: Date = Date(),
        kind: SessionAuditKind,
        platformName: String,
        requestTitle: String,
        requestContent: String,
        submittedMessage: String,
        resultLabel: String
    ) {
        self.id = id
        self.sessionId = sessionId
        self.createdAt = createdAt
        self.kind = kind
        self.platformName = platformName
        self.requestTitle = requestTitle
        self.requestContent = requestContent
        self.submittedMessage = submittedMessage
        self.resultLabel = resultLabel
    }
}
