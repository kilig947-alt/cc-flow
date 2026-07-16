import SwiftUI

struct FileCardsFeatureView: View {
    let compact: Bool
    @ObservedObject private var service = LocalFileIndexService.shared
    @State private var pendingPlan: FileActionPlan?
    @State private var actionMessage: String?
    @State private var lastAuditID: UUID?
    var body: some View {
        Group {
            if compact {
                Label("\(service.cards.count) 张 File Card", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
            } else { fileList }
        }
        .onAppear { if service.cards.isEmpty { service.scan() } }
        .confirmationDialog("确认执行整理建议？", isPresented: Binding(get: { pendingPlan != nil }, set: { if !$0 { pendingPlan = nil } }),
                            titleVisibility: .visible, presenting: pendingPlan) { plan in
            Button("确认移动", role: .destructive) { execute(plan) }
            Button("取消", role: .cancel) { pendingPlan = nil }
        } message: { plan in
            Text("来源：\(plan.source.path)\n目标：\(plan.destination.path)\n执行前将再次校验文件，绝不覆盖同名目标。")
        }
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
            Toggle("允许所选 AI Provider 增强最近 File Card（最多 4000 字 OCR；不发送绝对路径）",
                   isOn: $service.aiEnhancementEnabled).font(.caption)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(service.folders, id: \.path) { folder in
                    HStack { Image(systemName: "folder"); Text(folder.lastPathComponent)
                        Button { service.removeFolder(folder) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                        .font(.caption).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.white.opacity(0.06), in: Capsule())
                } }
            }
            if let actionMessage {
                HStack { Text(actionMessage).font(.caption).foregroundStyle(.secondary); Spacer()
                    if let lastAuditID { Button("撤销") { undo(lastAuditID) } }
                }
            }
            ScrollView { LazyVStack(spacing: 7) { ForEach(service.cards) { card in cardRow(card) } } }
        }.padding(16)
    }

    private func cardRow(_ card: LocalFileCard) -> some View {
        HStack(spacing: 10) {
            Button { service.reveal(card) } label: {
                HStack(spacing: 10) {
                Image(systemName: "doc").frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(card.ocrText.isEmpty ? card.suggestion : "OCR · \(card.ocrText.replacingOccurrences(of: "\n", with: " "))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                }
            }.buttonStyle(.plain)
            Spacer()
            if card.suggestion != "暂无整理建议" {
                Button("查看建议") {
                    do { pendingPlan = try FileActionExecutor.makePlan(for: card) }
                    catch { actionMessage = error.localizedDescription }
                }.buttonStyle(.bordered).controlSize(.small)
            }
            Text(ByteCountFormatter.string(fromByteCount: card.size, countStyle: .file)).font(.caption2).foregroundStyle(.secondary)
        }.padding(9).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private func execute(_ plan: FileActionPlan) {
        pendingPlan = nil
        Task { do { let audit = try await FileActionExecutor.shared.executeConfirmed(plan); lastAuditID = audit.id; actionMessage = "已完成移动，可安全撤销"; service.scan() }
            catch { actionMessage = error.localizedDescription } }
    }

    private func undo(_ id: UUID) {
        Task { do { try await FileActionExecutor.shared.undo(id); lastAuditID = nil; actionMessage = "已撤销"; service.scan() }
            catch { actionMessage = error.localizedDescription } }
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
    @ObservedObject private var bridge = BrowserBridgeService.shared
    private var downloads: [LocalFileCard] { service.cards.filter { $0.url.path.contains("/Downloads/") } }
    var body: some View {
        Group {
            if compact { Label(bridge.downloads.first.map { "\($0.filename) · \($0.state)" } ?? "最近下载 \(downloads.count)", systemImage: "arrow.down.circle").font(.system(size: 10, weight: .semibold)).lineLimit(1) }
            else { VStack(alignment: .leading, spacing: 10) {
                Label("下载监控", systemImage: "arrow.down.circle").font(.headline)
                Text("\(bridge.status)。扩展事件提供实时状态，本地目录作为完成记录兜底。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(bridge.downloads.prefix(8)) { item in
                    HStack { Image(systemName: item.state == "complete" ? "checkmark.circle.fill" : "arrow.down.circle"); Text(item.filename).lineLimit(1); Spacer(); Text(item.state).font(.caption).foregroundStyle(.secondary) }
                        .padding(8).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                }
                ScrollView { LazyVStack(spacing: 7) { ForEach(downloads.prefix(100)) { card in
                    Button { service.reveal(card) } label: { HStack { Image(systemName: "arrow.down.doc"); Text(card.name).lineLimit(1); Spacer(); Text(card.modifiedAt, style: .relative).font(.caption2) }.padding(9).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain)
                } } }
            }.padding(16).onAppear { if service.cards.isEmpty { service.scan() } } }
        }
    }
}
