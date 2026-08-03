import Combine
import Foundation

@MainActor
final class SessionAuditStore: ObservableObject {
    static let shared = SessionAuditStore()

    @Published private(set) var recordsBySession: [String: [SessionAuditRecord]]

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
