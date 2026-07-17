import SwiftUI

struct UsageCompactView: View {
    @ObservedObject private var service = UsageService.shared
    let selectedProvider: UsageProviderID?

    init(selectedProvider: UsageProviderID? = nil) {
        self.selectedProvider = selectedProvider
    }

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            if let presentation = compactPresentation {
                HStack(spacing: 5) {
                    Image(presentation.provider.logoAssetName)
                        .resizable()
                        .renderingMode(.original)
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)

                    Text(verbatim: "\(presentation.remainingPercentage)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundColor(.white.opacity(0.86))

                    if service.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityText(for: presentation)))
            }
        }
        .onAppear { service.start() }
    }

    private var compactMetric: UsageCompactMetric {
        UsageCompactMetricResolver.resolve(
            snapshot: service.snapshot,
            selectedProvider: selectedProvider
        )
    }

    private var compactPresentation: UsageCompactBrandPresentation? {
        UsageCompactBrandPresentationResolver.resolve(metric: compactMetric)
    }

    private func accessibilityText(for presentation: UsageCompactBrandPresentation) -> String {
        AppLocalization.format(
            "%@ 账号用量：剩余 %d%%",
            presentation.provider.displayName,
            presentation.remainingPercentage
        )
    }

    static func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return value.formatted()
    }
}
