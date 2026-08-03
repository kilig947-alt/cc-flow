import Foundation

/// Reads the title index maintained by Codex for `/status`'s "Thread name".
///
/// Codex hook payloads identify the thread but do not consistently include its
/// display name. The app already receives that same thread ID, so this index is
/// the authoritative local bridge between a hook session and its user-visible
/// title.
nonisolated struct CodexSessionTitleIndex {
    private struct Entry: Decodable {
        let id: String
        let threadName: String

        private enum CodingKeys: String, CodingKey {
            case id
            case threadName = "thread_name"
        }
    }

    private struct Fingerprint: Equatable {
        let fileSize: UInt64
        let modificationDate: Date?
    }

    private let indexURL: URL
    private let fileManager: FileManager
    private var fingerprint: Fingerprint?
    private var titlesBySessionID: [String: String] = [:]

    init(
        indexURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl"),
        fileManager: FileManager = .default
    ) {
        self.indexURL = indexURL
        self.fileManager = fileManager
    }

    mutating func title(for sessionID: String) -> String? {
        reloadIfNeeded()

        let normalizedID = sessionID.hasPrefix("codex:")
            ? String(sessionID.dropFirst("codex:".count))
            : sessionID
        return titlesBySessionID[normalizedID]
    }

    private mutating func reloadIfNeeded() {
        guard let attributes = try? fileManager.attributesOfItem(atPath: indexURL.path),
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value else {
            fingerprint = nil
            titlesBySessionID = [:]
            return
        }

        let currentFingerprint = Fingerprint(
            fileSize: fileSize,
            modificationDate: attributes[.modificationDate] as? Date
        )
        guard currentFingerprint != fingerprint else { return }

        guard let data = try? Data(contentsOf: indexURL),
              let contents = String(data: data, encoding: .utf8) else {
            return
        }

        let decoder = JSONDecoder()
        var refreshedTitles: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(Entry.self, from: lineData),
                  let title = Self.sanitizedTitle(entry.threadName) else {
                continue
            }
            // Codex may append a renamed thread with the same ID; the last
            // valid entry is the newest one.
            refreshedTitles[entry.id] = title
        }

        titlesBySessionID = refreshedTitles
        fingerprint = currentFingerprint
    }

    private static func sanitizedTitle(_ title: String) -> String? {
        let cleaned = title
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
