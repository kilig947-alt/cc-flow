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
        add(url: url, title: nil, browser: "手动保存")
        inputURL = ""; persist()
    }

    func add(url: URL, title: String?, browser: String, notify: Bool = false) {
        let isNew = !resources.contains { $0.url == url }
        resources.removeAll { $0.url == url }
        resources.insert(BrowserResource(id: UUID(), url: url, title: title?.isEmpty == false ? title! : (url.host ?? url.absoluteString), browser: browser, savedAt: Date()), at: 0)
        persist()
        if notify && isNew {
            ProductivityProactiveEventCenter.shared.publish(
                targetFeatureID: LeftFeature.browserResourcesID,
                kind: .browserResourceSaved,
                summary: "已保存网页：\(title?.isEmpty == false ? title! : (url.host ?? url.absoluteString))"
            )
        }
    }

    func remove(_ resource: BrowserResource) { resources.removeAll { $0.id == resource.id }; persist() }
    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(resources), forKey: key) }
}
