import AppKit
import Combine
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

struct LocalFileCard: Codable, Identifiable, Equatable {
    let id: String
    let url: URL
    let name: String
    let kind: String
    let size: Int64
    let modifiedAt: Date
    var tags: [String]
    var summary: String
    let ocrText: String
    var suggestion: String
}

@MainActor
final class LocalFileIndexService: ObservableObject {
    static let shared = LocalFileIndexService()
    @Published private(set) var cards: [LocalFileCard] = []
    @Published private(set) var folders: [URL] = []
    @Published private(set) var isScanning = false
    @Published var query = ""
    @Published var aiEnhancementEnabled: Bool {
        didSet { UserDefaults.standard.set(aiEnhancementEnabled, forKey: "productivity.fileCards.aiEnabled") }
    }

    private let defaultsKey = "productivity.watchedFolderPaths"
    private let cardsURL = BridgeRuntimePaths.runtimeDirectoryURL
        .appendingPathComponent("productivity", isDirectory: true)
        .appendingPathComponent("file-cards-v1.json")
    private var scanTask: Task<Void, Never>?
    private var enrichmentTask: Task<Void, Never>?
    private var consumers = 0
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaults = [home.appendingPathComponent("Downloads"), home.appendingPathComponent("Desktop")]
        let saved = UserDefaults.standard.stringArray(forKey: defaultsKey)?.map(URL.init(fileURLWithPath:)) ?? []
        folders = Array(Set(defaults + saved)).sorted { $0.path < $1.path }
        aiEnhancementEnabled = UserDefaults.standard.bool(forKey: "productivity.fileCards.aiEnabled")
        if let data = try? Data(contentsOf: cardsURL), let decoded = try? JSONDecoder().decode([LocalFileCard].self, from: data) {
            cards = decoded
        }
    }

    func start() { consumers += 1 }
    func stop() {
        consumers = max(0, consumers - 1)
        guard consumers == 0 else { return }
        scanTask?.cancel(); scanTask = nil; enrichmentTask?.cancel(); enrichmentTask = nil; isScanning = false
    }

    var results: [LocalFileCard] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return cards }
        return cards.filter {
            $0.name.lowercased().contains(needle) || $0.url.path.lowercased().contains(needle) ||
            $0.kind.lowercased().contains(needle) || $0.tags.contains { $0.lowercased().contains(needle) } ||
            $0.summary.lowercased().contains(needle) || $0.ocrText.lowercased().contains(needle)
        }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let roots = folders
        scanTask?.cancel()
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .contentTypeKey]
            var output: [LocalFileCard] = []
            for root in roots {
                guard !Task.isCancelled else { return }
                let resolved = WatchedFolderBookmarkStore.resolve(path: root.path) ?? root
                let accessing = resolved.startAccessingSecurityScopedResource()
                defer { if accessing { resolved.stopAccessingSecurityScopedResource() } }
                guard let enumerator = FileManager.default.enumerator(at: resolved, includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                while let url = enumerator.nextObject() as? URL, output.count < 500 {
                    guard !Task.isCancelled else { return }
                    guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                    let name = url.lastPathComponent
                    if ["crdownload", "download", "part"].contains(url.pathExtension.lowercased()) { continue }
                    let kind = values.contentType?.localizedDescription ?? url.pathExtension.uppercased()
                    let tags = Self.tags(for: url)
                    let ocrText = output.count < 40 ? Self.recognizeText(at: url) : ""
                    output.append(LocalFileCard(
                        id: url.standardizedFileURL.path, url: url, name: name, kind: kind,
                        size: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate ?? .distantPast,
                        tags: tags, summary: "\(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file))",
                        ocrText: String(ocrText.prefix(8_000)), suggestion: Self.suggestion(for: url, tags: tags)
                    ))
                }
            }
            output.sort { $0.modifiedAt > $1.modifiedAt }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.cards = output; self.persistCards(); self.isScanning = false
                self.enrichmentTask = Task { await self.enrichRecentCardsWithAI() }
            }
        }
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { _ = WatchedFolderBookmarkStore.save(url: $0) }
        folders = Array(Set(folders + panel.urls)).sorted { $0.path < $1.path }
        UserDefaults.standard.set(folders.map(\.path), forKey: defaultsKey)
        scan()
    }

    func removeFolder(_ url: URL) {
        WatchedFolderBookmarkStore.remove(path: url.path)
        folders.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        UserDefaults.standard.set(folders.map(\.path), forKey: defaultsKey)
        let prefix = url.standardizedFileURL.path + "/"
        cards.removeAll { $0.url.standardizedFileURL.path.hasPrefix(prefix) }
        persistCards()
    }

    func reveal(_ card: LocalFileCard) { NSWorkspace.shared.activateFileViewerSelecting([card.url]) }

    private func persistCards() {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        try? FileManager.default.createDirectory(at: cardsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cardsURL, options: .atomic)
    }

    private func enrichRecentCardsWithAI() async {
        guard aiEnhancementEnabled, AIProviderSettings.shared.selection != .local else { return }
        for index in cards.indices.prefix(10) {
            guard !Task.isCancelled else { return }
            let card = cards[index]
            let request = AIProviderRequest(task: .fileCard, filename: card.name, path: nil,
                fileType: card.url.pathExtension, ocrText: String(card.ocrText.prefix(4_000)), query: nil, title: nil, snippet: nil)
            let result = await AIProviderService.shared.perform(request)
            guard cards.indices.contains(index), cards[index].id == card.id else { continue }
            cards[index].summary = result.response.summary
            cards[index].tags = Array(Set(cards[index].tags + result.response.tags)).sorted()
            if let suggestion = result.response.suggestion, !suggestion.isEmpty {
                cards[index].suggestion = "\(suggestion)（仅建议，确认后才会执行）"
            }
            persistCards()
        }
    }

    nonisolated private static func tags(for url: URL) -> [String] {
        var result = [url.pathExtension.lowercased()].filter { !$0.isEmpty }
        let name = url.lastPathComponent.lowercased()
        if name.contains("screenshot") || name.contains("截屏") { result.append("截图") }
        if ["png", "jpg", "jpeg", "heic", "gif"].contains(url.pathExtension.lowercased()) { result.append("图片") }
        if ["pdf", "doc", "docx", "md", "txt"].contains(url.pathExtension.lowercased()) { result.append("文档") }
        return result
    }

    nonisolated private static func suggestion(for url: URL, tags: [String]) -> String {
        if tags.contains("截图") { return "建议归档到“截图”文件夹（仅建议，确认后才会执行）" }
        if tags.contains("图片") { return "建议归档到“图片”文件夹（仅建议，确认后才会执行）" }
        if tags.contains("文档") { return "建议归档到“文档”文件夹（仅建议，确认后才会执行）" }
        return "暂无整理建议"
    }

    nonisolated static func recognizeText(at url: URL) -> String {
        guard !Task.isCancelled else { return "" }
        let ext = url.pathExtension.lowercased()
        var images: [CGImage] = []
        if ext == "pdf", let document = PDFDocument(url: url) {
            for index in 0..<min(document.pageCount, 3) {
                guard let page = document.page(at: index) else { continue }
                let image = page.thumbnail(of: CGSize(width: 1800, height: 2400), for: .mediaBox)
                if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { images.append(cg) }
            }
        } else if ["png", "jpg", "jpeg", "heic", "tiff", "gif"].contains(ext),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { images = [image] }
        guard !images.isEmpty else { return "" }
        var lines: [String] = []
        for image in images {
            guard !Task.isCancelled else { return lines.joined(separator: "\n") }
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                lines.append(contentsOf: observations.compactMap { $0.topCandidates(1).first?.string })
            }
            request.recognitionLevel = .accurate; request.recognitionLanguages = ["zh-Hans", "en-US"]
            try? VNImageRequestHandler(cgImage: image).perform([request])
        }
        return lines.joined(separator: "\n")
    }
}

private enum WatchedFolderBookmarkStore {
    private static let key = "productivity.watchedFolderBookmarks.v1"
    static func save(url: URL) -> Bool {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
        var all = load(); all[url.path] = data; persist(all); return true
    }
    static func resolve(path: String) -> URL? {
        guard let data = load()[path] else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { _ = save(url: url) }
        return url
    }
    static func remove(path: String) { var all = load(); all.removeValue(forKey: path); persist(all) }
    private static func load() -> [String: Data] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? PropertyListDecoder().decode([String: Data].self, from: data)) ?? [:]
    }
    private static func persist(_ value: [String: Data]) { UserDefaults.standard.set(try? PropertyListEncoder().encode(value), forKey: key) }
}
