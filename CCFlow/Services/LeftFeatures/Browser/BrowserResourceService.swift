import Combine
import Foundation

struct BrowserResource: Codable, Identifiable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    let browser: String
    let savedAt: Date
}

@MainActor
final class BrowserResourceService: ObservableObject {
    static let shared = BrowserResourceService()
    @Published private(set) var resources: [BrowserResource] = []
    @Published var inputURL = ""
    private let key = "productivity.browserResources.v1"
    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([BrowserResource].self, from: data) { resources = decoded }
    }

    func saveCurrentInput() {
        let raw = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        resources.insert(BrowserResource(id: UUID(), url: url, title: url.host ?? raw, browser: "手动保存", savedAt: Date()), at: 0)
        inputURL = ""; persist()
    }

    func remove(_ resource: BrowserResource) { resources.removeAll { $0.id == resource.id }; persist() }
    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(resources), forKey: key) }
}
