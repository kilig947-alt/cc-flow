import Foundation

nonisolated struct CodexAccountUsageResult: Sendable {
    var windows: [UsageWindow]
    var capturedAt: Date
}

nonisolated enum CodexAccountUsageFetch: Sendable {
    case success(CodexAccountUsageResult)
    case failure(String)
}

nonisolated enum CodexAppServerUsageClient {
    private static let processRegistry = ProcessRegistry()

    static func cancelCurrentRequest() {
        processRegistry.cancel()
    }

    static func fetch(timeout: TimeInterval = 8) -> CodexAccountUsageFetch {
        guard let executable = codexExecutableURL() else {
            return .failure("未找到 Codex CLI")
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let state = ResponseState(input: input.fileHandleForWriting)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            state.consume(data)
        }

        do {
            try process.run()
            processRegistry.set(process)
            defer { processRegistry.clear(process) }
            state.send([
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": ["name": "cc-flow", "version": "1"],
                    "capabilities": ["experimentalApi": true]
                ]
            ])
            guard state.completed.wait(timeout: .now() + timeout) == .success else {
                output.fileHandleForReading.readabilityHandler = nil
                if process.isRunning { process.terminate() }
                return .failure("Codex 账户接口响应超时")
            }
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return .failure("无法启动 Codex CLI")
        }

        output.fileHandleForReading.readabilityHandler = nil
        input.fileHandleForWriting.closeFile()
        if process.isRunning { process.terminate() }
        guard let result = state.result() else {
            return .failure("无法解析 Codex 账户限额")
        }
        return .success(result)
    }

    private final class ProcessRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private weak var process: Process?

        func set(_ process: Process) {
            lock.lock()
            self.process = process
            lock.unlock()
        }

        func clear(_ process: Process) {
            lock.lock()
            if self.process === process { self.process = nil }
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            let running = process
            process = nil
            lock.unlock()
            if running?.isRunning == true { running?.terminate() }
        }
    }

    private static func codexExecutableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            home.appendingPathComponent(".local/bin/codex").path,
            home.appendingPathComponent(".asdf/shims/codex").path,
            home.appendingPathComponent(".volta/bin/codex").path,
            home.appendingPathComponent(".local/share/mise/shims/codex").path,
            home.appendingPathComponent("Library/pnpm/codex").path
        ]
        candidates.append(contentsOf: (Foundation.ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex").path })
        let nvmRoot = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(
            at: nvmRoot,
            includingPropertiesForKeys: nil
        ) {
            candidates.append(contentsOf: versions.map { $0.appendingPathComponent("bin/codex").path })
        }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    private final class ResponseState: @unchecked Sendable {
        let completed = DispatchSemaphore(value: 0)
        private let input: FileHandle
        private let lock = NSLock()
        private var buffer = Data()
        private var rateLimitResult: [String: Any]?
        private var receivedUsage = false
        private var didFinish = false

        init(input: FileHandle) {
            self.input = input
        }

        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            input.write(data)
            input.write(Data([0x0A]))
        }

        func consume(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = (object["id"] as? NSNumber)?.intValue else { continue }
                if id == 1 {
                    send(["method": "initialized"])
                    send(["id": 2, "method": "account/rateLimits/read", "params": NSNull()])
                    send(["id": 3, "method": "account/usage/read", "params": NSNull()])
                } else if id == 2 {
                    rateLimitResult = object["result"] as? [String: Any]
                    finishIfReady()
                } else if id == 3 {
                    receivedUsage = true
                    finishIfReady()
                }
            }
        }

        func result() -> CodexAccountUsageResult? {
            lock.lock()
            defer { lock.unlock() }
            guard let snapshot = rateLimitResult?["rateLimits"] as? [String: Any] else { return nil }
            let windows = [("primary", "主要限额"), ("secondary", "次要限额")].compactMap { key, label -> UsageWindow? in
                guard let payload = snapshot[key] as? [String: Any],
                      let used = number(payload["usedPercent"]) else { return nil }
                return UsageWindow(
                    id: key,
                    label: label,
                    usedPercentage: used,
                    resetsAt: number(payload["resetsAt"]).map(Date.init(timeIntervalSince1970:)),
                    windowMinutes: number(payload["windowDurationMins"]).map(Int.init)
                )
            }
            guard !windows.isEmpty else { return nil }
            return CodexAccountUsageResult(windows: windows, capturedAt: Date())
        }

        private func finishIfReady() {
            guard rateLimitResult != nil, receivedUsage, !didFinish else { return }
            didFinish = true
            completed.signal()
        }

        private func number(_ value: Any?) -> Double? {
            if let number = value as? NSNumber { return number.doubleValue }
            if let string = value as? String { return Double(string) }
            return nil
        }
    }
}
