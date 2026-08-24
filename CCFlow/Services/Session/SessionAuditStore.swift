import Combine
import Foundation

enum SessionAuditMode: String, CaseIterable, Sendable {
    case unrestricted
    case partial
    case skipped

    var title: String {
        switch self {
        case .unrestricted: return "完全放任"
        case .partial: return "部分允许"
        case .skipped: return "完全跳过"
        }
    }

    var systemImage: String {
        switch self {
        case .unrestricted: return "bolt.shield"
        case .partial: return "checkmark.shield"
        case .skipped: return "forward.end"
        }
    }
}

@MainActor
final class SessionAuditStore: ObservableObject {
    static let shared = SessionAuditStore()

    @Published private(set) var recordsBySession: [String: [SessionAuditRecord]]
    /// Session-local by design: a new AI session always starts in the safer
    /// partial-review mode, even though its audit records remain persisted.
    @Published private(set) var modesBySession: [String: SessionAuditMode] = [:]

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
            ?? BridgeRuntimePaths.runtimeDirectoryURL.appendingPathComponent(
                "session-audit-records.json"
            )
        recordsBySession = Self.load(from: self.fileURL)
    }

    func records(for sessionId: String) -> [SessionAuditRecord] {
        recordsBySession[sessionId, default: []]
            .sorted { $0.createdAt > $1.createdAt }
    }

    func append(_ record: SessionAuditRecord) {
        var sessionRecords = recordsBySession[record.sessionId, default: []]
        sessionRecords.append(record)
        recordsBySession[record.sessionId] = sessionRecords
        persist()
    }

    func mode(for sessionId: String) -> SessionAuditMode {
        modesBySession[sessionId] ?? .partial
    }

    func setMode(_ mode: SessionAuditMode, for sessionId: String) {
        modesBySession[sessionId] = mode
    }

    func allowsAutomaticPresentation(for sessionId: String) -> Bool {
        mode(for: sessionId) != .skipped
    }

    func removeRecords(for sessionId: String) {
        recordsBySession[sessionId] = nil
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let data = Self.encodedData(recordsBySession) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private nonisolated static func load(
        from fileURL: URL
    ) -> [String: [SessionAuditRecord]] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return decodedRecords(from: data)
    }

    nonisolated static func encodedData(
        _ records: [String: [SessionAuditRecord]]
    ) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(records)
    }

    nonisolated static func decodedRecords(
        from data: Data
    ) -> [String: [SessionAuditRecord]] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode(
            [String: [SessionAuditRecord]].self,
            from: data
        )) ?? [:]
    }
}
