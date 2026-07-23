import Foundation

nonisolated struct AntigravityAccountUsageResult: Sendable {
    var windows: [UsageWindow]
    var capturedAt: Date
}

nonisolated enum AntigravityAccountUsageFetch: Sendable {
    case success(AntigravityAccountUsageResult)
    case failure(String)
}

/// Reads quota data from the loopback language service owned by a running
/// Antigravity app. The CSRF token is used only for this local request and is
/// never persisted or included in diagnostics.
nonisolated enum AntigravityUsageClient {
    private struct Server {
        var pid: Int32
        var csrfToken: String
        var portHint: Int?
    }

    static func fetch(timeout: TimeInterval = 3) -> AntigravityAccountUsageFetch {
        guard let server = discoverServer() else {
            return .failure("请先启动 Antigravity 并登录")
        }

        let ports = ([server.portHint].compactMap { $0 } + listeningPorts(pid: server.pid))
            .reduce(into: [Int]()) { result, port in
                if !result.contains(port) { result.append(port) }
            }
        guard !ports.isEmpty else {
            return .failure("未找到 Antigravity 本地用量服务")
        }

        for port in ports {
            guard let data = requestStatus(
                port: port,
                csrfToken: server.csrfToken,
                timeout: timeout
            ) else { continue }
            if let result = parseStatus(data: data, capturedAt: Date()) {
                return .success(result)
            }
        }
        return .failure("无法读取 Antigravity 账户限额")
    }

    static func parseStatus(data: Data, capturedAt: Date) -> AntigravityAccountUsageResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = root["userStatus"] as? [String: Any] else {
            return nil
        }

        let cascade = status["cascadeModelConfigData"] as? [String: Any]
        let configs = cascade?["clientModelConfigs"] as? [[String: Any]] ?? []
        let modelQuotas = configs.compactMap { config -> ModelQuota? in
            guard let quota = config["quotaInfo"] as? [String: Any],
                  let remaining = number(quota["remainingFraction"]),
                  remaining.isFinite else {
                return nil
            }
            let modelText = [
                config["model"] as? String,
                config["modelId"] as? String,
                config["label"] as? String
            ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            let family: ModelFamily = modelText.contains("claude")
                || modelText.contains("gpt")
                || modelText.contains("oss")
                ? .claudeAndGPT
                : .gemini
            let reset = parseDate(quota["resetTime"])
            let cadence: QuotaCadence = reset.map {
                $0.timeIntervalSince(capturedAt) > 12 * 60 * 60 ? .weekly : .fiveHour
            } ?? .fiveHour
            return ModelQuota(
                family: family,
                cadence: cadence,
                remainingPercentage: max(0, min(100, remaining * 100)),
                resetsAt: reset
            )
        }

        let windows = ModelFamily.allCases.flatMap { family in
            QuotaCadence.allCases.compactMap { cadence -> UsageWindow? in
                let matching = modelQuotas.filter {
                    $0.family == family && $0.cadence == cadence
                }
                guard let remaining = matching.map(\.remainingPercentage).min() else {
                    return nil
                }
                return UsageWindow(
                    id: "antigravity-\(family.rawValue)-\(cadence.rawValue)",
                    label: "\(family.displayName) · \(cadence.displayName)",
                    usedPercentage: 100 - remaining,
                    resetsAt: matching.compactMap(\.resetsAt).max(),
                    windowMinutes: cadence == .fiveHour ? 300 : 10_080
                )
            }
        }

        guard !windows.isEmpty else { return nil }
        return AntigravityAccountUsageResult(windows: windows, capturedAt: capturedAt)
    }

    private enum ModelFamily: String, CaseIterable {
        case gemini
        case claudeAndGPT = "claude-gpt"

        var displayName: String {
            switch self {
            case .gemini: return "Gemini Models"
            case .claudeAndGPT: return "Claude and GPT models"
            }
        }
    }

    private enum QuotaCadence: String, CaseIterable {
        case weekly
        case fiveHour = "five-hour"

        var displayName: String {
            switch self {
            case .weekly: return "周限额"
            case .fiveHour: return "5 小时限额"
            }
        }
    }

    private struct ModelQuota {
        var family: ModelFamily
        var cadence: QuotaCadence
        var remainingPercentage: Double
        var resetsAt: Date?
    }

    private static func discoverServer() -> Server? {
        guard let listeners = runProcess(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"]
        ) else { return nil }

        let candidatePIDs = listeners.split(separator: "\n").compactMap { row -> Int32? in
            let columns = row.split(whereSeparator: \.isWhitespace)
            guard columns.count > 1,
                  columns[0].hasPrefix("language_") else {
                return nil
            }
            return Int32(columns[1])
        }

        for pid in Set(candidatePIDs) {
            guard
                  let command = runProcess(
                    executable: "/bin/ps",
                    arguments: ["-p", String(pid), "-o", "command="]
                  ),
                  command.contains("--csrf_token"),
                  let token = capture(
                    #"--csrf_token(?:=|\s+)([^\s]+)"#,
                    in: command
                  ) else {
                continue
            }
            let port = capture(
                #"--extension_server_port(?:=|\s+)(\d+)"#,
                in: command
            ).flatMap(Int.init)
            return Server(pid: pid, csrfToken: token, portHint: port)
        }
        return nil
    }

    private static func listeningPorts(pid: Int32) -> [Int] {
        guard let output = runProcess(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN"]
        ) else { return [] }
        let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#)
        return output.split(separator: "\n").compactMap { line in
            capture(regex, in: String(line)).flatMap(Int.init)
        }
    }

    private static func requestStatus(
        port: Int,
        csrfToken: String,
        timeout: TimeInterval
    ) -> Data? {
        requestStatus(
            scheme: "https",
            port: port,
            csrfToken: csrfToken,
            timeout: timeout
        ) ?? requestStatus(
            scheme: "http",
            port: port,
            csrfToken: csrfToken,
            timeout: timeout
        )
    }

    private static func requestStatus(
        scheme: String,
        port: Int,
        csrfToken: String,
        timeout: TimeInterval
    ) -> Data? {
        guard let url = URL(string:
            "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus"
        ) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "metadata": [
                "ideName": "antigravity",
                "extensionName": "antigravity",
                "locale": "en"
            ]
        ])

        let state = RequestState()
        let session = URLSession(
            configuration: .ephemeral,
            delegate: scheme == "https" ? LoopbackTrustDelegate.shared : nil,
            delegateQueue: nil
        )
        let task = session.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            state.finish(data: status.map({ 200..<300 ~= $0 }) == true ? data : nil)
        }
        task.resume()
        guard state.completed.wait(timeout: .now() + timeout + 0.5) == .success else {
            task.cancel()
            session.invalidateAndCancel()
            return nil
        }
        session.finishTasksAndInvalidate()
        return state.data
    }

    private static func runProcess(executable: String, arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Drain stdout while the child is still running. Waiting first can
            // deadlock when the pipe buffer fills (notably for a full `ps ax`).
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func capture(_ pattern: String, in string: String) -> String? {
        capture(try? NSRegularExpression(pattern: pattern), in: string)
    }

    private static func capture(_ regex: NSRegularExpression?, in string: String) -> String? {
        guard let regex else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[captureRange])
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let seconds = number(value) {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
        }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
            ?? ISO8601DateFormatter().date(from: string)
    }

    private final class RequestState: @unchecked Sendable {
        let completed = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var storedData: Data?

        var data: Data? {
            lock.lock()
            defer { lock.unlock() }
            return storedData
        }

        func finish(data: Data?) {
            lock.lock()
            storedData = data
            lock.unlock()
            completed.signal()
        }
    }

    private final class LoopbackTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
        static let shared = LoopbackTrustDelegate()

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (
                URLSession.AuthChallengeDisposition,
                URLCredential?
            ) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod
                    == NSURLAuthenticationMethodServerTrust,
                  challenge.protectionSpace.host == "127.0.0.1",
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }
}
