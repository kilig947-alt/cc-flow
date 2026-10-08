import SwiftUI

struct UsageExpandedView: View {
    @ObservedObject private var service = UsageService.shared

    @Environment(\.locale) private var localizationLocale

    var body: some View {
        // Recompute formatted strings when the app language changes.
        let _ = localizationLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let snapshot = service.snapshot {
                    ForEach(displayProviders(from: snapshot)) { provider in
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

    private func displayProviders(from snapshot: UsageSnapshot) -> [ProviderUsageSnapshot] {
        UsageProviderID.allCases.map { provider in
            snapshot.providers.first(where: { $0.provider == provider })
                ?? ProviderUsageSnapshot(
                    provider: provider,
                    accountState: .unavailable,
                    windows: [],
                    tokenSummary: nil,
                    capturedAt: nil,
                    errorMessage: service.isRefreshing && provider == .antigravity
                        ? AppLocalization.runtimeString("usage.detecting_antigravity_local_usage_service")
                        : nil
                )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(appLocalized: "usage.account_usage")
                    .font(.system(size: 16, weight: .bold))
                if let date = service.snapshot?.capturedAt {
                    Text(AppLocalization.format(
                        "usage.updated",
                        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(localizationLocale))
                    ))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await service.refresh(reason: .retry) }
            } label: {
                Label(service.isRefreshing ? AppLocalization.runtimeString("usage.refreshing") : AppLocalization.runtimeString("settings.refresh"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minWidth: 70, minHeight: 44)
            .disabled(service.isRefreshing)
            .accessibilityLabel(Text(appLocalized: "usage.refresh_account_usage"))
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
                Text(appLocalized: emptyMessage(for: provider.provider))
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
                    tokenMetric(AppLocalization.runtimeString("usage.today"), tokens.today.total)
                    tokenMetric(AppLocalization.runtimeString("usage.duration_7_days"), tokens.sevenDays.total)
                    if let current = tokens.currentSession {
                        tokenMetric(AppLocalization.runtimeString("usage.current_session"), current.total)
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
                Text(verbatim: window.localizedLabel(locale: localizationLocale))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(AppLocalization.format("usage.remaining", Int(window.remainingPercentage.rounded())))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                if let reset = window.resetsAt {
                    Text("· \(reset.formatted(.relative(presentation: .numeric).locale(localizationLocale)))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(usageBarColor(for: window.remainingPercentage))
                        .frame(
                            width: proxy.size.width
                                * CGFloat(min(max(window.remainingPercentage, 0), 100)) / 100
                        )
                }
            }
                .frame(height: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: window.localizedLabel(locale: localizationLocale)))
                .accessibilityValue(Text(AppLocalization.format("usage.remaining_2", String(describing: Int(window.remainingPercentage.rounded())))))
        }
    }

    private func usageBarColor(for remainingPercentage: Double) -> Color {
        if remainingPercentage < 10 { return .red }
        if remainingPercentage < 30 { return .orange }
        return .green
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
            "usage.today_input_output_cache_read_cache_write",
            UsageCompactView.formatTokens(total.input),
            UsageCompactView.formatTokens(total.output),
            UsageCompactView.formatTokens(total.cacheRead),
            UsageCompactView.formatTokens(total.cacheWrite)
        )
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(appLocalized: "usage.loading_claude_code_codex_and_antigravity_usage")
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .foregroundColor(.secondary)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28))
            Text(appLocalized: "usage.no_usage_data")
                .font(.system(size: 13, weight: .semibold))
            Button("usage.retry") { Task { await service.refresh(reason: .retry) } }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .foregroundColor(.secondary)
    }

    private func stateText(_ state: UsageAccountState) -> String {
        switch state {
        case .available: return AppLocalization.runtimeString("github.connected")
        case .stale: return AppLocalization.runtimeString("usage.data_may_be_stale")
        case .unavailable: return AppLocalization.runtimeString("usage.limits_not_detected")
        }
    }

    private func emptyMessage(for provider: UsageProviderID) -> String {
        switch provider {
        case .claude:
            return AppLocalization.runtimeString("usage.start_claude_code_and_complete_one_request_to")
        case .codex:
            return AppLocalization.runtimeString("usage.no_limits_were_detected_in_local_codex_sessions")
        case .antigravity:
            return AppLocalization.runtimeString("usage.launch_antigravity_and_sign_in_to_view_model")
        }
    }
}
