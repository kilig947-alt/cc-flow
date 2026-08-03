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
