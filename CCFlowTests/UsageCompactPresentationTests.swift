import XCTest
@testable import CC_FLOW

final class UsageCompactPresentationTests: XCTestCase {
    func testSelectsMostRecentActiveEligibleProvider() {
        let now = Date()
        let sessions = [
            makeSession(id: "claude", provider: .claude, phase: .processing, activity: now.addingTimeInterval(-30)),
            makeSession(id: "codex", provider: .codex, phase: .compacting, activity: now)
        ]

        XCTAssertEqual(UsageCompactProviderSelector.select(from: sessions), .codex)
    }

    func testActiveEligibleSessionWinsOverNewerIdleSession() {
        let now = Date()
        let sessions = [
            makeSession(id: "claude", provider: .claude, phase: .processing, activity: now.addingTimeInterval(-30)),
            makeSession(id: "codex", provider: .codex, phase: .idle, activity: now)
        ]

        XCTAssertEqual(UsageCompactProviderSelector.select(from: sessions), .claude)
    }

    func testFallsBackToMostRecentEligibleSessionWhenNoneAreActive() {
        let now = Date()
        let sessions = [
            makeSession(id: "claude", provider: .claude, phase: .ended, activity: now.addingTimeInterval(-30)),
            makeSession(id: "codex", provider: .codex, phase: .waitingForInput, activity: now)
        ]

        XCTAssertEqual(UsageCompactProviderSelector.select(from: sessions), .codex)
    }

    func testIgnoresTraeProvider() {
        let sessions = [
            makeSession(id: "trae", provider: .trae, phase: .processing, activity: Date())
        ]

        XCTAssertNil(UsageCompactProviderSelector.select(from: sessions))
    }

    func testSelectedProviderRemainingIgnoresOtherProvider() {
        let snapshot = makeSnapshot(
            claudeWindows: [makeWindow(id: "claude", used: 20)],
            codexWindows: [makeWindow(id: "codex", used: 95)]
        )

        XCTAssertEqual(
            UsageCompactMetricResolver.resolve(snapshot: snapshot, selectedProvider: .claude),
            .providerRemaining(.claude, 80)
        )
    }

    func testSelectedProviderFallsBackToItsTodayTokens() {
        let snapshot = makeSnapshot(claudeToday: 12_345, codexToday: 99_999)

        XCTAssertEqual(
            UsageCompactMetricResolver.resolve(snapshot: snapshot, selectedProvider: .claude),
            .providerTodayTokens(.claude, 12_345)
        )
    }

    func testSelectedProviderFallsBackToProviderOnlyWhenDataIsMissing() {
        let snapshot = UsageSnapshot(providers: [], capturedAt: Date())

        XCTAssertEqual(
            UsageCompactMetricResolver.resolve(snapshot: snapshot, selectedProvider: .codex),
            .providerOnly(.codex)
        )
    }

    func testNoSelectedProviderRetainsAggregateFallback() {
        let snapshot = makeSnapshot(
            claudeWindows: [makeWindow(id: "claude", used: 20)],
            codexWindows: [makeWindow(id: "codex", used: 95)]
        )

        XCTAssertEqual(
            UsageCompactMetricResolver.resolve(snapshot: snapshot, selectedProvider: nil),
            .aggregateRemaining(5)
        )
    }

    func testNoSelectedProviderFallsBackToAggregateTodayTokens() {
        let snapshot = makeSnapshot(claudeToday: 12_000, codexToday: 3_000)

        XCTAssertEqual(
            UsageCompactMetricResolver.resolve(snapshot: snapshot, selectedProvider: nil),
            .aggregateTodayTokens(15_000)
        )
    }

    func testNoSelectedProviderFallsBackToGenericWithoutUsageData() {
        XCTAssertEqual(
            UsageCompactMetricResolver.resolve(snapshot: nil, selectedProvider: nil),
            .generic
        )
    }

    func testBrandPresentationShowsSelectedProviderRemainingPercentage() {
        XCTAssertEqual(
            UsageCompactBrandPresentationResolver.resolve(metric: .providerRemaining(.claude, 51.6)),
            UsageCompactBrandPresentation(provider: .claude, remainingPercentage: 52)
        )
        XCTAssertEqual(
            UsageCompactBrandPresentationResolver.resolve(metric: .providerRemaining(.codex, 48.2)),
            UsageCompactBrandPresentation(provider: .codex, remainingPercentage: 48)
        )
    }

    func testBrandPresentationHidesEveryNonPercentageState() {
        let hiddenMetrics: [UsageCompactMetric] = [
            .providerTodayTokens(.claude, 12_345),
            .providerOnly(.codex),
            .aggregateRemaining(48),
            .aggregateTodayTokens(12_345),
            .generic
        ]

        for metric in hiddenMetrics {
            XCTAssertNil(UsageCompactBrandPresentationResolver.resolve(metric: metric))
        }
    }

    func testUsageProvidersUseBundledBrandAssets() {
        XCTAssertEqual(UsageProviderID.claude.logoAssetName, "ClaudeCodeLogo")
        XCTAssertEqual(UsageProviderID.codex.logoAssetName, "OpenAILogo")
    }

    private func makeSession(
        id: String,
        provider: SessionProvider,
        phase: SessionPhase,
        activity: Date
    ) -> SessionState {
        SessionState(
            sessionId: id,
            cwd: "/tmp/\(id)",
            provider: provider,
            phase: phase,
            lastActivity: activity
        )
    }

    private func makeSnapshot(
        claudeWindows: [UsageWindow] = [],
        codexWindows: [UsageWindow] = [],
        claudeToday: Int = 0,
        codexToday: Int = 0
    ) -> UsageSnapshot {
        UsageSnapshot(
            providers: [
                makeProvider(.claude, windows: claudeWindows, today: claudeToday),
                makeProvider(.codex, windows: codexWindows, today: codexToday)
            ],
            capturedAt: Date()
        )
    }

    private func makeProvider(
        _ provider: UsageProviderID,
        windows: [UsageWindow],
        today: Int
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            accountState: .available,
            windows: windows,
            tokenSummary: TokenUsageSummary(
                today: TokenUsageTotal(input: today),
                sevenDays: TokenUsageTotal(),
                currentSession: nil
            ),
            capturedAt: Date(),
            errorMessage: nil
        )
    }

    private func makeWindow(id: String, used: Double) -> UsageWindow {
        UsageWindow(
            id: id,
            label: id,
            usedPercentage: used,
            resetsAt: nil,
            windowMinutes: nil
        )
    }
}
