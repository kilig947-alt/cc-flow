import Foundation

nonisolated enum UsageProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

nonisolated struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var usedPercentage: Double
    var resetsAt: Date?
    var windowMinutes: Int?

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
