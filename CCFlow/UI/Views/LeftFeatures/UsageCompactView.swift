import SwiftUI

struct UsageCompactView: View {
    @ObservedObject private var service = UsageService.shared

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 11, weight: .semibold))
            Text(compactText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
            if service.isRefreshing {
                ProgressView().controlSize(.mini)
            }
        }
        .foregroundColor(.white.opacity(0.86))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(appLocalized: "账号用量"))
        .onAppear { service.start() }
    }

    private var compactText: String {
        let windows = service.snapshot?.providers.flatMap(\.windows) ?? []
        if let remaining = windows.map(\.remainingPercentage).min() {
            return AppLocalization.format("剩余 %d%%", Int(remaining.rounded()))
        }
        let today = service.snapshot?.providers.compactMap { $0.tokenSummary?.today.total }.reduce(0, +) ?? 0
        return today > 0 ? AppLocalization.format("今日 %@", Self.formatTokens(today)) : AppLocalization.string("用量")
    }

    static func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return value.formatted()
    }
}
