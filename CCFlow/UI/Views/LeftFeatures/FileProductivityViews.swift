import SwiftUI

struct FileCardsFeatureView: View {
    let compact: Bool
    @ObservedObject private var service = LocalFileIndexService.shared
    var body: some View {
        Group {
            if compact {
                Label("\(service.cards.count) 张 File Card", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
            } else { fileList }
        }.onAppear { if service.cards.isEmpty { service.scan() } }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("File Card", systemImage: "doc.text.magnifyingglass").font(.headline)
                Spacer()
                if service.isScanning { ProgressView().controlSize(.small) }
                Button { service.addFolder() } label: { Label("添加文件夹", systemImage: "folder.badge.plus") }
                Button { service.scan() } label: { Image(systemName: "arrow.clockwise") }
            }
            Text("只生成卡片与整理建议；不会自动移动、重命名或归档文件。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView { LazyVStack(spacing: 7) { ForEach(service.cards) { card in cardRow(card) } } }
        }.padding(16)
    }

    private func cardRow(_ card: LocalFileCard) -> some View {
        Button { service.reveal(card) } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc").frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(card.suggestion).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: card.size, countStyle: .file)).font(.caption2).foregroundStyle(.secondary)
            }.padding(9).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}

struct NaturalSearchFeatureView: View {
    let compact: Bool
    @ObservedObject private var service = LocalFileIndexService.shared
    var body: some View {
        Group {
            if compact {
                Label(service.query.isEmpty ? "搜索本地 File Card" : "找到 \(service.results.count) 项", systemImage: "sparkle.magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("自然搜索", systemImage: "sparkle.magnifyingglass").font(.headline)
                    TextField("搜索文件名、路径、File Card、OCR 或标签", text: $service.query).textFieldStyle(.roundedBorder)
                    Text("仅搜索已授权目录的约定字段，不索引文档正文。")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView { LazyVStack(spacing: 7) {
                        ForEach(service.results) { card in
                            Button { service.reveal(card) } label: {
                                HStack { Image(systemName: "doc"); VStack(alignment: .leading) {
                                    Text(card.name).fontWeight(.semibold); Text(card.url.deletingLastPathComponent().path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }; Spacer() }.padding(9).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain)
                        }
                    } }
                }.padding(16).onAppear { if service.cards.isEmpty { service.scan() } }
            }
        }
    }
}

struct DownloadMonitorFeatureView: View {
    let compact: Bool
    @ObservedObject private var service = LocalFileIndexService.shared
    private var downloads: [LocalFileCard] { service.cards.filter { $0.url.path.contains("/Downloads/") } }
    var body: some View {
        Group {
            if compact { Label("最近下载 \(downloads.count)", systemImage: "arrow.down.circle").font(.system(size: 10, weight: .semibold)) }
            else { VStack(alignment: .leading, spacing: 10) {
                Label("下载监控", systemImage: "arrow.down.circle").font(.headline)
                Text("显示 Chrome、Edge 和 Safari 写入下载目录的文件。安装浏览器扩展后可获得实时进度。")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView { LazyVStack(spacing: 7) { ForEach(downloads.prefix(100)) { card in
                    Button { service.reveal(card) } label: { HStack { Image(systemName: "arrow.down.doc"); Text(card.name).lineLimit(1); Spacer(); Text(card.modifiedAt, style: .relative).font(.caption2) }.padding(9).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain)
                } } }
            }.padding(16).onAppear { if service.cards.isEmpty { service.scan() } } }
        }
    }
}
