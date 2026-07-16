import SwiftUI

struct UsageExpandedView: View {
    @ObservedObject private var service = UsageService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let snapshot = service.snapshot {
                    ForEach(snapshot.providers) { provider in
                        providerCard(provider)
                    }
                } else if service.isRefreshing {
                    loadingState
                } else {
                    emptyState
                }
            }
            .padding(14)
        }
        .onAppear {
            service.start()
            Task { await service.refresh(reason: .becameActive) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appLocalized: "账号用量")
                    .font(.system(size: 16, weight: .bold))
                if let date = service.snapshot?.capturedAt {
                    Text(AppLocalization.format(
                        "更新于 %@",
                        date.formatted(date: .omitted, time: .shortened)
                    ))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await service.refresh(reason: .retry) }
            } label: {
                Label(service.isRefreshing ? "更新中" : "刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minWidth: 70, minHeight: 44)
            .disabled(service.isRefreshing)
            .accessibilityLabel(Text(appLocalized: "刷新账号用量"))
        }
    }

    private func providerCard(_ provider: ProviderUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(provider.provider.displayName)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(appLocalized: stateText(provider.accountState))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(provider.accountState == .available ? .green : .secondary)
            }

            if provider.windows.isEmpty {
                Text(appLocalized: provider.provider == .claude
                     ? "启动 Claude Code 并完成一次请求后可读取账户限额。"
                     : "尚未在本地 Codex 会话中检测到限额；Token 统计仍可用。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ForEach(provider.windows) { window in
                    usageWindowRow(window)
                }
            }

            if let error = provider.errorMessage {
                Label {
                    Text(appLocalized: error)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let tokens = provider.tokenSummary {
                Divider().opacity(0.35)
                HStack(spacing: 18) {
                    tokenMetric("今日", tokens.today.total)
                    tokenMetric("7 天", tokens.sevenDays.total)
                    if let current = tokens.currentSession {
                        tokenMetric("当前会话", current.total)
                    }
                    Spacer(minLength: 0)
                }
                Text(tokenBreakdown(tokens.today))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func usageWindowRow(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(appLocalized: window.label)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(AppLocalization.format("剩余 %d%%", Int(window.remainingPercentage.rounded())))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                if let reset = window.resetsAt {
                    Text("· \(reset.formatted(.relative(presentation: .numeric)))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            ProgressView(value: window.remainingPercentage, total: 100)
                .tint(window.remainingPercentage < 10 ? .red : (window.remainingPercentage < 30 ? .orange : .green))
                .accessibilityLabel(Text(appLocalized: window.label))
                .accessibilityValue(Text("剩余 \(Int(window.remainingPercentage.rounded()))%"))
        }
    }

    private func tokenMetric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(appLocalized: label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(UsageCompactView.formatTokens(value))
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
    }

    private func tokenBreakdown(_ total: TokenUsageTotal) -> String {
        AppLocalization.format(
            "今日明细：输入 %@ · 输出 %@ · 缓存读取 %@ · 缓存写入 %@",
            UsageCompactView.formatTokens(total.input),
            UsageCompactView.formatTokens(total.output),
            UsageCompactView.formatTokens(total.cacheRead),
            UsageCompactView.formatTokens(total.cacheWrite)
        )
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(appLocalized: "正在读取 Claude Code 和 Codex 用量…")
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .foregroundColor(.secondary)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28))
            Text(appLocalized: "暂无用量数据")
                .font(.system(size: 13, weight: .semibold))
            Button("重试") { Task { await service.refresh(reason: .retry) } }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .foregroundColor(.secondary)
    }

    private func stateText(_ state: UsageAccountState) -> String {
        switch state {
        case .available: return "已连接"
        case .stale: return "数据可能已过期"
        case .unavailable: return "未检测到限额"
        }
    }
}
