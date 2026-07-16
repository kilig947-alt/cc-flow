import AppKit
import Combine
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

struct LocalFileCard: Identifiable, Equatable {
    let id: String
    let url: URL
    let name: String
    let kind: String
    let size: Int64
    let modifiedAt: Date
    let tags: [String]
    let summary: String
    let ocrText: String
    let suggestion: String
}

@MainActor
final class LocalFileIndexService: ObservableObject {
    static let shared = LocalFileIndexService()
    @Published private(set) var cards: [LocalFileCard] = []
    @Published private(set) var folders: [URL] = []
    @Published private(set) var isScanning = false
    @Published var query = ""

    private let defaultsKey = "productivity.watchedFolderPaths"
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaults = [home.appendingPathComponent("Downloads"), home.appendingPathComponent("Desktop")]
        let saved = UserDefaults.standard.stringArray(forKey: defaultsKey)?.map(URL.init(fileURLWithPath:)) ?? []
        folders = Array(Set(defaults + saved)).sorted { $0.path < $1.path }
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
        Task.detached(priority: .utility) {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .contentTypeKey]
            var output: [LocalFileCard] = []
            for root in roots {
                guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                while let url = enumerator.nextObject() as? URL, output.count < 500 {
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
            await MainActor.run { self.cards = output; self.isScanning = false }
        }
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        folders = Array(Set(folders + panel.urls)).sorted { $0.path < $1.path }
        UserDefaults.standard.set(folders.map(\.path), forKey: defaultsKey)
        scan()
    }

    func reveal(_ card: LocalFileCard) { NSWorkspace.shared.activateFileViewerSelecting([card.url]) }

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
