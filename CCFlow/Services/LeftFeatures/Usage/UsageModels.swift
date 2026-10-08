import Foundation

nonisolated enum UsageProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case antigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        }
    }

    var logoAssetName: String {
        switch self {
        case .claude: return "ClaudeCodeLogo"
        case .codex: return "OpenAILogo"
        case .antigravity: return "AntigravityLogo"
        }
    }

    var logoSystemName: String? {
        nil
    }
}

nonisolated struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var usedPercentage: Double
    var resetsAt: Date?
    var windowMinutes: Int?

    /// Old snapshots contain display text; newer snapshots store stable label keys.
    /// Resolve at presentation so changing language does not require a network refresh.
    func localizedLabel(locale: Locale) -> String {
        let legacyKeys: [String: String] = [
            "5 小时": "usage.duration_5_hours",
            "7 天": "usage.duration_7_days",
            "主要限额": "usage.primary_limit",
            "次要限额": "usage.secondary_limit",
        ]
        if id.hasPrefix("antigravity-"), let separator = label.range(of: " · ") {
            let cadenceKey: String?
            if id.hasSuffix("-five-hour") { cadenceKey = "usage.duration_5_hour_quota" }
            else if id.hasSuffix("-weekly") { cadenceKey = "usage.weekly_quota" }
            else { cadenceKey = nil }
            if let cadenceKey {
                return String(label[..<separator.lowerBound]) + " · " + AppLocalization.string(cadenceKey, locale: locale)
            }
        }
        return AppLocalization.string(legacyKeys[label] ?? label, locale: locale)
    }

    var remainingPercentage: Double {
        max(0, min(100, 100 - usedPercentage))
    }
}

nonisolated struct TokenUsageTotal: Codable, Equatable, Sendable {
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheWrite: Int = 0

    var total: Int { input + output + cacheRead + cacheWrite }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite
        )
    }
}

nonisolated struct TokenUsageSummary: Codable, Equatable, Sendable {
    var today: TokenUsageTotal
    var sevenDays: TokenUsageTotal
    var currentSession: TokenUsageTotal?
}

nonisolated enum UsageAccountState: String, Codable, Sendable {
    case available
    case unavailable
    case stale
}

nonisolated struct ProviderUsageSnapshot: Codable, Equatable, Identifiable, Sendable {
    var provider: UsageProviderID
    var accountState: UsageAccountState
    var windows: [UsageWindow]
    var tokenSummary: TokenUsageSummary?
    var capturedAt: Date?
    var errorMessage: String?

    var id: UsageProviderID { provider }
}

nonisolated struct UsageSnapshot: Codable, Equatable, Sendable {
    var providers: [ProviderUsageSnapshot]
    var capturedAt: Date
}

nonisolated enum UsageRefreshReason: Sendable {
    case passive
    case becameActive
    case shortcut
    case retry
}
