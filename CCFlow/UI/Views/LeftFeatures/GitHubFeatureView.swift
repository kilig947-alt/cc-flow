import AppKit
import SwiftUI

struct GitHubFeatureView: View {
    let compact: Bool
    @ObservedObject private var service = GitHubService.shared

    var body: some View {
        Group { compact ? AnyView(compactContent) : AnyView(expandedContent) }
            .onAppear { if service.profile == nil { service.refresh() } }
    }

    private var compactContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
            if let profile = service.profile {
                Text("@\(profile.login)").fontWeight(.semibold)
                Text("\(profile.repositories) repos").foregroundStyle(.secondary)
            } else { Text(service.status).lineLimit(1).foregroundStyle(.secondary) }
        }.font(.system(size: 10))
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right").font(.headline)
                Spacer()
                if service.isLoading { ProgressView().controlSize(.small) }
                Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).frame(width: 44, height: 44)
            }
            if let profile = service.profile {
                HStack(spacing: 14) {
                    AsyncImage(url: profile.avatarURL) { image in image.resizable() } placeholder: { Color.secondary.opacity(0.15) }
                        .frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name).font(.title3.bold())
                        Text("@\(profile.login)").foregroundStyle(.secondary)
                    }
                }
                Text(service.status).font(.caption).foregroundStyle(service.status == "已连接" ? Color.secondary : Color.orange)
                HStack(spacing: 10) {
                    stat("仓库", profile.repositories, .cyan)
                    stat("关注者", profile.followers, .purple)
                    stat("正在关注", profile.following, .yellow)
                }
                if !service.contributions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("贡献记录 · \(service.contributions.reduce(0) { $0 + $1.count }) 次").font(.caption).foregroundStyle(.secondary)
                        GeometryReader { proxy in
                            let days = visibleContributionDays(for: proxy.size.width)
                            let weeks = max(1, Int(ceil(Double(days.count) / 7.0)))
                            let spacing: CGFloat = 3
                            let cell = max(4, min(11, (proxy.size.width - CGFloat(weeks - 1) * spacing) / CGFloat(weeks)))
                            LazyHGrid(rows: Array(repeating: GridItem(.fixed(cell), spacing: spacing), count: 7), spacing: spacing) {
                                ForEach(days) { day in
                                    RoundedRectangle(cornerRadius: max(1, cell * 0.2)).fill(contributionColor(day.count)).frame(width: cell, height: cell)
                                        .accessibilityLabel("\(day.date)，\(day.count) 次贡献")
                                }
                            }.frame(maxWidth: .infinity, alignment: .trailing)
                        }.frame(height: 95)
                    }.padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                }
                ForEach(service.repositories.prefix(4)) { repository in
                    Button {
                        if let url = repository.url { NSWorkspace.shared.open(url) }
                    } label: {
                        HStack { Image(systemName: "folder"); Text(repository.name).lineLimit(1); Spacer(); Label("\(repository.stars)", systemImage: "star"); Image(systemName: "arrow.up.right") }
                            .font(.system(size: 10)).padding(.horizontal, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(repository.url == nil)
                        .accessibilityHint(repository.url == nil ? "仓库地址不可用" : "在默认浏览器打开仓库")
                }
                Spacer()
            } else {
                ContentUnavailableView("GitHub 未连接", systemImage: "person.crop.circle.badge.exclamationmark",
                                       description: Text(service.status))
            }
        }.padding(16)
    }

    private func contributionColor(_ count: Int) -> Color {
        if count == 0 { return .white.opacity(0.08) }
        if count < 3 { return .green.opacity(0.35) }
        if count < 6 { return .green.opacity(0.65) }
        return .green
    }

    private func visibleContributionDays(for width: CGFloat) -> [GitHubContributionDay] {
        let weeks = max(1, min(53, Int((width + 3) / 7)))
        return Array(service.contributions.suffix(weeks * 7))
    }

    private func stat(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.title2.bold()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}
