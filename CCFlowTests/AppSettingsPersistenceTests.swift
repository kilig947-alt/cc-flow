import AppKit
import XCTest
@testable import CC_FLOW

@MainActor
final class AppSettingsPersistenceTests: XCTestCase {
    private static var retainedStores: [AppSettingsStore] = []

    private func makeDefaults(testName: String = #function) -> UserDefaults {
        let suiteName = "CCFlowTests.AppSettingsPersistence.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStore(defaults: UserDefaults) -> AppSettingsStore {
        let store = AppSettingsStore(defaults: defaults)
        Self.retainedStores.append(store)
        return store
    }

    private func makeStore(
        defaults: UserDefaults,
        bridgeRuntimeConfigWriter: @escaping (BridgeRuntimeConfigSnapshot) -> Void
    ) -> AppSettingsStore {
        let store = AppSettingsStore(
            defaults: defaults,
            bridgeRuntimeConfigWriter: bridgeRuntimeConfigWriter
        )
        Self.retainedStores.append(store)
        return store
    }

    func testNotificationPresentationModeDefaultsToActiveAndPersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.notificationPresentationMode, .active)

        store.notificationPresentationMode = .quiet
        XCTAssertEqual(defaults.string(forKey: "notificationPresentationMode"), "quiet")

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.notificationPresentationMode, .quiet)
    }

    func testShortcutsUseDefaultsWhenNoPreferenceExists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.shortcut(for: .openActiveSession), GlobalShortcutAction.openActiveSession.defaultShortcut)
        XCTAssertEqual(store.shortcut(for: .openLeftFeature), GlobalShortcutAction.openLeftFeature.defaultShortcut)
        XCTAssertEqual(store.shortcut(for: .openSessionList), GlobalShortcutAction.openSessionList.defaultShortcut)
    }

    func testClearedShortcutPersistsAsDisabledInsteadOfRestoringDefault() {
        let defaults = makeDefaults()
        let key = "openActiveSessionShortcut"
        let disabledKey = "openActiveSessionShortcutDisabled"
        let store = makeStore(defaults: defaults)

        store.setShortcut(nil, for: .openActiveSession)

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertNil(reloadedStore.shortcut(for: .openActiveSession))
        XCTAssertEqual(defaults.object(forKey: disabledKey) as? Bool, true)
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testSettingShortcutAfterClearReEnablesAndPersistsCustomValue() {
        let defaults = makeDefaults()
        let disabledKey = "openSessionListShortcutDisabled"
        let store = makeStore(defaults: defaults)
        let shortcut = GlobalShortcut(
            keyCode: 45,
            modifierFlags: [.control, .option]
        )

        store.setShortcut(nil, for: .openSessionList)
        store.setShortcut(shortcut, for: .openSessionList)

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.shortcut(for: .openSessionList), shortcut)
        XCTAssertEqual(defaults.object(forKey: disabledKey) as? Bool, false)
    }

    func testShortcutLegacyDictionaryMigratesToDataStorage() {
        let defaults = makeDefaults()
        let key = "openActiveSessionShortcut"
        let modifiers: NSEvent.ModifierFlags = [.control, .option]
        let expected = GlobalShortcut(
            keyCode: 42,
            modifierFlags: modifiers
        )

        defaults.set(
            [
                "keyCode": 42,
                "modifierFlags": Int(modifiers.rawValue)
            ],
            forKey: key
        )

        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.shortcut(for: .openActiveSession), expected)
        XCTAssertNotNil(defaults.data(forKey: key))
        XCTAssertNil(defaults.dictionary(forKey: key))
    }

    func testMascotOverridesLegacyDictionaryMigratesToDataStorage() {
        let defaults = makeDefaults()
        let key = "mascotOverrides"

        defaults.set(
            [
                MascotClient.trae.rawValue: MascotKind.claude.rawValue
            ],
            forKey: key
        )

        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.mascotOverride(for: .trae), .claude)
        XCTAssertNotNil(defaults.data(forKey: key))
        XCTAssertNil(defaults.dictionary(forKey: key))
    }

    func testShortcutWritesTypedDataForFreshValues() {
        let defaults = makeDefaults()
        let key = "openSessionListShortcut"
        let store = makeStore(defaults: defaults)
        let shortcut = GlobalShortcut(
            keyCode: 44,
            modifierFlags: [.command, .shift]
        )

        store.setShortcut(shortcut, for: .openSessionList)
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.shortcut(for: .openSessionList), shortcut)
        XCTAssertNotNil(defaults.data(forKey: key))
        XCTAssertNil(defaults.dictionary(forKey: key))
    }

    func testSubagentVisibilityModePersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.subagentVisibilityMode, .visible)

        store.subagentVisibilityMode = .visible
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.subagentVisibilityMode, .visible)
        XCTAssertEqual(defaults.string(forKey: "subagentVisibilityMode"), SubagentVisibilityMode.visible.rawValue)
        XCTAssertEqual(defaults.string(forKey: "codexSubagentVisibilityMode"), SubagentVisibilityMode.visible.rawValue)
    }

    func testSubagentVisibilityModeFallsBackToLegacyCodexKey() {
        let defaults = makeDefaults()
        defaults.set(SubagentVisibilityMode.hidden.rawValue, forKey: "codexSubagentVisibilityMode")

        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.subagentVisibilityMode, .hidden)
        XCTAssertEqual(defaults.string(forKey: "subagentVisibilityMode"), SubagentVisibilityMode.hidden.rawValue)
    }

    func testSubagentVisibilityModeMigratesLegacyAllValueToVisible() {
        let defaults = makeDefaults()
        defaults.set("all", forKey: "subagentVisibilityMode")

        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.subagentVisibilityMode, .visible)
    }

    func testAutoOpenCompactedNotificationPanelPersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        XCTAssertTrue(store.autoOpenCompactedNotificationPanel)

        store.autoOpenCompactedNotificationPanel = false
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.autoOpenCompactedNotificationPanel)
        XCTAssertEqual(defaults.object(forKey: "autoOpenCompactedNotificationPanel") as? Bool, false)
    }

    func testAutomaticUpdateChecksEnabledPersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        XCTAssertTrue(store.automaticUpdateChecksEnabled)

        store.automaticUpdateChecksEnabled = false

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.automaticUpdateChecksEnabled)
        XCTAssertEqual(defaults.object(forKey: "automaticUpdateChecksEnabled") as? Bool, false)
    }

    func testCompletionPromptRegexRulesUseDefaultTemplatesWhenUnset() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "completionQuickRepliesEnabled")
        defaults.set(["OK", "继续", "允许"], forKey: "completionQuickReplies")
        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.completionPromptRegexRules, CompletionPromptRegexRule.defaultTemplates)
        XCTAssertEqual(store.completionPromptRegexRules.map(\.id), [
            "builtin-question-followed-by-recommendation",
            "builtin-final-line-explicit-confirmation",
            "builtin-review-confirmation",
            "builtin-listed-options",
            "builtin-inline-or-options",
            "builtin-freeform-input",
            "builtin-trailing-question-confirmation"
        ])
        XCTAssertTrue(store.completionPromptRegexRules.allSatisfy(\.isEnabled))
        XCTAssertNil(defaults.object(forKey: "completionQuickRepliesEnabled"))
        XCTAssertNil(defaults.object(forKey: "completionQuickReplies"))
    }

    func testCompletionPromptRegexRulesPersistEditsAndDisabledState() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        store.completionPromptRegexRules[0].isEnabled = false
        store.completionPromptRegexRules[0].triggerPattern = "请审阅"
        store.completionPromptRegexRules.swapAt(0, 1)

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.completionPromptRegexRules.map(\.id), [
            "builtin-final-line-explicit-confirmation",
            "builtin-question-followed-by-recommendation",
            "builtin-review-confirmation",
            "builtin-listed-options",
            "builtin-inline-or-options",
            "builtin-freeform-input",
            "builtin-trailing-question-confirmation"
        ])
        XCTAssertFalse(reloadedStore.completionPromptRegexRules[1].isEnabled)
        XCTAssertEqual(reloadedStore.completionPromptRegexRules[1].triggerPattern, "请审阅")
    }

    func testExistingRegexRulesReceiveTrailingQuestionFallbackOnce() throws {
        let defaults = makeDefaults()
        let oldRules = Array(CompletionPromptRegexRule.defaultTemplates.prefix(3))
        defaults.set(
            try JSONEncoder().encode(oldRules),
            forKey: "completionPromptRegexRules"
        )

        let migratedStore = makeStore(defaults: defaults)
        XCTAssertEqual(
            migratedStore.completionPromptRegexRules.last?.id,
            "builtin-trailing-question-confirmation"
        )

        migratedStore.completionPromptRegexRules.removeAll {
            $0.id == "builtin-trailing-question-confirmation"
        }
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.completionPromptRegexRules.contains {
            $0.id == "builtin-trailing-question-confirmation"
        })
    }

    func testExistingRegexRulesReceiveInlineChoiceTemplateOnce() throws {
        let defaults = makeDefaults()
        let oldRules = CompletionPromptRegexRule.defaultTemplates.filter {
            $0.id != "builtin-inline-or-options"
        }
        defaults.set(
            try JSONEncoder().encode(oldRules),
            forKey: "completionPromptRegexRules"
        )

        let migratedStore = makeStore(defaults: defaults)
        let inlineIndex = try XCTUnwrap(migratedStore.completionPromptRegexRules.firstIndex {
            $0.id == "builtin-inline-or-options"
        })
        let trailingIndex = try XCTUnwrap(migratedStore.completionPromptRegexRules.firstIndex {
            $0.id == "builtin-trailing-question-confirmation"
        })
        XCTAssertLessThan(inlineIndex, trailingIndex)
        XCTAssertTrue(migratedStore.completionPromptRegexRules[inlineIndex].isEnabled)

        migratedStore.completionPromptRegexRules.removeAll {
            $0.id == "builtin-inline-or-options"
        }
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.completionPromptRegexRules.contains {
            $0.id == "builtin-inline-or-options"
        })
    }

    func testExistingTrailingQuestionRuleReceivesYesOptionOnce() throws {
        let defaults = makeDefaults()
        var oldRules = CompletionPromptRegexRule.defaultTemplates
        let trailingIndex = try XCTUnwrap(oldRules.firstIndex {
            $0.id == "builtin-trailing-question-confirmation"
        })
        oldRules[trailingIndex].staticOptions.removeAll { $0.id == "yes" }
        defaults.set(
            try JSONEncoder().encode(oldRules),
            forKey: "completionPromptRegexRules"
        )

        let migratedStore = makeStore(defaults: defaults)
        let migratedTrailing = try XCTUnwrap(migratedStore.completionPromptRegexRules.first {
            $0.id == "builtin-trailing-question-confirmation"
        })
        XCTAssertEqual(migratedTrailing.staticOptions.filter { $0.id == "yes" }.count, 1)
        XCTAssertEqual(migratedTrailing.staticOptions.last?.title, "是的")

        let reloadedStore = makeStore(defaults: defaults)
        let reloadedTrailing = try XCTUnwrap(reloadedStore.completionPromptRegexRules.first {
            $0.id == "builtin-trailing-question-confirmation"
        })
        XCTAssertEqual(reloadedTrailing.staticOptions.filter { $0.id == "yes" }.count, 1)
    }

    func testV2RepairRestoresMissingDefaultRulesAfterLegacyMigrationsCompleted() throws {
        let defaults = makeDefaults()
        let legacyRules = Array(CompletionPromptRegexRule.defaultTemplates.prefix(2))
        defaults.set(
            try JSONEncoder().encode(legacyRules),
            forKey: "completionPromptRegexRules"
        )
        defaults.set(true, forKey: "completionPromptTrailingQuestionTemplateMigrationCompleted")
        defaults.set(true, forKey: "completionPromptInlineChoiceTemplateMigrationCompleted")
        defaults.set(true, forKey: "completionPromptTrailingQuestionOptionsMigrationCompleted")

        let repairedStore = makeStore(defaults: defaults)
        XCTAssertEqual(
            repairedStore.completionPromptRegexRules.map(\.id),
            CompletionPromptRegexRule.defaultTemplates.map(\.id)
        )
        XCTAssertTrue(repairedStore.completionPromptRegexRules.allSatisfy(\.isEnabled))

        repairedStore.completionPromptRegexRules.removeAll {
            $0.id == "builtin-trailing-question-confirmation"
        }
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.completionPromptRegexRules.contains {
            $0.id == "builtin-trailing-question-confirmation"
        })
    }

    func testV3RepairAddsNewConfirmationRulesAndReviewWordingOnce() throws {
        let defaults = makeDefaults()
        let legacyReviewPattern = #"(?is)(?:请|请先|请你).{0,32}(?:审阅|审核)|(?:你|请).{0,12}确认后|确认后.{0,24}(?:继续|进入|开始)"#
        var legacyRules = CompletionPromptRegexRule.defaultTemplates.filter {
            $0.id != "builtin-question-followed-by-recommendation"
                && $0.id != "builtin-final-line-explicit-confirmation"
        }
        let reviewIndex = try XCTUnwrap(legacyRules.firstIndex {
            $0.id == "builtin-review-confirmation"
        })
        legacyRules[reviewIndex].triggerPattern = legacyReviewPattern
        let legacyListedOptionsPattern = #"(?is)(?:请选择|请确认|希望包含哪些|你希望|选择哪|选项)|(?m)^\s*(?:A|1)[.．、)]\s+\S+"#
        let listedOptionsIndex = try XCTUnwrap(legacyRules.firstIndex {
            $0.id == "builtin-listed-options"
        })
        legacyRules[listedOptionsIndex].triggerPattern = legacyListedOptionsPattern
        defaults.set(
            try JSONEncoder().encode(legacyRules),
            forKey: "completionPromptRegexRules"
        )
        defaults.set(true, forKey: "completionPromptDefaultTemplatesRepairMigrationV2Completed")

        let repairedStore = makeStore(defaults: defaults)
        XCTAssertEqual(
            repairedStore.completionPromptRegexRules.map(\.id),
            CompletionPromptRegexRule.defaultTemplates.map(\.id)
        )
        XCTAssertTrue(repairedStore.completionPromptRegexRules.first {
            $0.id == "builtin-review-confirmation"
        }?.triggerPattern.contains("评审") == true)
        XCTAssertTrue(repairedStore.completionPromptRegexRules.first {
            $0.id == "builtin-listed-options"
        }?.triggerPattern.contains("(?=.*请)") == true)

        repairedStore.completionPromptRegexRules.removeAll {
            $0.id == "builtin-final-line-explicit-confirmation"
        }
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.completionPromptRegexRules.contains {
            $0.id == "builtin-final-line-explicit-confirmation"
        })
    }

    func testHookDebugLogSettingsPersistAndWriteRuntimeConfig() {
        let defaults = makeDefaults()
        var snapshots: [BridgeRuntimeConfigSnapshot] = []
        let store = makeStore(defaults: defaults) { snapshot in
            snapshots.append(snapshot)
        }

        XCTAssertEqual(snapshots.last?.debugLoggingEnabled, true)
        XCTAssertEqual(snapshots.last?.debugLogRetentionDays, 7)
        XCTAssertEqual(snapshots.last?.debugLogMaxDirectoryMegabytes, 256)

        store.hookDebugLoggingEnabled = false
        store.hookDebugLogRetentionDays = 14
        store.hookDebugLogMaxDirectoryMegabytes = 128

        let reloadedStore = makeStore(defaults: defaults) { snapshot in
            snapshots.append(snapshot)
        }

        XCTAssertFalse(reloadedStore.hookDebugLoggingEnabled)
        XCTAssertEqual(reloadedStore.hookDebugLogRetentionDays, 14)
        XCTAssertEqual(reloadedStore.hookDebugLogMaxDirectoryMegabytes, 128)
        XCTAssertEqual(defaults.object(forKey: "hookDebugLoggingEnabled") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "hookDebugLogRetentionDays") as? Int, 14)
        XCTAssertEqual(defaults.object(forKey: "hookDebugLogMaxDirectoryMegabytes") as? Int, 128)
        XCTAssertEqual(snapshots.last?.routePromptsToTerminal, false)
        XCTAssertEqual(snapshots.last?.debugLoggingEnabled, false)
        XCTAssertEqual(snapshots.last?.debugLogRetentionDays, 14)
        XCTAssertEqual(snapshots.last?.debugLogMaxDirectoryMegabytes, 128)
    }

    func testHookDebugLogSettingsClampOutOfRangeValues() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        store.hookDebugLogRetentionDays = 500
        store.hookDebugLogMaxDirectoryMegabytes = 2

        XCTAssertEqual(
            store.hookDebugLogRetentionDays,
            BridgeRuntimeConfigSnapshot.maximumDebugLogRetentionDays
        )
        XCTAssertEqual(
            store.hookDebugLogMaxDirectoryMegabytes,
            BridgeRuntimeConfigSnapshot.minimumDebugLogMaxDirectoryMegabytes
        )
    }

    func testBridgeRuntimeConfigWriterIncludesHookDebugLogSettings() throws {
        let snapshot = BridgeRuntimeConfigSnapshot(
            routePromptsToTerminal: true,
            debugLoggingEnabled: false,
            debugLogRetentionDays: 10,
            debugLogMaxDirectoryMegabytes: 64
        )

        let data = try XCTUnwrap(BridgeRuntimeConfigWriter.payloadData(snapshot))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["routePromptsToTerminal"] as? Bool, true)
        XCTAssertEqual(json["debugLoggingEnabled"] as? Bool, false)
        XCTAssertEqual(json["debugLogRetentionDays"] as? Int, 10)
        XCTAssertEqual(json["debugLogMaxDirectoryMegabytes"] as? Int, 64)
    }

    func testUsageVisibilityPersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        XCTAssertTrue(store.showUsage)

        store.showUsage = false
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.showUsage)
        XCTAssertEqual(defaults.object(forKey: "showUsage") as? Bool, false)
    }

    func testUsageValueModePersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.usageValueMode, .remaining)

        store.usageValueMode = .remaining
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.usageValueMode, .remaining)
        XCTAssertEqual(defaults.string(forKey: "usageValueMode"), UsageValueMode.remaining.rawValue)
    }

    func testClosedNotchTrailingContentModePersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.closedNotchTrailingContentMode, .sessionCount)

        store.closedNotchTrailingContentMode = .traeTaskIcon
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.closedNotchTrailingContentMode, .traeTaskIcon)
        XCTAssertEqual(
            defaults.string(forKey: "closedNotchTrailingContentMode"),
            ClosedNotchTrailingContentMode.traeTaskIcon.rawValue
        )
    }

    func testNotchModuleWidthDefaultsClampsAndPersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.notchModuleWidth, AppSettingsStore.defaultNotchModuleWidth)

        store.notchModuleWidth = AppSettingsStore.minimumNotchModuleWidth - 20
        XCTAssertEqual(store.notchModuleWidth, AppSettingsStore.minimumNotchModuleWidth)

        store.notchModuleWidth = 332
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.notchModuleWidth, 332)
        XCTAssertEqual(defaults.double(forKey: AppSettingsDefaultKeys.notchModuleWidth), 332)
    }

    func testExpandedPanelWidthDefaultsClampsAndPersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.expandedPanelWidth, AppSettingsStore.defaultExpandedPanelWidth)

        store.expandedPanelWidth = 400
        XCTAssertEqual(store.expandedPanelWidth, AppSettingsStore.minimumExpandedPanelWidth)

        store.expandedPanelWidth = 1800
        XCTAssertEqual(store.expandedPanelWidth, AppSettingsStore.maximumExpandedPanelWidth)

        store.expandedPanelWidth = 1040
        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.expandedPanelWidth, 1040)
        XCTAssertEqual(defaults.double(forKey: AppSettingsDefaultKeys.expandedPanelWidth), 1040)

        defaults.set(1800, forKey: AppSettingsDefaultKeys.expandedPanelWidth)
        let normalizedStore = makeStore(defaults: defaults)
        XCTAssertEqual(normalizedStore.expandedPanelWidth, AppSettingsStore.maximumExpandedPanelWidth)
    }

    func testSurfaceModePersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        store.surfaceMode = .floatingPet

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.surfaceMode, .floatingPet)
        XCTAssertEqual(defaults.string(forKey: AppSettingsDefaultKeys.surfaceMode), IslandSurfaceMode.floatingPet.rawValue)
    }

    func testFloatingPetSizeModePersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        XCTAssertEqual(store.floatingPetSizeMode, .automatic)

        store.floatingPetSizeMode = .large

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.floatingPetSizeMode, .large)
        XCTAssertEqual(
            defaults.string(forKey: AppSettingsDefaultKeys.floatingPetSizeMode),
            FloatingPetSizeMode.large.rawValue
        )
    }

    func testPreviewMascotKindPersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        store.previewMascotKind = MascotKind(themeID: "frieren")

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.previewMascotKind, MascotKind(themeID: "frieren"))
        XCTAssertEqual(defaults.string(forKey: "previewMascotKind"), "frieren")
    }

    func testOptionalMascotClientFallsBackToPreviewMascotKind() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)
        let client: MascotClient? = nil

        store.previewMascotKind = MascotKind(themeID: "ikun")

        XCTAssertEqual(store.mascotKind(for: client), MascotKind(themeID: "ikun"))
    }

    func testFloatingPetAnchorPersists() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)
        let anchor = FloatingPetAnchor(xRatio: 0.82, yRatio: 0.14)

        store.floatingPetAnchor = anchor

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.floatingPetAnchor, anchor)
        XCTAssertNotNil(defaults.data(forKey: AppSettingsDefaultKeys.floatingPetAnchor))
    }

    func testPresentationModeOnboardingPendingPersistsAndClears() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        store.presentationModeOnboardingPending = true
        XCTAssertEqual(defaults.object(forKey: AppSettingsDefaultKeys.presentationModeOnboardingPending) as? Bool, true)

        store.presentationModeOnboardingPending = false

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.presentationModeOnboardingPending)
        XCTAssertEqual(defaults.object(forKey: AppSettingsDefaultKeys.presentationModeOnboardingPending) as? Bool, false)
    }

    func testNotchDetachmentHintPendingPersistsAndClears() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        store.notchDetachmentHintPending = true
        XCTAssertEqual(defaults.object(forKey: AppSettingsDefaultKeys.notchDetachmentHintPending) as? Bool, true)

        store.notchDetachmentHintPending = false

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.notchDetachmentHintPending)
        XCTAssertEqual(defaults.object(forKey: AppSettingsDefaultKeys.notchDetachmentHintPending) as? Bool, false)
    }

    func testFloatingPetSettingsHintPendingPersistsAndClears() {
        let defaults = makeDefaults()
        let store = makeStore(defaults: defaults)

        store.floatingPetSettingsHintPending = true
        XCTAssertEqual(defaults.object(forKey: AppSettingsDefaultKeys.floatingPetSettingsHintPending) as? Bool, true)

        store.floatingPetSettingsHintPending = false

        let reloadedStore = makeStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.floatingPetSettingsHintPending)
        XCTAssertEqual(defaults.object(forKey: AppSettingsDefaultKeys.floatingPetSettingsHintPending) as? Bool, false)
    }
}
