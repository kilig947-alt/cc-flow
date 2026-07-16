import Foundation

enum FileOrganizationAction: String, Sendable { case move }

struct FileActionPlan: Identifiable, Sendable {
    let id: UUID
    let action: FileOrganizationAction
    let source: URL
    let destination: URL
    let sourceSize: Int64
    let sourceModifiedAt: Date
    let sourceIdentifier: String
}

struct FileActionAudit: Identifiable, Sendable {
    let id: UUID
    let plan: FileActionPlan
    let executedAt: Date
    var undoneAt: Date?
}

enum FileActionError: LocalizedError {
    case sourceChanged, destinationExists, sourceMissing, undoConflict
    var errorDescription: String? {
        switch self {
        case .sourceChanged: "源文件在确认后已发生变化，请重新生成建议"
        case .destinationExists: "目标位置已有同名文件，未执行任何操作"
        case .sourceMissing: "源文件已不存在"
        case .undoConflict: "无法安全撤销：原位置或文件身份已变化"
        }
    }
}

actor FileActionExecutor {
    static let shared = FileActionExecutor()
    private(set) var audits: [FileActionAudit] = []

    nonisolated static func makePlan(for card: LocalFileCard) throws -> FileActionPlan {
        let values = try card.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        let category = card.tags.contains("截图") ? "截图" : card.tags.contains("图片") ? "图片" : card.tags.contains("文档") ? "文档" : "其他"
        let destination = card.url.deletingLastPathComponent().appendingPathComponent("CC FLOW 分类", isDirectory: true)
            .appendingPathComponent(category, isDirectory: true).appendingPathComponent(card.name)
        return FileActionPlan(id: UUID(), action: .move, source: card.url, destination: destination,
            sourceSize: Int64(values.fileSize ?? 0), sourceModifiedAt: values.contentModificationDate ?? .distantPast,
            sourceIdentifier: String(describing: values.fileResourceIdentifier))
    }

    func executeConfirmed(_ plan: FileActionPlan) throws -> FileActionAudit {
        guard FileManager.default.fileExists(atPath: plan.source.path) else { throw FileActionError.sourceMissing }
        guard !FileManager.default.fileExists(atPath: plan.destination.path) else { throw FileActionError.destinationExists }
        let values = try plan.source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        guard Int64(values.fileSize ?? -1) == plan.sourceSize,
              values.contentModificationDate == plan.sourceModifiedAt,
              String(describing: values.fileResourceIdentifier) == plan.sourceIdentifier else { throw FileActionError.sourceChanged }
        try FileManager.default.createDirectory(at: plan.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: plan.source, to: plan.destination)
        let audit = FileActionAudit(id: UUID(), plan: plan, executedAt: Date(), undoneAt: nil)
        audits.insert(audit, at: 0)
        return audit
    }

    func undo(_ auditID: UUID) throws {
        guard let index = audits.firstIndex(where: { $0.id == auditID && $0.undoneAt == nil }) else { throw FileActionError.undoConflict }
        let audit = audits[index]
        guard FileManager.default.fileExists(atPath: audit.plan.destination.path),
              !FileManager.default.fileExists(atPath: audit.plan.source.path) else { throw FileActionError.undoConflict }
        let values = try audit.plan.destination.resourceValues(forKeys: [.fileResourceIdentifierKey])
        guard String(describing: values.fileResourceIdentifier) == audit.plan.sourceIdentifier else { throw FileActionError.undoConflict }
        try FileManager.default.moveItem(at: audit.plan.destination, to: audit.plan.source)
        audits[index].undoneAt = Date()
    }
}
