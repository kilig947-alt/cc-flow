import XCTest
@testable import CC_FLOW

final class UsageCompactPresentationTests: XCTestCase {
    func testResolvesBothProvidersWithoutSessionSelection() {
        let snapshot = makeSnapshot(
            claudeWindows: [makeWindow(id: "claude", used: 28.4)],
            codexWindows: [makeWindow(id: "codex", used: 56)]
        )

        XCTAssertEqual(
            UsageCompactBrandPresentationResolver.resolve(snapshot: snapshot),
            [
                UsageCompactBrandPresentation(provider: .claude, remainingPercentage: 72),
                UsageCompactBrandPresentation(provider: .codex, remainingPercentage: 44)
            ]
        )
    }

    func testResolvesOnlyProviderWithPercentageData() {
        let snapshot = makeSnapshot(
            claudeWindows: [],
            codexWindows: [makeWindow(id: "codex", used: 56)]
        )

        XCTAssertEqual(
            UsageCompactBrandPresentationResolver.resolve(snapshot: snapshot),
            [UsageCompactBrandPresentation(provider: .codex, remainingPercentage: 44)]
        )
    }

    func testHidesProvidersWithoutUsageWindows() {
        XCTAssertEqual(
            UsageCompactBrandPresentationResolver.resolve(snapshot: makeSnapshot()),
            []
        )
        XCTAssertEqual(
            UsageCompactBrandPresentationResolver.resolve(snapshot: nil),
            []
        )
    }

    func testUsesLowestRemainingWindowForEachProvider() {
        let snapshot = makeSnapshot(
            claudeWindows: [
                makeWindow(id: "five-hour", used: 10),
                makeWindow(id: "weekly", used: 55.6)
            ]
        )

        XCTAssertEqual(
            UsageCompactBrandPresentationResolver.resolve(snapshot: snapshot),
            [UsageCompactBrandPresentation(provider: .claude, remainingPercentage: 44)]
        )
    }

    func testClampsPercentagesBeforeDisplay() {
        let snapshot = makeSnapshot(
            claudeWindows: [makeWindow(id: "claude", used: -20)],
            codexWindows: [makeWindow(id: "codex", used: 150)]
        )

        XCTAssertEqual(
            UsageCompactBrandPresentationResolver.resolve(snapshot: snapshot),
            [
                UsageCompactBrandPresentation(provider: .claude, remainingPercentage: 100),
                UsageCompactBrandPresentation(provider: .codex, remainingPercentage: 0)
            ]
        )
    }

    func testUsageProvidersUseBundledBrandAssets() {
        XCTAssertEqual(UsageProviderID.claude.logoAssetName, "ClaudeCodeLogo")
        XCTAssertEqual(UsageProviderID.codex.logoAssetName, "OpenAILogo")
    }

    private func makeSnapshot(
        claudeWindows: [UsageWindow] = [],
        codexWindows: [UsageWindow] = []
    ) -> UsageSnapshot {
        UsageSnapshot(
            providers: [
                makeProvider(.claude, windows: claudeWindows),
                makeProvider(.codex, windows: codexWindows)
            ],
            capturedAt: Date()
        )
    }

    private func makeProvider(
        _ provider: UsageProviderID,
        windows: [UsageWindow]
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            accountState: .available,
            windows: windows,
            tokenSummary: nil,
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
