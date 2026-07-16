import Combine
import Foundation

struct GitHubProfile: Equatable {
    let login: String
    let name: String
    let avatarURL: URL?
    let repositories: Int
    let followers: Int
    let following: Int
}
struct GitHubContributionDay: Identifiable, Equatable { let date: String; let count: Int; var id: String { date } }
struct GitHubRepositorySummary: Identifiable, Equatable {
    let name: String
    let stars: Int
    let url: URL?
    var id: String { name }
}

@MainActor
final class GitHubService: ObservableObject {
    static let shared = GitHubService()
    @Published private(set) var profile: GitHubProfile?
    @Published private(set) var status = "尚未连接"
    @Published private(set) var isLoading = false
    @Published private(set) var contributions: [GitHubContributionDay] = []
    @Published private(set) var repositories: [GitHubRepositorySummary] = []
    private init() {}

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            do {
                let data = try await Self.fetchUser()
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let object, let login = object["login"] as? String else { throw GitHubError.invalidResponse }
                let previousLogin = profile?.login
                profile = GitHubProfile(
                    login: login, name: (object["name"] as? String) ?? login,
                    avatarURL: (object["avatar_url"] as? String).flatMap(URL.init(string:)),
                    repositories: object["public_repos"] as? Int ?? 0,
                    followers: object["followers"] as? Int ?? 0,
                    following: object["following"] as? Int ?? 0
                )
                if previousLogin != nil && previousLogin != login {
                    contributions = []
                    repositories = []
                }
                do {
                    let dashboard = try await Self.fetchDashboard()
                    contributions = dashboard.days
                    repositories = dashboard.repositories
                    status = "已连接"
                } catch {
                    status = "已连接，贡献数据暂不可用：\(error.localizedDescription)"
                }
            } catch {
                status = error.localizedDescription
            }
            isLoading = false
        }
    }

    nonisolated private static func fetchUser() async throws -> Data {
        if let data = runGH(arguments: ["api", "user"]) { return data }
        var lastError: Error = GitHubError.authenticationRequired
        for token in try availableTokens() {
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let status = (response as? HTTPURLResponse)?.statusCode else { throw GitHubError.network }
                guard status == 200 else { throw status == 401 ? GitHubError.authenticationRequired : GitHubError.http(status) }
                return data
            } catch { lastError = error }
        }
        throw lastError
    }

    nonisolated private static func fetchDashboard() async throws -> (days: [GitHubContributionDay], repositories: [GitHubRepositorySummary]) {
        let query = "query { viewer { contributionsCollection { contributionCalendar { weeks { contributionDays { date contributionCount } } } } repositories(first: 6, orderBy: {field: PUSHED_AT, direction: DESC}) { nodes { nameWithOwner stargazerCount url } } } }"
        if let data = runGH(arguments: ["api", "graphql", "-f", "query=\(query)"]),
           let parsed = try? parseDashboard(data) { return parsed }
        var lastError: Error = GitHubError.authenticationRequired
        for token in try availableTokens() {
            do {
                let data = try await fetchDashboardWithToken(query: query, token: token)
                return try parseDashboard(data)
            }
            catch { lastError = error }
        }
        throw lastError
    }

    nonisolated private static func parseDashboard(_ data: Data) throws -> (days: [GitHubContributionDay], repositories: [GitHubRepositorySummary]) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["errors"] == nil,
              let payload = root["data"] as? [String: Any], let viewer = payload["viewer"] as? [String: Any] else { throw GitHubError.invalidResponse }
        let collection = viewer["contributionsCollection"] as? [String: Any]
        let calendar = collection?["contributionCalendar"] as? [String: Any]
        let weeks = calendar?["weeks"] as? [[String: Any]] ?? []
        let days = weeks.flatMap { $0["contributionDays"] as? [[String: Any]] ?? [] }.compactMap { item -> GitHubContributionDay? in
            guard let date = item["date"] as? String else { return nil }; return GitHubContributionDay(date: date, count: item["contributionCount"] as? Int ?? 0)
        }
        let repoRoot = viewer["repositories"] as? [String: Any]
        let repos = (repoRoot?["nodes"] as? [[String: Any]] ?? []).compactMap { item -> GitHubRepositorySummary? in
            guard let name = item["nameWithOwner"] as? String else { return nil }
            let url = (item["url"] as? String).flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
            return GitHubRepositorySummary(name: name, stars: item["stargazerCount"] as? Int ?? 0, url: url)
        }
        return (days, repos)
    }

    nonisolated private static func fetchDashboardWithToken(query: String, token: String) async throws -> Data {
            var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!); request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw GitHubError.network }
        guard status == 200 else { throw status == 401 ? GitHubError.authenticationRequired : GitHubError.http(status) }
        return data
    }

    nonisolated private static func availableTokens() throws -> [String] {
        var tokens: [String] = []
        if let gh = executable(named: "gh") {
            let process = Process(); let output = Pipe()
            process.executableURL = gh; process.arguments = ["auth", "token"]
            process.standardOutput = output; process.standardError = Pipe()
            if (try? process.run()) != nil {
                process.waitUntilExit()
                if process.terminationStatus == 0,
                   let token = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !token.isEmpty { tokens.append(token) }
            }
        }
        if let token = ProductivitySecretsStore.shared.value(for: .githubPAT), !token.isEmpty, !tokens.contains(token) { tokens.append(token) }
        guard !tokens.isEmpty else { throw GitHubError.authenticationRequired }
        return tokens
    }

    nonisolated private static func runGH(arguments: [String]) -> Data? {
        guard let gh = executable(named: "gh") else { return nil }
        let process = Process(); let output = Pipe()
        process.executableURL = gh; process.arguments = arguments
        process.standardOutput = output; process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    nonisolated private static func executable(named name: String) -> URL? {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] +
            (Foundation.ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private enum GitHubError: LocalizedError {
    case authenticationRequired, invalidResponse, network, http(Int)
    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "请先运行 gh auth login，或在设置中添加 GitHub PAT"
        case .invalidResponse: "GitHub 返回的数据无法识别"
        case .network: "无法连接 GitHub，请检查网络后重试"
        case .http(let code): "GitHub 请求失败（HTTP \(code)）"
        }
    }
}
