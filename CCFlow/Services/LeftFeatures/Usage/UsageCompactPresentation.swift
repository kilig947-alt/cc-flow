import Foundation

nonisolated enum UsageCompactProviderSelector {
    static func select(from sessions: [SessionState]) -> UsageProviderID? {
        let eligibleSessions = sessions.filter { usageProvider(for: $0.provider) != nil }
        let activeSessions = eligibleSessions.filter(\.phase.isActive)
        let candidates = activeSessions.isEmpty ? eligibleSessions : activeSessions

        guard let selectedSession = candidates.max(by: isEarlier) else { return nil }
        return usageProvider(for: selectedSession.provider)
    }

    private static func isEarlier(_ lhs: SessionState, _ rhs: SessionState) -> Bool {
        if lhs.lastActivity != rhs.lastActivity {
            return lhs.lastActivity < rhs.lastActivity
        }
        return lhs.stableId < rhs.stableId
    }

    private static func usageProvider(for provider: SessionProvider) -> UsageProviderID? {
        switch provider {
        case .claude: return .claude
        case .codex: return .codex
        case .trae: return nil
        }
    }
}

nonisolated enum UsageCompactMetric: Equatable, Sendable {
    case providerRemaining(UsageProviderID, Double)
    case providerTodayTokens(UsageProviderID, Int)
    case providerOnly(UsageProviderID)
    case aggregateRemaining(Double)
    case aggregateTodayTokens(Int)
    case generic
}

nonisolated enum UsageCompactMetricResolver {
    static func resolve(
        snapshot: UsageSnapshot?,
        selectedProvider: UsageProviderID?
    ) -> UsageCompactMetric {
        if let selectedProvider {
            guard let providerSnapshot = snapshot?.providers.first(where: { $0.provider == selectedProvider }) else {
                return .providerOnly(selectedProvider)
            }

            if let remaining = providerSnapshot.windows.map(\.remainingPercentage).min() {
                return .providerRemaining(selectedProvider, remaining)
            }

            let today = providerSnapshot.tokenSummary?.today.total ?? 0
            return today > 0
                ? .providerTodayTokens(selectedProvider, today)
                : .providerOnly(selectedProvider)
        }

        let providers = snapshot?.providers ?? []
        if let remaining = providers.flatMap(\.windows).map(\.remainingPercentage).min() {
            return .aggregateRemaining(remaining)
        }

        let today = providers.compactMap { $0.tokenSummary?.today.total }.reduce(0, +)
        return today > 0 ? .aggregateTodayTokens(today) : .generic
    }
}

extension UsageProviderID {
    var compactDisplayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}
