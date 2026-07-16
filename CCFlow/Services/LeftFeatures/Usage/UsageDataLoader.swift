import Foundation

nonisolated enum UsageDataLoader {
    static let claudeStatusURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/cc-flow/claude-usage.json")
    private static let fileCache = FileParseCache()

    private struct FileFingerprint: Equatable, Sendable {
        var size: Int
        var modifiedAt: Date
    }

    private struct ClaudeRecord: Sendable {
        var timestamp: Date
        var messageID: String?
        var usage: TokenUsageTotal
    }

    private struct DatedTokenDelta: Sendable {
        var timestamp: Date?
        var usage: TokenUsageTotal
    }

    private struct CodexFileData: Sendable {
        var sessionID: String?
        var deltas: [DatedTokenDelta]
        var windows: [UsageWindow]
        var capturedAt: Date?
    }

    private final class FileParseCache: @unchecked Sendable {
        private struct ClaudeEntry: Sendable {
            var fingerprint: FileFingerprint
            var records: [ClaudeRecord]
        }

        private struct CodexEntry: Sendable {
            var fingerprint: FileFingerprint
            var data: CodexFileData
        }

        private let lock = NSLock()
        private var claude: [String: ClaudeEntry] = [:]
        private var codex: [String: CodexEntry] = [:]
        private var parseCount = 0

        func claudeRecords(
            for file: URL,
            fingerprint: FileFingerprint,
            shouldCache: () -> Bool,
            parse: () -> [ClaudeRecord]
        ) -> [ClaudeRecord] {
            lock.lock()
            if let entry = claude[file.path], entry.fingerprint == fingerprint {
                lock.unlock()
                return entry.records
            }
            lock.unlock()
            let records = parse()
            guard shouldCache() else { return records }
            lock.lock()
            claude[file.path] = ClaudeEntry(fingerprint: fingerprint, records: records)
            parseCount += 1
            lock.unlock()
            return records
        }

        func codexData(
            for file: URL,
            fingerprint: FileFingerprint,
            shouldCache: () -> Bool,
            parse: () -> CodexFileData
        ) -> CodexFileData {
            lock.lock()
            if let entry = codex[file.path], entry.fingerprint == fingerprint {
                lock.unlock()
                return entry.data
            }
            lock.unlock()
            let data = parse()
            guard shouldCache() else { return data }
            lock.lock()
            codex[file.path] = CodexEntry(fingerprint: fingerprint, data: data)
            parseCount += 1
            lock.unlock()
            return data
        }

        func reset() {
            lock.lock()
            claude.removeAll()
            codex.removeAll()
            parseCount = 0
            lock.unlock()
        }

        func retainClaude(paths: Set<String>) {
            lock.lock()
            claude = claude.filter { paths.contains($0.key) }
            lock.unlock()
        }

        func retainCodex(paths: Set<String>) {
            lock.lock()
            codex = codex.filter { paths.contains($0.key) }
            lock.unlock()
        }

        func currentParseCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return parseCount
        }
    }

    static func resetFileCacheForTesting() { fileCache.reset() }
    static var parsedFileCountForTesting: Int { fileCache.currentParseCount() }

    static func load(
        now: Date = Date(),
        fileManager: FileManager = .default,
        claudeRoot: URL? = nil,
        codexRoot: URL? = nil,
        codexArchivedRoot: URL? = nil,
        statusURL: URL? = nil,
        queryCodexAccount: Bool = true,
        currentSessionIDs: [UsageProviderID: String] = [:],
        currentSessionPaths: [UsageProviderID: String] = [:],
        shouldCancel: @Sendable () -> Bool = { Task.isCancelled }
    ) -> UsageSnapshot {
        let claudeTokens = loadClaudeTokens(
            now: now,
            root: claudeRoot,
            fileManager: fileManager,
            currentSessionID: currentSessionIDs[.claude],
            currentSessionPath: currentSessionPaths[.claude],
            shouldCancel: shouldCancel
        )
        if shouldCancel() { return UsageSnapshot(providers: [], capturedAt: now) }
        let codexResult = loadCodex(
            now: now,
            root: codexRoot,
            archivedRoot: codexArchivedRoot,
            fileManager: fileManager,
            currentSessionID: currentSessionIDs[.codex],
            currentSessionPath: currentSessionPaths[.codex],
            shouldCancel: shouldCancel
        )
        if shouldCancel() { return UsageSnapshot(providers: [], capturedAt: now) }
        let codexAccount: CodexAccountUsageResult?
        let codexError: String?
        if queryCodexAccount {
            switch CodexAppServerUsageClient.fetch() {
            case .success(let result):
                codexAccount = result
                codexError = nil
            case .failure(let message):
                codexAccount = nil
                codexError = message
            }
        } else {
            codexAccount = nil
            codexError = nil
        }
        let claudeAccount = loadClaudeAccount(now: now, statusURL: statusURL ?? claudeStatusURL)

        return UsageSnapshot(
            providers: [
                ProviderUsageSnapshot(
                    provider: .claude,
                    accountState: claudeAccount.state,
                    windows: claudeAccount.windows,
                    tokenSummary: claudeTokens,
                    capturedAt: claudeAccount.capturedAt,
                    errorMessage: nil
                ),
                ProviderUsageSnapshot(
                    provider: .codex,
                    accountState: (codexAccount?.windows ?? codexResult.windows).isEmpty ? .unavailable : .available,
                    windows: codexAccount?.windows ?? codexResult.windows,
                    tokenSummary: codexResult.tokens,
                    capturedAt: codexAccount?.capturedAt ?? codexResult.capturedAt,
                    errorMessage: codexError
                )
            ],
            capturedAt: now
        )
    }

    private static func loadClaudeAccount(now: Date, statusURL: URL) -> (
        state: UsageAccountState,
        windows: [UsageWindow],
        capturedAt: Date?
    ) {
        guard let data = try? Data(contentsOf: statusURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (.unavailable, [], nil)
        }
        let capturedAt = number(object["captured_at"]).map(Date.init(timeIntervalSince1970:))
            ?? (try? statusURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let rateLimits = object["rate_limits"] as? [String: Any] ?? object
        let definitions = [("five_hour", "5 小时", 300), ("seven_day", "7 天", 10_080)]
        let windows = definitions.compactMap { key, label, minutes -> UsageWindow? in
            guard let payload = rateLimits[key] as? [String: Any],
                  let used = number(payload["used_percentage"] ?? payload["utilization"]) else { return nil }
            return UsageWindow(
                id: key,
                label: label,
                usedPercentage: used,
                resetsAt: number(payload["resets_at"]).map(Date.init(timeIntervalSince1970:)),
                windowMinutes: minutes
            )
        }
        let isStale = capturedAt.map { now.timeIntervalSince($0) > 20 * 60 } ?? true
        return (windows.isEmpty ? .unavailable : (isStale ? .stale : .available), windows, capturedAt)
    }

    private static func loadClaudeTokens(
        now: Date,
        root: URL?,
        fileManager: FileManager,
        currentSessionID: String?,
        currentSessionPath: String?,
        shouldCancel: @Sendable () -> Bool
    ) -> TokenUsageSummary? {
        let root = root ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        var today = TokenUsageTotal()
        var sevenDays = TokenUsageTotal()
        var currentSession = TokenUsageTotal()
        var seen = Set<String>()
        var currentSessionSeen = Set<String>()

        let files = jsonlFiles(root: root, modifiedAfter: sevenDayStart, prefix: nil, fileManager: fileManager)
        fileCache.retainClaude(paths: Set(files.map { $0.url.path }))
        for file in files {
            if shouldCancel() { return nil }
            let isCurrentSession = matchesCurrentSession(
                file: file.url,
                sessionID: currentSessionID,
                sessionPath: currentSessionPath
            )
            let records = fileCache.claudeRecords(
                for: file.url,
                fingerprint: file.fingerprint,
                shouldCache: { !shouldCancel() }
            ) {
                parseClaudeFile(file.url, shouldCancel: shouldCancel)
            }
            for record in records {
                if shouldCancel() { return nil }
                guard record.timestamp >= sevenDayStart else { continue }
                if isCurrentSession,
                   record.messageID.map({ currentSessionSeen.insert($0).inserted }) ?? true {
                    currentSession = currentSession + record.usage
                }
                if let messageID = record.messageID, !seen.insert(messageID).inserted { continue }
                sevenDays = sevenDays + record.usage
                if record.timestamp >= todayStart { today = today + record.usage }
            }
        }
        guard sevenDays.total > 0 else { return nil }
        return TokenUsageSummary(
            today: today,
            sevenDays: sevenDays,
            currentSession: currentSession.total > 0 ? currentSession : nil
        )
    }

    private static func parseClaudeFile(
        _ file: URL,
        shouldCancel: @Sendable () -> Bool
    ) -> [ClaudeRecord] {
        var records: [ClaudeRecord] = []
        forEachLine(in: file, shouldCancel: shouldCancel) { object in
                guard object["type"] as? String == "assistant",
                      let timestamp = date(object["timestamp"]),
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      (message["model"] as? String) != "<synthetic>" else { return }
                let messageID = (message["id"] as? String) ?? (object["requestId"] as? String)
                let total = TokenUsageTotal(
                    input: integer(usage["input_tokens"]),
                    output: integer(usage["output_tokens"]),
                    cacheRead: integer(usage["cache_read_input_tokens"]),
                    cacheWrite: integer(usage["cache_creation_input_tokens"])
                )
                records.append(ClaudeRecord(timestamp: timestamp, messageID: messageID, usage: total))
        }
        return records
    }

    private static func loadCodex(
        now: Date,
        root: URL?,
        archivedRoot: URL?,
        fileManager: FileManager,
        currentSessionID: String?,
        currentSessionPath: String?,
        shouldCancel: @Sendable () -> Bool
    ) -> (
        tokens: TokenUsageSummary?,
        windows: [UsageWindow],
        capturedAt: Date?
    ) {
        let roots: [URL]
        if let root {
            roots = [root] + (archivedRoot.map { [$0] } ?? [])
        } else {
            roots = [
                fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
                fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/archived_sessions")
            ]
        }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        var today = TokenUsageTotal()
        var sevenDays = TokenUsageTotal()
        var currentSession = TokenUsageTotal()
        var latestWindows: [UsageWindow] = []
        var latestCapture: Date?

        var seenSessionIDs = Set<String>()
        let files = roots.flatMap {
            jsonlFiles(root: $0, modifiedAfter: sevenDayStart, prefix: "rollout-", fileManager: fileManager)
        }
        fileCache.retainCodex(paths: Set(files.map { $0.url.path }))
        for file in files {
            if shouldCancel() { return (nil, [], nil) }
            let data = fileCache.codexData(
                for: file.url,
                fingerprint: file.fingerprint,
                shouldCache: { !shouldCancel() }
            ) {
                parseCodexFile(file.url, shouldCancel: shouldCancel)
            }
            if let sessionID = data.sessionID, !seenSessionIDs.insert(sessionID).inserted {
                continue
            }
            let isCurrentSession = matchesCurrentSession(
                file: file.url,
                sessionID: nil,
                sessionPath: currentSessionPath
            ) || data.sessionID == currentSessionID
            if let capturedAt = data.capturedAt,
               latestCapture == nil || capturedAt > latestCapture! {
                latestWindows = data.windows
                latestCapture = capturedAt
            }
            for delta in data.deltas {
                if shouldCancel() { return (nil, [], nil) }
                if isCurrentSession { currentSession = currentSession + delta.usage }
                guard let timestamp = delta.timestamp, timestamp >= sevenDayStart else { continue }
                sevenDays = sevenDays + delta.usage
                if timestamp >= todayStart { today = today + delta.usage }
            }
        }
        let tokens = sevenDays.total > 0
            ? TokenUsageSummary(
                today: today,
                sevenDays: sevenDays,
                currentSession: currentSession.total > 0 ? currentSession : nil
            )
            : nil
        return (tokens, latestWindows, latestCapture)
    }

    private static func parseCodexFile(
        _ file: URL,
        shouldCancel: @Sendable () -> Bool
    ) -> CodexFileData {
        var previous = TokenUsageTotal()
        var result = CodexFileData(sessionID: nil, deltas: [], windows: [], capturedAt: nil)
        forEachLine(in: file, shouldCancel: shouldCancel) { object in
            if object["type"] as? String == "session_meta",
               let payload = object["payload"] as? [String: Any],
               let id = payload["id"] as? String {
                result.sessionID = id
            }
            guard object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count" else { return }
            let timestamp = date(object["timestamp"])
            if let rateLimits = payload["rate_limits"] as? [String: Any],
               timestamp.map({ result.capturedAt == nil || $0 > result.capturedAt! }) ?? false {
                let parsed = codexWindows(rateLimits)
                if !parsed.isEmpty {
                    result.windows = parsed
                    result.capturedAt = timestamp
                }
            }
            guard let info = payload["info"] as? [String: Any],
                  let cumulative = info["total_token_usage"] as? [String: Any] else { return }
            let rawInput = integer(cumulative["input_tokens"])
            let rawCached = integer(cumulative["cached_input_tokens"])
            let current = TokenUsageTotal(
                input: max(0, rawInput - rawCached),
                output: integer(cumulative["output_tokens"]),
                cacheRead: rawCached,
                cacheWrite: 0
            )
            let delta = TokenUsageTotal(
                input: max(0, current.input - previous.input),
                output: max(0, current.output - previous.output),
                cacheRead: max(0, current.cacheRead - previous.cacheRead),
                cacheWrite: 0
            )
            previous = current
            result.deltas.append(DatedTokenDelta(timestamp: timestamp, usage: delta))
        }
        return result
    }

    private static func matchesCurrentSession(
        file: URL,
        sessionID: String?,
        sessionPath: String?
    ) -> Bool {
        if let sessionPath,
           file.standardizedFileURL.path == URL(fileURLWithPath: sessionPath).standardizedFileURL.path {
            return true
        }
        guard let sessionID else { return false }
        return file.deletingPathExtension().lastPathComponent == sessionID
    }

    private static func codexWindows(_ limits: [String: Any]) -> [UsageWindow] {
        [("primary", "主要限额"), ("secondary", "次要限额")].compactMap { key, label in
            guard let payload = limits[key] as? [String: Any],
                  let used = number(payload["used_percent"] ?? payload["usedPercent"]) else { return nil }
            return UsageWindow(
                id: key,
                label: label,
                usedPercentage: used,
                resetsAt: number(payload["reset_at"] ?? payload["resets_at"] ?? payload["resetsAt"])
                    .map(Date.init(timeIntervalSince1970:)),
                windowMinutes: {
                    if let minutes = integerOptional(
                        payload["window_minutes"] ?? payload["windowMinutes"] ?? payload["windowDurationMins"]
                    ) { return minutes }
                    return integerOptional(payload["limit_window_seconds"]).map { $0 / 60 }
                }()
            )
        }
    }

    private static func jsonlFiles(
        root: URL,
        modifiedAfter cutoff: Date,
        prefix: String?,
        fileManager: FileManager
    ) -> [(url: URL, fingerprint: FileFingerprint)] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { item -> (URL, FileFingerprint)? in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            if let prefix, !url.lastPathComponent.hasPrefix(prefix) { return nil }
            guard let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey
            ]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= cutoff else { return nil }
            return (url, FileFingerprint(size: values.fileSize ?? 0, modifiedAt: modifiedAt))
        }
    }

    private static func forEachLine(
        in url: URL,
        shouldCancel: @Sendable () -> Bool,
        body: ([String: Any]) -> Void
    ) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        var start = data.startIndex
        while start < data.endIndex {
            if shouldCancel() { return }
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            if end > start,
               let object = try? JSONSerialization.jsonObject(with: data[start..<end]) as? [String: Any] {
                body(object)
            }
            start = end < data.endIndex ? data.index(after: end) : data.endIndex
        }
    }

    private static func integer(_ value: Any?) -> Int { integerOptional(value) ?? 0 }
    private static func integerOptional(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
