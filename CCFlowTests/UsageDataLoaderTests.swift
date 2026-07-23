import AppKit
import XCTest
@testable import CC_FLOW

final class UsageDataLoaderTests: XCTestCase {
    func testLeftFeatureExpandedSizeDefaultsToSharedMineradioWidth() {
        let feature = LeftFeature(kind: .newsnow(baseURL: "https://example.com"))

        XCTAssertEqual(feature.resolvedExpandedWidth, 900)
        XCTAssertEqual(feature.resolvedExpandedHeight, 460)
    }

    func testLeftFeatureCustomExpandedSizeOverridesDefaults() {
        let feature = LeftFeature(
            kind: .music,
            expandedWidth: 920,
            expandedHeight: 540
        )

        XCTAssertEqual(feature.resolvedExpandedWidth, 920)
        XCTAssertEqual(feature.resolvedExpandedHeight, 540)
    }

    func testLeftFeatureDecodesWithoutGlobalShortcut() throws {
        let feature = LeftFeature(
            id: LeftFeature.usageID,
            kind: .usage,
            isEnabled: true,
            sortOrder: 0
        )
        let encoded = try JSONEncoder().encode(feature)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "globalShortcut")

        let decoded = try JSONDecoder().decode(
            LeftFeature.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.kind, .usage)
        XCTAssertNil(decoded.globalShortcut)
    }

    func testLeftFeatureShortcutRoundTrips() throws {
        let shortcut = try XCTUnwrap(GlobalShortcut(keyCode: 40, modifierFlags: [.option, .command]))
        let feature = LeftFeature(kind: .usage, globalShortcut: shortcut)

        let decoded = try JSONDecoder().decode(LeftFeature.self, from: JSONEncoder().encode(feature))

        XCTAssertEqual(decoded.globalShortcut, shortcut)
    }

    func testLeftFeatureCrossDomainLoginDefaultsOffForLegacyDataAndRoundTrips() throws {
        let feature = LeftFeature(kind: .webURL(url: "https://example.com"))
        let encoded = try JSONEncoder().encode(feature)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "keepsCrossDomainLoginInWebView")

        let legacyDecoded = try JSONDecoder().decode(
            LeftFeature.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertFalse(legacyDecoded.keepsCrossDomainLoginInWebView)

        let enabled = LeftFeature(
            kind: .webURL(url: "https://chatgpt.com"),
            keepsCrossDomainLoginInWebView: true
        )
        let roundTripped = try JSONDecoder().decode(
            LeftFeature.self,
            from: JSONEncoder().encode(enabled)
        )
        XCTAssertTrue(roundTripped.keepsCrossDomainLoginInWebView)
    }

    func testCustomAreaWebNavigationPolicyKeepsOnlyEnabledWebsiteCrossDomainNavigationEmbedded() {
        let common = (
            scheme: "https",
            isMainFrame: true,
            isSameHost: false,
            allowsNetworkAccess: true
        )

        XCTAssertEqual(
            CustomAreaWebNavigationPolicy.decision(
                scheme: common.scheme,
                isMainFrame: common.isMainFrame,
                isSameHost: common.isSameHost,
                source: .remoteURL,
                allowsNetworkAccess: common.allowsNetworkAccess,
                keepsCrossDomainLoginInWebView: false
            ),
            .openExternally
        )
        XCTAssertEqual(
            CustomAreaWebNavigationPolicy.decision(
                scheme: common.scheme,
                isMainFrame: common.isMainFrame,
                isSameHost: common.isSameHost,
                source: .remoteURL,
                allowsNetworkAccess: common.allowsNetworkAccess,
                keepsCrossDomainLoginInWebView: true
            ),
            .allowInWebView
        )
        XCTAssertEqual(
            CustomAreaWebNavigationPolicy.decision(
                scheme: "https",
                isMainFrame: true,
                isSameHost: true,
                source: .remoteURL,
                allowsNetworkAccess: true,
                keepsCrossDomainLoginInWebView: false
            ),
            .allowInWebView
        )
    }

    func testCustomAreaWebNavigationPolicyPreservesLocalAndBuiltinBehavior() {
        XCTAssertEqual(
            CustomAreaWebNavigationPolicy.decision(
                scheme: "https",
                isMainFrame: true,
                isSameHost: false,
                source: .localArea,
                allowsNetworkAccess: true,
                keepsCrossDomainLoginInWebView: true
            ),
            .openExternally
        )
        XCTAssertEqual(
            CustomAreaWebNavigationPolicy.decision(
                scheme: "https",
                isMainFrame: true,
                isSameHost: false,
                source: .mineradio,
                allowsNetworkAccess: true,
                keepsCrossDomainLoginInWebView: false
            ),
            .allowInWebView
        )
        XCTAssertEqual(
            CustomAreaWebNavigationPolicy.decision(
                scheme: "https",
                isMainFrame: false,
                isSameHost: false,
                source: .localArea,
                allowsNetworkAccess: false,
                keepsCrossDomainLoginInWebView: true
            ),
            .cancel
        )
    }

    func testCustomAreaWebNavigationPolicyLoadsOnlyEnabledWebsiteHTTPPopups() {
        XCTAssertTrue(
            CustomAreaWebNavigationPolicy.shouldLoadPopupInCurrentWebView(
                scheme: "https",
                source: .remoteURL,
                keepsCrossDomainLoginInWebView: true
            )
        )
        XCTAssertFalse(
            CustomAreaWebNavigationPolicy.shouldLoadPopupInCurrentWebView(
                scheme: "https",
                source: .remoteURL,
                keepsCrossDomainLoginInWebView: false
            )
        )
        XCTAssertFalse(
            CustomAreaWebNavigationPolicy.shouldLoadPopupInCurrentWebView(
                scheme: "https",
                source: .mineradio,
                keepsCrossDomainLoginInWebView: true
            )
        )
        XCTAssertFalse(
            CustomAreaWebNavigationPolicy.shouldLoadPopupInCurrentWebView(
                scheme: "mailto",
                source: .remoteURL,
                keepsCrossDomainLoginInWebView: true
            )
        )
    }

    @MainActor
    func testShortcutConflictChecksFixedAndDisabledFeatureOwners() throws {
        let shortcut = try XCTUnwrap(GlobalShortcut(keyCode: 40, modifierFlags: [.option, .command]))
        let feature = LeftFeature(
            id: "disabled-feature",
            kind: .music,
            isEnabled: false,
            globalShortcut: shortcut
        )

        XCTAssertEqual(
            LeftFeatureStore.conflictingShortcutOwner(
                for: shortcut,
                fixedShortcuts: [(.openActiveSession, shortcut)],
                features: [feature]
            ),
            GlobalShortcutAction.openActiveSession.title
        )
        XCTAssertEqual(
            LeftFeatureStore.conflictingShortcutOwner(
                for: shortcut,
                fixedShortcuts: [],
                features: [feature]
            ),
            feature.displayName
        )
        XCTAssertNil(
            LeftFeatureStore.conflictingShortcutOwner(
                for: shortcut,
                fixedShortcuts: [],
                features: [feature],
                excludingFeatureID: feature.id
            )
        )
    }

    @MainActor
    func testUsageFeatureMigrationInsertsEnabledFeatureFirstAndIsIdempotent() {
        let source = [
            LeftFeature(id: LeftFeature.musicID, kind: .music, isEnabled: false, sortOrder: 0),
            LeftFeature(id: LeftFeature.shelfID, kind: .shelf, isEnabled: true, sortOrder: 1)
        ]

        let migrated = LeftFeatureStore.featuresByEnsuringUsageFeature(source)
        let ordered = migrated.sorted { $0.sortOrder < $1.sortOrder }

        XCTAssertEqual(ordered.first?.id, LeftFeature.usageID)
        XCTAssertEqual(ordered.first?.isEnabled, true)
        XCTAssertNil(ordered.first?.expandedWidth)
        XCTAssertEqual(LeftFeatureStore.featuresByEnsuringUsageFeature(migrated), migrated)
    }

    @MainActor
    func testProductivityFeatureMigrationAppendsDisabledFeaturesAndIsIdempotent() {
        let source = [
            LeftFeature(id: LeftFeature.musicID, kind: .music, isEnabled: true, sortOrder: 4),
            LeftFeature(id: LeftFeature.systemMonitorID, kind: .systemMonitor, isEnabled: true, sortOrder: 9)
        ]

        let migrated = LeftFeatureStore.featuresByEnsuringProductivityFeatures(source)
        let productivityIDs = Set([
            LeftFeature.systemMonitorID, LeftFeature.calendarID, LeftFeature.githubID,
            LeftFeature.fileCardsID, LeftFeature.downloadMonitorID,
            LeftFeature.browserResourcesID, LeftFeature.mailAssistantID
        ])

        XCTAssertEqual(Set(migrated.filter { productivityIDs.contains($0.id) }.map(\.id)), productivityIDs)
        XCTAssertEqual(migrated.first(where: { $0.id == LeftFeature.systemMonitorID })?.isEnabled, true)
        XCTAssertTrue(migrated.filter { $0.id != LeftFeature.systemMonitorID && productivityIDs.contains($0.id) }.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(migrated.filter { productivityIDs.contains($0.id) }.allSatisfy { $0.expandedWidth == nil })
        XCTAssertEqual(migrated.prefix(source.count).map(\.id), source.map(\.id))
        XCTAssertEqual(LeftFeatureStore.featuresByEnsuringProductivityFeatures(migrated), migrated)
    }

    @MainActor
    func testNaturalSearchMigrationMergesIntoFileWatch() {
        let source = [
            LeftFeature(id: LeftFeature.musicID, kind: .music, isEnabled: true, sortOrder: 0),
            LeftFeature(id: LeftFeature.naturalSearchID, kind: .naturalSearch, isEnabled: true, sortOrder: 2),
            LeftFeature(id: LeftFeature.fileCardsID, kind: .fileCards, isEnabled: false, sortOrder: 4),
            LeftFeature(id: LeftFeature.shelfID, kind: .shelf, isEnabled: true, sortOrder: 5)
        ]
        let migrated = LeftFeatureStore.featuresByMergingNaturalSearchIntoFileWatch(source)
        XCTAssertFalse(migrated.contains { $0.id == LeftFeature.naturalSearchID || $0.kind == .naturalSearch })
        XCTAssertEqual(migrated.first(where: { $0.id == LeftFeature.fileCardsID })?.isEnabled, true)
        XCTAssertEqual(migrated.first(where: { $0.id == LeftFeature.fileCardsID })?.sortOrder, 4)
        XCTAssertEqual(migrated.first(where: { $0.id == LeftFeature.shelfID })?.sortOrder, 5)
        XCTAssertEqual(LeftFeatureStore.featuresByMergingNaturalSearchIntoFileWatch(migrated), migrated)
    }

    @MainActor
    func testNewsNowMigrationPreservesPreferencesAndBecomesAIHot() {
        let source = [LeftFeature(id: LeftFeature.newsnowID, kind: .newsnow(baseURL: "https://old.example"),
            isEnabled: false, sortOrder: 7, customIconName: "img:favicon-old.png", expandedWidth: 812,
            expandedHeight: 455, expandedPinned: true)]
        let migrated = LeftFeatureStore.featuresByMigratingNewsNowToAIHot(source)
        XCTAssertEqual(migrated[0].kind, .newsnow(baseURL: LeftFeatureStore.aiHotURL))
        XCTAssertEqual(migrated[0].sortOrder, 7)
        XCTAssertEqual(migrated[0].expandedWidth, 812)
        XCTAssertEqual(migrated[0].expandedPinned, true)
        XCTAssertNil(migrated[0].customIconName)
        XCTAssertEqual(LeftFeatureStore.featuresByMigratingNewsNowToAIHot(migrated), migrated)
    }

    @MainActor
    func testBuiltinDefaultWidthMigrationClearsKnownPresetsAndPreservesCustomWidths() {
        let source = [
            LeftFeature(id: LeftFeature.usageID, kind: .usage, expandedWidth: 680),
            LeftFeature(id: LeftFeature.mineradioID, kind: .mineradio(pageURL: "https://mineradio.art"), expandedWidth: 900),
            LeftFeature(id: LeftFeature.calendarID, kind: .calendar, expandedWidth: 760),
            LeftFeature(id: LeftFeature.githubID, kind: .github, expandedWidth: 850),
            LeftFeature(id: LeftFeature.usageID, kind: .usage, expandedWidth: 700),
            LeftFeature(id: LeftFeature.usageID, kind: .usage, expandedWidth: 900)
        ]

        let migrated = LeftFeatureStore.featuresByNormalizingBuiltinDefaultExpandedWidths(source)

        XCTAssertNil(migrated[0].expandedWidth)
        XCTAssertNil(migrated[1].expandedWidth)
        XCTAssertNil(migrated[2].expandedWidth)
        XCTAssertEqual(migrated[3].expandedWidth, 850)
        XCTAssertEqual(migrated[4].expandedWidth, 700)
        XCTAssertEqual(migrated[5].expandedWidth, 900)
        XCTAssertEqual(LeftFeatureStore.featuresByNormalizingBuiltinDefaultExpandedWidths(migrated), migrated)
    }

    func testProductivityKindsRoundTrip() throws {
        let kinds: [LeftFeatureKind] = [
            .systemMonitor, .calendar, .github, .fileCards, .naturalSearch,
            .downloadMonitor, .browserResources, .mailAssistant
        ]

        for kind in kinds {
            let feature = LeftFeature(kind: kind, isEnabled: false)
            let decoded = try JSONDecoder().decode(LeftFeature.self, from: JSONEncoder().encode(feature))
            XCTAssertEqual(decoded.kind, kind)
        }
    }

    @MainActor
    func testSelectOrReenterExpandedFeatureClearsReentryRequestOnSwitch() {
        let store = LeftFeatureStore.shared
        guard store.enabledFeatures.count >= 2 else { return }
        let featureA = store.enabledFeatures[0].id
        let featureB = store.enabledFeatures[1].id

        store.setExpandedActiveFeature(id: featureA)
        XCTAssertNil(store.expandedReentryRequest)

        // 点击当前激活页面（featureA）触发重新加载请求
        store.selectOrReenterExpandedFeature(id: featureA)
        XCTAssertEqual(store.expandedReentryRequest?.featureID, featureA)
        XCTAssertNotNil(store.expandedReentryRequest?.generation)

        // 切换到不同页面（featureB），重新加载请求应被清除，仅切换激活功能
        store.selectOrReenterExpandedFeature(id: featureB)
        XCTAssertEqual(store.expandedActiveFeature?.id, featureB)
        XCTAssertNil(store.expandedReentryRequest)
    }


    func testLoaderDeduplicatesClaudeMessagesAndUsesCodexCumulativeDeltas() throws {
        UsageDataLoader.resetFileCacheForTesting()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        let timestamp = ISO8601DateFormatter.testFormatter.string(from: now)
        let claudeLine = """
        {"type":"assistant","timestamp":"\(timestamp)","message":{"id":"same-message","model":"claude-test","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":3,"cache_creation_input_tokens":2}}}
        """
        try writeLines([claudeLine, claudeLine], to: claudeRoot.appendingPathComponent("session.jsonl"))

        let codexLines = [
            """
            {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10,"cached_input_tokens":20}},"rate_limits":null}}
            """,
            """
            {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"output_tokens":20,"reasoning_output_tokens":9,"cached_input_tokens":25}},"rate_limits":{"primary":{"used_percent":30,"window_minutes":300,"reset_at":\(Int(now.timeIntervalSince1970 + 3600))}}}}
            """
        ]
        try writeLines(codexLines, to: codexRoot.appendingPathComponent("rollout-test.jsonl"))

        let statusURL = root.appendingPathComponent("status.json")
        let status: [String: Any] = [
            "captured_at": now.timeIntervalSince1970,
            "rate_limits": [
                "five_hour": ["used_percentage": 25, "resets_at": now.timeIntervalSince1970 + 1800]
            ]
        ]
        try JSONSerialization.data(withJSONObject: status).write(to: statusURL)

        let snapshot = UsageDataLoader.load(
            now: now,
            claudeRoot: claudeRoot,
            codexRoot: codexRoot,
            statusURL: statusURL,
            queryCodexAccount: false,
            currentSessionIDs: [.claude: "session", .codex: "codex-session"]
        )
        let claude = try XCTUnwrap(snapshot.providers.first { $0.provider == .claude })
        let codex = try XCTUnwrap(snapshot.providers.first { $0.provider == .codex })

        XCTAssertEqual(claude.windows.first?.usedPercentage, 25)
        XCTAssertEqual(claude.tokenSummary?.today, TokenUsageTotal(input: 10, output: 5, cacheRead: 3, cacheWrite: 2))
        XCTAssertEqual(claude.tokenSummary?.currentSession, TokenUsageTotal(input: 10, output: 5, cacheRead: 3, cacheWrite: 2))
        XCTAssertEqual(codex.windows.first?.usedPercentage, 30)
        XCTAssertEqual(codex.windows.first?.windowMinutes, 300)
        XCTAssertEqual(codex.tokenSummary?.today, TokenUsageTotal(input: 125, output: 20, cacheRead: 25, cacheWrite: 0))
        XCTAssertNil(codex.tokenSummary?.currentSession)
    }

    func testLoaderMatchesCodexCurrentSessionMetadata() throws {
        UsageDataLoader.resetFileCacheForTesting()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        let timestamp = ISO8601DateFormatter.testFormatter.string(from: now)
        try writeLines([
            """
            {"type":"session_meta","payload":{"id":"active-codex"}}
            """,
            """
            {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"output_tokens":7,"cached_input_tokens":20}}}}
            """
        ], to: codexRoot.appendingPathComponent("rollout-current.jsonl"))

        let snapshot = UsageDataLoader.load(
            now: now,
            claudeRoot: claudeRoot,
            codexRoot: codexRoot,
            statusURL: root.appendingPathComponent("missing.json"),
            queryCodexAccount: false,
            currentSessionIDs: [.codex: "active-codex"]
        )
        let codex = try XCTUnwrap(snapshot.providers.first { $0.provider == .codex })

        XCTAssertEqual(
            codex.tokenSummary?.currentSession,
            TokenUsageTotal(input: 60, output: 7, cacheRead: 20, cacheWrite: 0)
        )
    }

    func testLoaderReusesUnchangedFilesAndIncludesArchivedCodexSessions() throws {
        UsageDataLoader.resetFileCacheForTesting()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claudeRoot = root.appendingPathComponent("claude", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let archivedRoot = root.appendingPathComponent("archived", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archivedRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        let timestamp = ISO8601DateFormatter.testFormatter.string(from: now)
        let archivedFile = archivedRoot.appendingPathComponent("rollout-archived.jsonl")
        try writeLines([
            """
            {"type":"session_meta","payload":{"id":"archived-session"}}
            """,
            """
            {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":40,"output_tokens":5,"cached_input_tokens":10}}}}
            """
        ], to: archivedFile)

        let first = UsageDataLoader.load(
            now: now,
            claudeRoot: claudeRoot,
            codexRoot: codexRoot,
            codexArchivedRoot: archivedRoot,
            statusURL: root.appendingPathComponent("missing.json"),
            queryCodexAccount: false
        )
        let firstParseCount = UsageDataLoader.parsedFileCountForTesting
        let second = UsageDataLoader.load(
            now: now,
            claudeRoot: claudeRoot,
            codexRoot: codexRoot,
            codexArchivedRoot: archivedRoot,
            statusURL: root.appendingPathComponent("missing.json"),
            queryCodexAccount: false
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(UsageDataLoader.parsedFileCountForTesting, firstParseCount)
        let codex = try XCTUnwrap(first.providers.first { $0.provider == .codex })
        XCTAssertEqual(
            codex.tokenSummary?.today,
            TokenUsageTotal(input: 30, output: 5, cacheRead: 10, cacheWrite: 0)
        )

        try writeLines([
            """
            {"type":"session_meta","payload":{"id":"archived-session"}}
            """,
            """
            {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":50,"output_tokens":8,"cached_input_tokens":10}}}}
            """
        ], to: archivedFile)
        _ = UsageDataLoader.load(
            now: now,
            claudeRoot: claudeRoot,
            codexRoot: codexRoot,
            codexArchivedRoot: archivedRoot,
            statusURL: root.appendingPathComponent("missing.json"),
            queryCodexAccount: false
        )
        XCTAssertGreaterThan(UsageDataLoader.parsedFileCountForTesting, firstParseCount)
    }

    func testCancelledLoaderStopsBeforeProviderQueries() {
        let snapshot = UsageDataLoader.load(
            queryCodexAccount: false,
            shouldCancel: { true }
        )

        XCTAssertTrue(snapshot.providers.isEmpty)
    }

    func testRefreshMergePreservesLastSuccessfulWindowsAsStale() throws {
        let oldWindow = UsageWindow(
            id: "primary",
            label: "主要限额",
            usedPercentage: 40,
            resetsAt: nil,
            windowMinutes: 300
        )
        let previous = UsageSnapshot(providers: [
            ProviderUsageSnapshot(
                provider: .codex,
                accountState: .available,
                windows: [oldWindow],
                tokenSummary: TokenUsageSummary(
                    today: TokenUsageTotal(input: 10),
                    sevenDays: TokenUsageTotal(input: 10),
                    currentSession: nil
                ),
                capturedAt: Date(timeIntervalSince1970: 100),
                errorMessage: nil
            )
        ], capturedAt: Date(timeIntervalSince1970: 100))
        let incoming = UsageSnapshot(providers: [
            ProviderUsageSnapshot(
                provider: .codex,
                accountState: .unavailable,
                windows: [],
                tokenSummary: nil,
                capturedAt: nil,
                errorMessage: "响应超时"
            )
        ], capturedAt: Date(timeIntervalSince1970: 200))

        let merged = UsageService.mergingLastSuccess(new: incoming, previous: previous)
        let codex = try XCTUnwrap(merged.providers.first)

        XCTAssertEqual(codex.accountState, .stale)
        XCTAssertEqual(codex.windows, [oldWindow])
        XCTAssertEqual(codex.errorMessage, "响应超时")
        XCTAssertNil(codex.tokenSummary)
    }

    private func writeLines(_ lines: [String], to url: URL) throws {
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: url)
    }
}

private extension ISO8601DateFormatter {
    static let testFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
