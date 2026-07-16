import XCTest
@testable import CC_FLOW

final class FlowIslandProviderSummaryTests: XCTestCase {
    func testCountsProvidersAndTraeVariantsSeparately() {
        let sessions = [
            makeSession(id: "claude:1", provider: .claude, kind: .claudeCode, attention: true),
            makeSession(id: "codex:1", provider: .codex, kind: .codex, attention: true),
            makeSession(
                id: "trae:1",
                provider: .trae,
                kind: .trae,
                bundleIdentifier: TraeVariant.traeCN.bundleIdentifier,
                attention: true
            ),
            makeSession(
                id: "trae:2",
                provider: .trae,
                kind: .trae,
                bundleIdentifier: TraeVariant.trae.bundleIdentifier,
                attention: false
            )
        ]
        let summary = FlowIslandProviderSummary(sessions: sessions)

        XCTAssertEqual(summary.pendingCount(for: SessionProvider.claude), 1)
        XCTAssertEqual(summary.pendingCount(for: SessionProvider.codex), 1)
        XCTAssertEqual(summary.pendingCount(for: SessionProvider.trae), 1)
        XCTAssertEqual(summary.pendingCount(for: TraeVariant.traeCN), 1)
        XCTAssertEqual(summary.pendingCount(for: TraeVariant.trae), 0)
        XCTAssertEqual(summary.totalPendingCount, 3)
    }

    func testPreferredSessionChoosesLatestAttentionSessionBeforeNewerActiveSession() {
        let olderAttention = makeSession(
            id: "codex:attention",
            provider: .codex,
            kind: .codex,
            attention: true,
            lastActivity: Date(timeIntervalSince1970: 10)
        )
        let newerActive = makeSession(
            id: "codex:active",
            provider: .codex,
            kind: .codex,
            attention: false,
            lastActivity: Date(timeIntervalSince1970: 20)
        )

        let summary = FlowIslandProviderSummary(sessions: [newerActive, olderAttention])
        XCTAssertEqual(summary.preferredSession(for: .codex)?.sessionId, "codex:attention")
    }

    private func makeSession(
        id: String,
        provider: SessionProvider,
        kind: SessionClientKind,
        bundleIdentifier: String? = nil,
        attention: Bool,
        lastActivity: Date = Date()
    ) -> SessionState {
        SessionState(
            sessionId: id,
            cwd: "/tmp/project",
            provider: provider,
            clientInfo: SessionClientInfo(kind: kind, bundleIdentifier: bundleIdentifier),
            phase: attention
                ? .waitingForApproval(PermissionContext(toolUseId: "tool", toolName: "Bash", receivedAt: lastActivity))
                : .processing,
            lastActivity: lastActivity
        )
    }
}
