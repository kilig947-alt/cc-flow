import Combine
import Foundation

enum AIProviderSelection: String, Codable, CaseIterable, Identifiable {
    case local
    case codexCLI
    case claudeCLI
    case openAICompatible

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .local: "本地规则"
        case .codexCLI: "Codex CLI"
        case .claudeCLI: "Claude Code CLI"
        case .openAICompatible: "OpenAI-compatible API"
        }
    }
}

enum AITaskKind: String, Codable { case fileCard, organizationSuggestion, naturalQuery, browserClassification, mailImportance }

struct AIProviderRequest: Codable, Equatable {
    let task: AITaskKind
    let filename: String?
    let path: String?
    let fileType: String?
    let ocrText: String?
    let query: String?
    let title: String?
    let snippet: String?
}

struct AIProviderResponse: Codable, Equatable {
    let version: Int
    let summary: String
    let tags: [String]
    let suggestion: String?
}

@MainActor
final class AIProviderSettings: ObservableObject {
    static let shared = AIProviderSettings()
    @Published var selection: AIProviderSelection { didSet { defaults.set(selection.rawValue, forKey: "productivity.ai.provider") } }
    @Published var baseURL: String { didSet { defaults.set(baseURL, forKey: "productivity.ai.baseURL") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "productivity.ai.model") } }
    private let defaults = UserDefaults.standard
    private init() {
        selection = AIProviderSelection(rawValue: defaults.string(forKey: "productivity.ai.provider") ?? "") ?? .local
        baseURL = defaults.string(forKey: "productivity.ai.baseURL") ?? "https://api.openai.com/v1"
        model = defaults.string(forKey: "productivity.ai.model") ?? "gpt-4.1-mini"
    }
}

enum AIProviderError: LocalizedError {
    case executableMissing(String), authenticationRequired, timeout, invalidResponse, http(Int)
    var errorDescription: String? {
        switch self {
        case .executableMissing(let name): "未找到 \(name)"
        case .authenticationRequired: "缺少登录或 API Key"
        case .timeout: "AI 请求超时"
        case .invalidResponse: "AI 返回的结构无法识别"
        case .http(let code): "AI 服务返回 HTTP \(code)"
        }
    }
}

struct AIProviderResult: Equatable {
    let response: AIProviderResponse
    let usedProvider: AIProviderSelection
    let degradedMessage: String?
}

@MainActor
final class AIProviderService {
    static let shared = AIProviderService()
    private init() {}

    func perform(_ request: AIProviderRequest, override: AIProviderSelection? = nil) async -> AIProviderResult {
        let selected = override ?? AIProviderSettings.shared.selection
        guard selected != .local else { return AIProviderResult(response: Self.localResponse(for: request), usedProvider: .local, degradedMessage: nil) }
        do {
            let response: AIProviderResponse
            switch selected {
            case .local: response = Self.localResponse(for: request)
            case .codexCLI: response = try await Self.runCLI(name: "codex", arguments: ["exec", "--json", "-"] , request: request)
            case .claudeCLI: response = try await Self.runCLI(name: "claude", arguments: ["-p", "--output-format", "json"], request: request)
            case .openAICompatible:
                response = try await Self.runOpenAI(request: request, baseURL: AIProviderSettings.shared.baseURL, model: AIProviderSettings.shared.model)
            }
            return AIProviderResult(response: response, usedProvider: selected, degradedMessage: nil)
        } catch {
            return AIProviderResult(response: Self.localResponse(for: request), usedProvider: .local, degradedMessage: error.localizedDescription)
        }
    }

    nonisolated static func localResponse(for request: AIProviderRequest) -> AIProviderResponse {
        let ext = request.fileType?.lowercased() ?? ""
        var tags = [ext].filter { !$0.isEmpty }
        if ["png", "jpg", "jpeg", "heic", "gif"].contains(ext) { tags.append("图片") }
        if ["pdf", "doc", "docx", "md", "txt"].contains(ext) { tags.append("文档") }
        let summary = request.filename.map { "本地文件：\($0)" } ?? request.title ?? request.query ?? "本地规则结果"
        return AIProviderResponse(version: 1, summary: summary, tags: tags,
            suggestion: tags.contains("图片") ? "建议归入图片目录" : tags.contains("文档") ? "建议归入文档目录" : nil)
    }

    nonisolated private static func prompt(for request: AIProviderRequest) throws -> String {
        let data = try JSONEncoder().encode(request)
        let input = String(data: data, encoding: .utf8) ?? "{}"
        return "Return JSON only: {\"version\":1,\"summary\":\"\",\"tags\":[],\"suggestion\":null}. Do not propose shell commands. Input: \(input)"
    }

    nonisolated private static func runCLI(name: String, arguments: [String], request: AIProviderRequest) async throws -> AIProviderResponse {
        guard let executable = executable(named: name) else { throw AIProviderError.executableMissing(name) }
        return try await Task.detached(priority: .utility) {
                let process = Process(); let stdin = Pipe(); let stdout = Pipe(); let stderr = Pipe()
                process.executableURL = executable; process.arguments = arguments
                process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
                var environment = Foundation.ProcessInfo.processInfo.environment
                environment.removeValue(forKey: "OPENAI_API_KEY"); environment.removeValue(forKey: "ANTHROPIC_API_KEY")
                process.environment = environment
                try process.run()
                stdin.fileHandleForWriting.write(Data(try prompt(for: request).utf8)); try? stdin.fileHandleForWriting.close()
                let deadline = Date().addingTimeInterval(45)
                while process.isRunning && Date() < deadline && !Task.isCancelled { Thread.sleep(forTimeInterval: 0.05) }
                if process.isRunning { process.terminate(); throw AIProviderError.timeout }
                if Task.isCancelled { throw CancellationError() }
                guard process.terminationStatus == 0 else { throw AIProviderError.authenticationRequired }
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                guard data.count <= 1_000_000 else { throw AIProviderError.invalidResponse }
                return try decodeResponse(from: data)
        }.value
    }

    nonisolated private static func runOpenAI(request: AIProviderRequest, baseURL: String, model: String) async throws -> AIProviderResponse {
        guard let key = ProductivitySecretsStore.shared.value(for: .openAIAPIKey),
              let root = URL(string: baseURL) else { throw AIProviderError.authenticationRequired }
        let url = root.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: url); urlRequest.httpMethod = "POST"; urlRequest.timeoutInterval = 45
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "temperature": 0,
            "messages": [["role": "user", "content": try prompt(for: request)]]])
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIProviderError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = object?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else { throw AIProviderError.invalidResponse }
        return try decodeResponse(from: Data(content.utf8))
    }

    nonisolated static func decodeResponse(from data: Data) throws -> AIProviderResponse {
        if let direct = try? JSONDecoder().decode(AIProviderResponse.self, from: data), direct.version == 1 { return direct }
        if let string = String(data: data, encoding: .utf8), let start = string.firstIndex(of: "{"), let end = string.lastIndex(of: "}"),
           let decoded = try? JSONDecoder().decode(AIProviderResponse.self, from: Data(string[start...end].utf8)), decoded.version == 1 { return decoded }
        throw AIProviderError.invalidResponse
    }

    nonisolated private static func executable(named name: String) -> URL? {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] + (Foundation.ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
