import Combine
import Foundation

struct BrowserResource: Codable, Identifiable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    let browser: String
    let savedAt: Date
    let iconID: String?

    init(id: UUID, url: URL, title: String, browser: String, savedAt: Date, iconID: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.browser = browser
        self.savedAt = savedAt
        self.iconID = iconID
    }
}

@MainActor
final class BrowserResourceService: ObservableObject {
    static let shared = BrowserResourceService()
    @Published private(set) var resources: [BrowserResource] = []
    @Published var inputURL = ""
    private let key = "productivity.browserResources.v1"
    private var faviconRequests: Set<URL> = []
    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([BrowserResource].self, from: data) { resources = decoded }
        backfillMissingFavicons()
    }

    func saveCurrentInput() {
        let raw = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        add(url: url, title: nil, browser: "手动保存")
        inputURL = ""; persist()
    }

    func add(url: URL, title: String?, browser: String, notify: Bool = false) {
        let isNew = !resources.contains { $0.url == url }
        let existingIconID = resources.first(where: { $0.url == url })?.iconID
        resources.removeAll { $0.url == url }
        resources.insert(BrowserResource(id: UUID(), url: url,
            title: title?.isEmpty == false ? title! : (url.host ?? url.absoluteString),
            browser: browser, savedAt: Date(), iconID: existingIconID), at: 0)
        persist()
        fetchFaviconIfNeeded(for: url)
        if notify && isNew {
            ProductivityProactiveEventCenter.shared.publish(
                targetFeatureID: LeftFeature.browserResourcesID,
                kind: .browserResourceSaved,
                summary: "已保存网页：\(title?.isEmpty == false ? title! : (url.host ?? url.absoluteString))"
            )
        }
    }

    func remove(_ resource: BrowserResource) { resources.removeAll { $0.id == resource.id }; persist() }

    private func backfillMissingFavicons() {
        for resource in resources where resource.iconID == nil {
            fetchFaviconIfNeeded(for: resource.url)
        }
    }

    private func fetchFaviconIfNeeded(for url: URL) {
        guard resources.contains(where: { $0.url == url && $0.iconID == nil }),
              faviconRequests.insert(url).inserted else { return }
        FaviconFetcher.fetch(for: url) { [weak self] iconID in
            guard let self else { return }
            self.faviconRequests.remove(url)
            guard let iconID else { return }
            var changed = false
            self.resources = self.resources.map { resource in
                guard resource.url == url, resource.iconID == nil else { return resource }
                changed = true
                return BrowserResource(id: resource.id, url: resource.url, title: resource.title,
                    browser: resource.browser, savedAt: resource.savedAt, iconID: iconID)
            }
            if changed { self.persist() }
        }
    }

    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(resources), forKey: key) }
}
