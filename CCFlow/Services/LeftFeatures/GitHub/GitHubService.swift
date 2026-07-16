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

@MainActor
final class GitHubService: ObservableObject {
    static let shared = GitHubService()
    @Published private(set) var profile: GitHubProfile?
    @Published private(set) var status = "尚未连接"
    @Published private(set) var isLoading = false
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
