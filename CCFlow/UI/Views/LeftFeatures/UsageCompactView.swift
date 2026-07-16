import SwiftUI

struct UsageCompactView: View {
    @ObservedObject private var service = UsageService.shared
    let selectedProvider: UsageProviderID?

    init(selectedProvider: UsageProviderID? = nil) {
        self.selectedProvider = selectedProvider
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 11, weight: .semibold))
            Text(compactText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            if service.isRefreshing {
                ProgressView().controlSize(.mini)
            }
        }
        .foregroundColor(.white.opacity(0.86))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityText))
        .onAppear { service.start() }
    }

    private var compactMetric: UsageCompactMetric {
        UsageCompactMetricResolver.resolve(
            snapshot: service.snapshot,
            selectedProvider: selectedProvider
        )
    }

    private var compactText: String {
        switch compactMetric {
        case .providerRemaining(let provider, let remaining):
            return AppLocalization.format("%@ %d%%", provider.compactDisplayName, Int(remaining.rounded()))
        case .providerTodayTokens(let provider, let today):
            return AppLocalization.format("%@ 今日 %@", provider.compactDisplayName, Self.formatTokens(today))
        case .providerOnly(let provider):
            return AppLocalization.format("%@ 用量", provider.compactDisplayName)
        case .aggregateRemaining(let remaining):
            return AppLocalization.format("剩余 %d%%", Int(remaining.rounded()))
        case .aggregateTodayTokens(let today):
            return AppLocalization.format("今日 %@", Self.formatTokens(today))
        case .generic:
            return AppLocalization.string("用量")
        }
    }

    private var accessibilityText: String {
        switch compactMetric {
        case .providerRemaining(let provider, let remaining):
            return AppLocalization.format(
                "%@ 账号用量：剩余 %d%%",
                provider.displayName,
                Int(remaining.rounded())
            )
        case .providerTodayTokens(let provider, let today):
            return AppLocalization.format(
                "%@ 账号用量：今日 %@ 个令牌",
                provider.displayName,
                Self.formatTokens(today)
            )
        case .providerOnly(let provider):
            return AppLocalization.format("%@ 账号用量", provider.displayName)
        case .aggregateRemaining(let remaining):
            return AppLocalization.format("账号用量：剩余 %d%%", Int(remaining.rounded()))
        case .aggregateTodayTokens(let today):
            return AppLocalization.format("账号用量：今日 %@ 个令牌", Self.formatTokens(today))
        case .generic:
            return AppLocalization.string("账号用量")
        }
    }

    static func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return value.formatted()
    }
}
