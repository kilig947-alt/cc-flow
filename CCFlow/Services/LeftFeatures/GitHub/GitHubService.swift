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
struct GitHubRepositorySummary: Identifiable, Equatable { let name: String; let stars: Int; var id: String { name } }

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
                profile = GitHubProfile(
                    login: login, name: (object["name"] as? String) ?? login,
                    avatarURL: (object["avatar_url"] as? String).flatMap(URL.init(string:)),
                    repositories: object["public_repos"] as? Int ?? 0,
                    followers: object["followers"] as? Int ?? 0,
                    following: object["following"] as? Int ?? 0
                )
                let dashboard = try? await Self.fetchDashboard()
                contributions = dashboard?.days ?? []
                repositories = dashboard?.repositories ?? []
                status = "已连接"
            } catch {
                status = error.localizedDescription
                profile = nil
            }
            isLoading = false
        }
    }

    nonisolated private static func fetchUser() async throws -> Data {
        if let gh = executable(named: "gh") {
            let process = Process()
            let output = Pipe()
            process.executableURL = gh
            process.arguments = ["api", "user"]
            process.standardOutput = output
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return output.fileHandleForReading.readDataToEndOfFile() }
        }
        guard let token = ProductivitySecretsStore.shared.value(for: .githubPAT) else { throw GitHubError.authenticationRequired }
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw GitHubError.authenticationRequired }
        return data
    }

    nonisolated private static func fetchDashboard() async throws -> (days: [GitHubContributionDay], repositories: [GitHubRepositorySummary]) {
        let query = "query { viewer { contributionsCollection { contributionCalendar { weeks { contributionDays { date contributionCount } } } } repositories(first: 6, orderBy: {field: PUSHED_AT, direction: DESC}) { nodes { nameWithOwner stargazerCount } } } }"
        let data: Data
        if let gh = executable(named: "gh") {
            let process = Process(); let output = Pipe(); process.executableURL = gh
            process.arguments = ["api", "graphql", "-f", "query=\(query)"]
            process.standardOutput = output; process.standardError = Pipe(); try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw GitHubError.authenticationRequired }
            data = output.fileHandleForReading.readDataToEndOfFile()
        } else {
            guard let token = ProductivitySecretsStore.shared.value(for: .githubPAT) else { throw GitHubError.authenticationRequired }
            var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!); request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
            (data, _) = try await URLSession.shared.data(for: request)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any], let viewer = payload["viewer"] as? [String: Any] else { throw GitHubError.invalidResponse }
        let collection = viewer["contributionsCollection"] as? [String: Any]
        let calendar = collection?["contributionCalendar"] as? [String: Any]
        let weeks = calendar?["weeks"] as? [[String: Any]] ?? []
        let days = weeks.flatMap { $0["contributionDays"] as? [[String: Any]] ?? [] }.compactMap { item -> GitHubContributionDay? in
            guard let date = item["date"] as? String else { return nil }; return GitHubContributionDay(date: date, count: item["contributionCount"] as? Int ?? 0)
        }
        let repoRoot = viewer["repositories"] as? [String: Any]
        let repos = (repoRoot?["nodes"] as? [[String: Any]] ?? []).compactMap { item -> GitHubRepositorySummary? in
            guard let name = item["nameWithOwner"] as? String else { return nil }; return GitHubRepositorySummary(name: name, stars: item["stargazerCount"] as? Int ?? 0)
        }
        return (days, repos)
    }

    nonisolated private static func executable(named name: String) -> URL? {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] +
            (Foundation.ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private enum GitHubError: LocalizedError {
    case authenticationRequired, invalidResponse
    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "请先运行 gh auth login，或在设置中添加 GitHub PAT"
        case .invalidResponse: "GitHub 返回的数据无法识别"
        }
    }
}
