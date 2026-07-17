import Combine
import XCTest
@testable import CC_FLOW

@MainActor
private final class AccessibilityStatusProbe {
    var isTrusted = false
    var promptValues: [Bool] = []

    func currentStatus(prompt: Bool) -> Bool {
        promptValues.append(prompt)
        return isTrusted
    }
}

final class SettingsPanelViewModelTests: XCTestCase {
    func testClaudeAndCodexHookProfilesPreferBundledBrandAssets() throws {
        let claude = try XCTUnwrap(
            ClientProfileRegistry.managedHookProfiles.first { $0.brand == .claude }
        )
        let codex = try XCTUnwrap(
            ClientProfileRegistry.managedHookProfiles.first { $0.brand == .codex }
        )

        XCTAssertEqual(claude.logoAssetName, "ClaudeCodeLogo")
        XCTAssertTrue(claude.prefersBundledLogoOverAppIcon)
        XCTAssertEqual(codex.logoAssetName, "OpenAILogo")
        XCTAssertTrue(codex.prefersBundledLogoOverAppIcon)
    }

    func testCodexHookPresentationStatusRequiresTrustUntilEventArrives() throws {
        let profile = try XCTUnwrap(
            ClientProfileRegistry.managedHookProfiles.first { $0.brand == .codex }
        )

        XCTAssertEqual(
            SettingsPanelViewModel.hookPresentationStatus(
                for: profile,
                isInstalled: false,
                hasReceivedCodexHookEvent: false
            ),
            .notInstalled
        )
        XCTAssertEqual(
            SettingsPanelViewModel.hookPresentationStatus(
                for: profile,
                isInstalled: true,
                hasReceivedCodexHookEvent: false
            ),
            .awaitingCodexTrust
        )
        XCTAssertEqual(
            SettingsPanelViewModel.hookPresentationStatus(
                for: profile,
                isInstalled: true,
                hasReceivedCodexHookEvent: true
            ),
            .active
        )
    }

    func testNonCodexInstalledHookDoesNotRequireCodexTrust() throws {
        let profile = try XCTUnwrap(
            ClientProfileRegistry.managedHookProfiles.first { $0.brand == .claude }
        )

        XCTAssertEqual(
            SettingsPanelViewModel.hookPresentationStatus(
                for: profile,
                isInstalled: true,
                hasReceivedCodexHookEvent: false
            ),
            .installed
        )
    }

    func testCodexHookVerificationRequiresNewIngressEventAndCurrentConfiguration() async throws {
        let defaultsName = "SettingsPanelViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hooksURL = temporaryDirectory.appendingPathComponent("hooks.json")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try Data(#"{"hooks":{"SessionStart":[]}}"#.utf8).write(to: hooksURL)

        let ingressEvents = PassthroughSubject<Void, Never>()
        let viewModel = await MainActor.run {
            SettingsPanelViewModel(
                accessibilityStatusProvider: { _ in false },
                accessibilitySettingsOpener: {},
                codexHookEventPublisher: ingressEvents.eraseToAnyPublisher(),
                defaults: defaults,
                codexHooksURL: hooksURL
            )
        }

        XCTAssertFalse(
            SettingsPanelViewModel.hasVerifiedCurrentCodexHooks(defaults: defaults, hooksURL: hooksURL)
        )

        ingressEvents.send(())
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = viewModel

        XCTAssertTrue(
            SettingsPanelViewModel.hasVerifiedCurrentCodexHooks(defaults: defaults, hooksURL: hooksURL)
        )

        try Data(#"{"hooks":{"SessionStart":[{"command":"changed"}]}}"#.utf8).write(to: hooksURL)
        XCTAssertFalse(
            SettingsPanelViewModel.hasVerifiedCurrentCodexHooks(defaults: defaults, hooksURL: hooksURL)
        )
    }

    func testRefreshAccessibilityStatusUsesLatestProviderValue() async {
        await MainActor.run {
            let probe = AccessibilityStatusProbe()
            let viewModel = SettingsPanelViewModel(
                accessibilityStatusProvider: { probe.currentStatus(prompt: $0) },
                accessibilitySettingsOpener: {}
            )

            viewModel.refreshAccessibilityStatus()
            XCTAssertFalse(viewModel.accessibilityEnabled)

            probe.isTrusted = true
            viewModel.refreshAccessibilityStatus()

            XCTAssertTrue(viewModel.accessibilityEnabled)
            XCTAssertEqual(probe.promptValues, [false, false])
        }
    }

    func testOpenAccessibilitySettingsPromptsBeforeOpeningSystemSettings() async {
        await MainActor.run {
            let probe = AccessibilityStatusProbe()
            var openSettingsCount = 0
            let viewModel = SettingsPanelViewModel(
                accessibilityStatusProvider: { probe.currentStatus(prompt: $0) },
                accessibilitySettingsOpener: { openSettingsCount += 1 }
            )

            viewModel.openAccessibilitySettings()

            XCTAssertFalse(viewModel.accessibilityEnabled)
            XCTAssertEqual(probe.promptValues, [true])
            XCTAssertEqual(openSettingsCount, 1)
        }
    }

    func testOpenAccessibilitySettingsDoesNotOpenSystemSettingsWhenPromptRefreshFindsAccess() async {
        await MainActor.run {
            let probe = AccessibilityStatusProbe()
            probe.isTrusted = true
            var openSettingsCount = 0
            let viewModel = SettingsPanelViewModel(
                accessibilityStatusProvider: { probe.currentStatus(prompt: $0) },
                accessibilitySettingsOpener: { openSettingsCount += 1 }
            )

            viewModel.openAccessibilitySettings()

            XCTAssertTrue(viewModel.accessibilityEnabled)
            XCTAssertEqual(probe.promptValues, [true])
            XCTAssertEqual(openSettingsCount, 0)
        }
    }
}
