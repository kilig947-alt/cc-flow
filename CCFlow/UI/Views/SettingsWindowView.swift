import AppKit
import Carbon.HIToolbox
import Combine
import CryptoKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case display
    case mascot
    case leftContent
    case sound
    case integration
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return AppLocalization.runtimeString("settings.general")
        case .shortcuts: return AppLocalization.runtimeString("session.shortcuts")
        case .display: return AppLocalization.runtimeString("settings.display")
        case .mascot: return AppLocalization.runtimeString("settings.mascots")
        case .sound: return AppLocalization.runtimeString("settings.sound")
        case .integration: return AppLocalization.runtimeString("settings.integrations")
        case .leftContent: return AppLocalization.runtimeString("settings.left_features")
        case .about: return AppLocalization.runtimeString("settings.about")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return AppLocalization.runtimeString("settings.system_behavior")
        case .shortcuts: return AppLocalization.runtimeString("settings.global_actions_and_custom_bindings")
        case .display: return AppLocalization.runtimeString("settings.displays_and_placement")
        case .mascot: return AppLocalization.runtimeString("settings.client_mascots_and_motion")
        case .sound: return AppLocalization.runtimeString("settings.notifications_and_sounds")
        case .integration: return AppLocalization.runtimeString("settings.hooks_and_permissions")
        case .leftContent: return AppLocalization.runtimeString("settings.flow_island_and_expanded_area")
        case .about: return AppLocalization.runtimeString("settings.version_and_updates")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcuts: return "command.square.fill"
        case .display: return "rectangle.on.rectangle"
        case .mascot: return "face.smiling.fill"
        case .sound: return "speaker.wave.2.fill"
        case .integration: return "link.circle.fill"
        case .leftContent: return "globe.asia.australia.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(red: 0.12, green: 0.42, blue: 0.95)
        case .shortcuts: return Color(red: 0.25, green: 0.82, blue: 0.46)
        case .display: return Color(red: 0.46, green: 0.40, blue: 0.96)
        case .mascot: return Color(red: 0.91, green: 0.27, blue: 0.81)  // Pink
        case .sound: return Color(red: 0.22, green: 0.83, blue: 0.42)
        case .integration: return Color(red: 0.16, green: 0.76, blue: 0.72)
        case .leftContent: return Color(red: 0.34, green: 0.62, blue: 0.92)
        case .about: return Color(red: 0.17, green: 0.60, blue: 0.96)
        }
    }

    static var visibleCategories: [SettingsCategory] {
        allCases
    }
}

/// 新建功能表单的功能类型选择。
/// - localDirectory: 用户自选本地文件夹或按名称自动生成目录，承载本地 HTML
/// - webURL: 远程网站 URL，直接在 WebView 内加载
enum NewFeatureType: String, CaseIterable, Identifiable {
    case localDirectory = "本地目录"
    case webURL = "网站 URL"

    var titleKey: String {
        switch self {
        case .localDirectory: return "settings.local_directory"
        case .webURL: return "settings.website_url"
        }
    }

    var id: String { rawValue }
}

enum AccessibilityPermissionStatus {
    static let isAvailable = true

    static func isTrusted(prompt: Bool = false) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }
}

@MainActor
final class SettingsPanelViewModel: ObservableObject {
    struct HookReinstallFeedback: Equatable {
        let message: String
        let isError: Bool
    }

    enum HookPresentationStatus: Equatable {
        case notInstalled
        case installed
        case awaitingCodexTrust
        case active

        var isInstalled: Bool {
            self != .notInstalled
        }
    }

    private static let codexHookVerifiedDigestDefaultsKey = "CodexHookTrustVerification.digest.v1"

    @Published var launchAtLogin = false
    @Published private(set) var hookInstallationStates: [String: Bool] = [:]
    @Published var accessibilityEnabled = false
    @Published var isExportingLogs = false
    @Published var logExportStatus = AppLocalization.string("settings.export_diagnostic_logs_and_settings_from_the_last")
    @Published private(set) var reinstallingHookProfileID: String?
    @Published private(set) var hookReinstallFeedbacks: [String: HookReinstallFeedback] = [:]
    @Published private(set) var customHookInstallations: [HookInstaller.CustomHookInstallation] = []
    @Published private(set) var bridgeHealthStatus = HookInstaller.BridgeHealthStatus(
        isHealthy: false,
        message: AppLocalization.string("settings.bridge_link_has_not_been_checked_yet")
    )

    private var hookFeedbackClearTasks: [String: Task<Void, Never>] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var hasReceivedCodexHookEvent = false
    private let defaults: UserDefaults
    private let codexHooksURL: URL
    private let accessibilityStatusProvider: @MainActor (_ prompt: Bool) -> Bool
    private let accessibilitySettingsOpener: @MainActor () -> Void

    init(
        accessibilityStatusProvider: @escaping @MainActor (_ prompt: Bool) -> Bool = { prompt in
            AccessibilityPermissionStatus.isTrusted(prompt: prompt)
        },
        accessibilitySettingsOpener: @escaping @MainActor () -> Void = {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
                return
            }
            NSWorkspace.shared.open(url)
        },
        codexHookEventPublisher: AnyPublisher<Void, Never> = NotificationCenter.default
            .publisher(for: .ccFlowCodexHookEventReceived)
            .map { _ in () }
            .eraseToAnyPublisher(),
        defaults: UserDefaults = .standard,
        codexHooksURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json")
    ) {
        self.accessibilityStatusProvider = accessibilityStatusProvider
        self.accessibilitySettingsOpener = accessibilitySettingsOpener
        self.defaults = defaults
        self.codexHooksURL = codexHooksURL
        hasReceivedCodexHookEvent = Self.hasVerifiedCurrentCodexHooks(
            defaults: defaults,
            hooksURL: codexHooksURL
        )

        codexHookEventPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.markCodexHookEventReceived()
            }
            .store(in: &cancellables)
    }

    var visibleHookProfiles: [ManagedHookClientProfile] {
        ClientProfileRegistry.managedHookProfiles.filter { profile in
            profile.alwaysVisibleInSettings
                || ClientAppLocator.isInstalled(bundleIdentifiers: profile.localAppBundleIdentifiers)
                || HookInstaller.isInstalled(profile)
        }
    }

    var hasIntegrationNotice: Bool {
        false
    }

    func refreshInitialState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshAccessibilityStatus()
        refreshLocalizedState()
    }

    func refresh(for category: SettingsCategory) {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshAccessibilityStatus()
        refreshLocalizedState()

        switch category {
        case .display:
            ScreenSelector.shared.refreshScreens()
        case .sound:
            SoundPackCatalog.shared.refresh()
        case .integration:
            refreshHookInstallationStates()
            refreshCustomHookInstallations()
            refreshBridgeHealthStatus()
        case .general, .shortcuts, .mascot, .leftContent, .about:
            break
        }
    }

    func refreshAccessibilityStatus() {
        guard AccessibilityPermissionStatus.isAvailable else {
            accessibilityEnabled = false
            return
        }

        accessibilityEnabled = accessibilityStatusProvider(false)
    }

    func refreshLocalizedState() {
        guard !isExportingLogs else { return }
        logExportStatus = AppLocalization.string("settings.export_diagnostic_logs_and_settings_from_the_last")
    }

    func refreshBridgeHealthStatus() {
        bridgeHealthStatus = HookInstaller.bridgeHealthStatus()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func isHookInstalled(_ profile: ManagedHookClientProfile) -> Bool {
        hookInstallationStates[profile.id] ?? false
    }

    func hookPresentationStatus(for profile: ManagedHookClientProfile) -> HookPresentationStatus {
        let hasCurrentCodexVerification = hasReceivedCodexHookEvent
            && Self.hasVerifiedCurrentCodexHooks(defaults: defaults, hooksURL: codexHooksURL)
        return Self.hookPresentationStatus(
            for: profile,
            isInstalled: isHookInstalled(profile),
            hasReceivedCodexHookEvent: hasCurrentCodexVerification
        )
    }

    nonisolated static func hookPresentationStatus(
        for profile: ManagedHookClientProfile,
        isInstalled: Bool,
        hasReceivedCodexHookEvent: Bool
    ) -> HookPresentationStatus {
        guard isInstalled else { return .notInstalled }
        guard profile.brand == .codex else { return .installed }
        return hasReceivedCodexHookEvent ? .active : .awaitingCodexTrust
    }

    func installHooks(for profile: ManagedHookClientProfile) {
        resetCodexHookVerificationIfNeeded(for: profile)
        HookInstaller.install(profile)
        let didInstall = HookInstaller.isInstalled(profile)
        _ = didInstall
        refreshHookInstallationStates()
        refreshBridgeHealthStatus()
    }

    func installHooks(for profile: ManagedHookClientProfile, selection: HookInstallSelection) {
        resetCodexHookVerificationIfNeeded(for: profile)
        HookInstaller.install(profile, selection: selection)
        let didInstall = HookInstaller.isInstalled(profile)
        _ = didInstall
        refreshHookInstallationStates()
        refreshBridgeHealthStatus()
    }

    func reinstallHooks(for profile: ManagedHookClientProfile, selection: HookInstallSelection) {
        guard reinstallingHookProfileID == nil else { return }

        resetCodexHookVerificationIfNeeded(for: profile)

        HookInstaller.saveSelection(selection, for: profile)

        hookFeedbackClearTasks[profile.id]?.cancel()
        hookFeedbackClearTasks[profile.id] = nil
        hookReinstallFeedbacks[profile.id] = nil
        reinstallingHookProfileID = profile.id

        Task {
            await Task.yield()

            HookInstaller.reinstall(profile)
            let didInstall = HookInstaller.isInstalled(profile)

            try? await Task.sleep(nanoseconds: 450_000_000)

            refreshHookInstallationStates()
            refreshBridgeHealthStatus()
            reinstallingHookProfileID = nil
            hookReinstallFeedbacks[profile.id] = HookReinstallFeedback(
                message: didInstall
                    ? AppLocalization.string("settings.hook_configuration_updated")
                    : AppLocalization.string("settings.update_failed_please_try_again"),
                isError: !didInstall
            )

            hookFeedbackClearTasks[profile.id] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                hookReinstallFeedbacks[profile.id] = nil
                hookFeedbackClearTasks[profile.id] = nil
            }
        }
    }

    func currentHookSelection(for profile: ManagedHookClientProfile) -> HookInstallSelection {
        HookInstaller.loadSelection(for: profile)
    }

    func reinstallHooks(for profile: ManagedHookClientProfile) {
        guard reinstallingHookProfileID == nil else { return }

        resetCodexHookVerificationIfNeeded(for: profile)

        hookFeedbackClearTasks[profile.id]?.cancel()
        hookFeedbackClearTasks[profile.id] = nil
        hookReinstallFeedbacks[profile.id] = nil
        reinstallingHookProfileID = profile.id

        Task {
            await Task.yield()

            HookInstaller.reinstall(profile)
            let didInstall = HookInstaller.isInstalled(profile)

            try? await Task.sleep(nanoseconds: 450_000_000)

            refreshHookInstallationStates()
            refreshBridgeHealthStatus()
            reinstallingHookProfileID = nil
            hookReinstallFeedbacks[profile.id] = HookReinstallFeedback(
                message: didInstall
                    ? AppLocalization.string("settings.reinstalled_successfully")
                    : AppLocalization.string("settings.reinstall_failed_please_try_again_later"),
                isError: !didInstall
            )

            hookFeedbackClearTasks[profile.id] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                hookReinstallFeedbacks[profile.id] = nil
                hookFeedbackClearTasks[profile.id] = nil
            }
        }
    }

    func uninstallHooks(for profile: ManagedHookClientProfile) {
        resetCodexHookVerificationIfNeeded(for: profile)
        HookInstaller.uninstall(profile)
        refreshHookInstallationStates()
        refreshBridgeHealthStatus()
    }

    func installCustomHook(profileID: String, directoryPath: String) {
        HookInstaller.installCustom(profileID: profileID, directoryPath: directoryPath)
        refreshCustomHookInstallations()
    }

    func uninstallCustomHook(id: String) {
        HookInstaller.uninstallCustom(id: id)
        refreshCustomHookInstallations()
    }

    func uninstallAllHooks() {
        resetCodexHookVerification()
        HookInstaller.uninstall()
        for installation in HookInstaller.customInstallations() {
            HookInstaller.uninstallCustom(id: installation.id)
        }
        refreshHookInstallationStates()
        refreshCustomHookInstallations()
        refreshBridgeHealthStatus()
    }

    func refreshCustomHookInstallations() {
        customHookInstallations = HookInstaller.customInstallations()
    }

    func openHookConfigurationDirectory(for profile: ManagedHookClientProfile) {
        guard let directoryURL = hookConfigurationDirectoryURL(for: profile) else {
            return
        }

        NSWorkspace.shared.open(directoryURL)
    }

    func isReinstallingHooks(for profile: ManagedHookClientProfile) -> Bool {
        reinstallingHookProfileID == profile.id
    }

    func hookReinstallFeedback(for profile: ManagedHookClientProfile) -> HookReinstallFeedback? {
        hookReinstallFeedbacks[profile.id]
    }

    func hookNotice(for profile: ManagedHookClientProfile) -> String? {
        if !profile.supportsHookIntegration {
            return AppLocalization.runtimeString("settings.official_hooks_configuration_is_not_yet_supported")
        }
        return nil
    }

    func prepareCodexHookTrustReview(openTerminal: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(codexHookTrustCommand, forType: .string)

        guard openTerminal,
              let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return
        }
        NSWorkspace.shared.openApplication(at: terminalURL, configuration: .init())
    }

    func openAccessibilitySettings() {
        guard AccessibilityPermissionStatus.isAvailable else {
            accessibilityEnabled = false
            return
        }

        accessibilityEnabled = accessibilityStatusProvider(true)
        if !accessibilityEnabled {
            accessibilitySettingsOpener()
        }
    }

    func exportLogs() {
        guard !isExportingLogs else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "CCFLOW-Diagnostics-\(Self.archiveTimestamp()).zip"

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isExportingLogs = true
        logExportStatus = AppLocalization.string("settings.exporting_logs")

        Task {
            do {
                let result = try await DiagnosticsExporter.shared.exportArchive(to: destinationURL)
                await MainActor.run {
                    if result.warnings.isEmpty {
                        logExportStatus = AppLocalization.format(
                            "settings.exported_to",
                            result.archiveURL.lastPathComponent
                        )
                    } else {
                        logExportStatus = AppLocalization.format(
                            "settings.exported_with_warning_s",
                            result.warnings.count
                        )
                    }
                    isExportingLogs = false
                }
            } catch {
                await MainActor.run {
                    logExportStatus = AppLocalization.format(
                        "features.export_failed",
                        error.localizedDescription
                    )
                    isExportingLogs = false
                }
            }
        }
    }

    private static func archiveTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func refreshHookInstallationStates() {
        hookInstallationStates = ClientProfileRegistry.managedHookProfiles.reduce(into: [:]) { result, profile in
            result[profile.id] = HookInstaller.isInstalled(profile)
        }
    }

    private func resetCodexHookVerificationIfNeeded(for profile: ManagedHookClientProfile) {
        guard profile.brand == .codex else { return }
        resetCodexHookVerification()
    }

    private func resetCodexHookVerification() {
        hasReceivedCodexHookEvent = false
        defaults.removeObject(forKey: Self.codexHookVerifiedDigestDefaultsKey)
        objectWillChange.send()
    }

    private func markCodexHookEventReceived() {
        guard !hasReceivedCodexHookEvent
            || !Self.hasVerifiedCurrentCodexHooks(defaults: defaults, hooksURL: codexHooksURL) else {
            return
        }
        hasReceivedCodexHookEvent = true
        if let digest = Self.codexHooksDigest(at: codexHooksURL) {
            defaults.set(digest, forKey: Self.codexHookVerifiedDigestDefaultsKey)
        }
        objectWillChange.send()
    }

    static func hasVerifiedCurrentCodexHooks(defaults: UserDefaults, hooksURL: URL) -> Bool {
        guard let verifiedDigest = defaults.string(forKey: codexHookVerifiedDigestDefaultsKey),
              let currentDigest = codexHooksDigest(at: hooksURL) else {
            return false
        }
        return verifiedDigest == currentDigest
    }

    private static func codexHooksDigest(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private var codexHookTrustCommand: String {
        let cliURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.openai.codex")?
            .appendingPathComponent("Contents/Resources/codex")
        guard let cliURL,
              FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            return "codex"
        }

        let escapedPath = cliURL.path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escapedPath)'"
    }

    private func hookConfigurationDirectoryURL(for profile: ManagedHookClientProfile) -> URL? {
        let fileManager = FileManager.default

        for configurationURL in profile.configurationURLs {
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: configurationURL.path, isDirectory: &isDirectory) else {
                continue
            }

            return isDirectory.boolValue ? configurationURL : configurationURL.deletingLastPathComponent()
        }

        if let existingDirectory = profile.configurationURLs
            .map({ $0.deletingLastPathComponent() })
            .first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return existingDirectory
        }

        return profile.primaryConfigurationURL.deletingLastPathComponent()
    }
}

private enum SettingsPanelPresentation {
    case window
    case popover
}

private struct SoundSettingsContent: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var soundPacks = SoundPackCatalog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSectionCard(title: AppLocalization.runtimeString("settings.notifications")) {
                SettingsToggleLine(
                    title: AppLocalization.runtimeString("settings.enable_sounds"),
                    subtitle: AppLocalization.runtimeString("settings.play_different_sounds_for_different_session_phases"),
                    isOn: $settings.soundEnabled
                )
                SettingsLineDivider()

                SettingsInfoLine(
                    title: AppLocalization.runtimeString("settings.sound_mode"),
                    subtitle: AppLocalization.runtimeString("settings.system_sounds_are_quick_to_configure_while_sound")
                ) {
                    soundThemeModePicker
                }
                SettingsLineDivider()

                SettingsSliderLine(
                    title: AppLocalization.runtimeString("settings.volume"),
                    subtitle: AppLocalization.runtimeString("settings.adjust_the_volume_of_cc_flow_notification_sounds"),
                    value: $settings.soundVolume,
                    range: 0...1,
                    step: 0.05,
                    format: { "\(Int(($0 * 100).rounded()))%" },
                    showsTickMarks: true
                )
            }

            if settings.soundThemeMode == .builtIn {
                SoundEventSection(title: AppLocalization.runtimeString("settings.phase_sounds")) {
                    ForEach(Array(NotificationEvent.allCases.enumerated()), id: \.element.id) { index, event in
                        SoundEventSettingsLine(
                            event: event,
                            isEnabled: soundEnabledBinding(for: event),
                            selectedSound: soundBinding(for: event)
                        ) {
                            AppSettings.playSound(for: event)
                        }

                        if index < NotificationEvent.allCases.count - 1 {
                            SettingsLineDivider()
                        }
                    }
                }
            } else {
                SettingsSectionCard(title: AppLocalization.runtimeString("settings.sound_packs")) {
                    SoundPackSourceInfoLine {
                        soundPackPicker
                    }

                    SoundPackImportActionLine {
                        if soundPacks.importPack(), soundPacks.pack(for: settings.selectedSoundPackPath) == nil {
                            settings.selectedSoundPackPath = soundPacks.availablePacks.first?.rootURL.path ?? ""
                        }
                    } accessory: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.72))
                    }

                    if soundPacks.availablePacks.isEmpty {
                        SettingsValueLine(title: AppLocalization.runtimeString("settings.available_sound_packs"), value: AppLocalization.runtimeString("settings.none_found"))
                    } else {
                        SettingsValueLine(title: AppLocalization.runtimeString("settings.available_sound_packs"), value: "\(soundPacks.availablePacks.count)")
                    }
                }

                SoundEventSection(title: AppLocalization.runtimeString("settings.phase_mapping")) {
                    ForEach(Array(NotificationEvent.allCases.enumerated()), id: \.element.id) { index, event in
                        SoundPackEventLine(
                            event: event,
                            isEnabled: Binding(
                                get: { AppSettings.isSoundEnabled(for: event) },
                                set: { AppSettings.setSoundEnabled($0, for: event) }
                            )
                        ) {
                            AppSettings.playSound(for: event)
                        }

                        if index < NotificationEvent.allCases.count - 1 {
                            SettingsLineDivider()
                        }
                    }
                }
            }
        }
        .onAppear {
            ensureValidSelectedSoundPack()
        }
        .onChange(of: soundPacks.availablePacks) { _, _ in
            ensureValidSelectedSoundPack()
        }
        .onChange(of: settings.soundThemeMode) { _, _ in
            ensureValidSelectedSoundPack()
        }
    }

    private var soundThemeModePicker: some View {
        Picker("settings.sound_mode", selection: $settings.soundThemeMode) {
            ForEach(SoundThemeMode.allCases) { mode in
                Text(appLocalized: mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .settingsMenuPicker(width: 168)
    }

    private var soundPackPicker: some View {
        Picker("settings.sound_pack", selection: $settings.selectedSoundPackPath) {
            if soundPacks.availablePacks.isEmpty {
                Text(appLocalized: "settings.none_found").tag("")
            } else {
                ForEach(soundPacks.availablePacks) { pack in
                    Text(pack.displayName).tag(pack.rootURL.path)
                }
            }
        }
        .labelsHidden()
        .settingsMenuPicker(width: 204)
    }

    private func soundEnabledBinding(for event: NotificationEvent) -> Binding<Bool> {
        switch event {
        case .processingStarted:
            return $settings.processingStartSoundEnabled
        case .attentionRequired:
            return $settings.attentionRequiredSoundEnabled
        case .taskCompleted:
            return $settings.taskCompletedSoundEnabled
        case .taskError:
            return $settings.taskErrorSoundEnabled
        case .resourceLimit:
            return $settings.resourceLimitSoundEnabled
        }
    }

    private func soundBinding(for event: NotificationEvent) -> Binding<NotificationSound> {
        switch event {
        case .processingStarted:
            return $settings.processingStartSound
        case .attentionRequired:
            return $settings.attentionRequiredSound
        case .taskCompleted:
            return $settings.taskCompletedSound
        case .taskError:
            return $settings.taskErrorSound
        case .resourceLimit:
            return $settings.resourceLimitSound
        }
    }

    private func ensureValidSelectedSoundPack() {
        guard settings.soundThemeMode == .soundPack else { return }
        if soundPacks.availablePacks.isEmpty {
            settings.selectedSoundPackPath = ""
        } else if soundPacks.pack(for: settings.selectedSoundPackPath) == nil {
            settings.selectedSoundPackPath = soundPacks.availablePacks.first?.rootURL.path ?? ""
        }
    }
}

private struct SettingsCategoryLoadingView: View {
    let category: SettingsCategory

    var body: some View {
        SettingsSectionCard(title: category.title) {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white.opacity(0.82))

                Text(verbatim: loadingTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))

                Text(verbatim: loadingSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.54))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
    }

    private var loadingTitle: String {
        AppLocalization.format("settings.loading_settings", AppLocalization.string(category.title))
    }

    private var loadingSubtitle: String {
        switch category {
        case .display:
            return AppLocalization.string("settings.refreshing_display_and_usage_status")
        case .sound:
            return AppLocalization.string("settings.scanning_available_sound_packs")
        case .integration:
            return AppLocalization.string("settings.checking_hooks_ide_extensions_and_installed_clients")
        case .general, .shortcuts, .mascot, .leftContent, .about:
            return AppLocalization.string("settings.almost_ready")
        }
    }
}

private struct SettingsSidebarSection: Identifiable {
    let title: String?
    let categories: [SettingsCategory]

    var id: String { title ?? categories.map(\.rawValue).joined(separator: "-") }
}

struct SettingsGlassSurface: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

private struct SettingsWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragHandleView: NSView {
        // 在 isMovableByWindowBackground=false 时仍允许通过此 view 拖动窗口。
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private enum SettingsPanelMetrics {
    static let windowSize = AppSettings.defaultSettingsWindowSize
    static let windowMinSize = AppSettings.minimumSettingsWindowSize
    static let windowMaxSize = AppSettings.maximumSettingsWindowSize
    static let popoverSize = CGSize(width: 760, height: 620)
    static let windowSidebarWidth: CGFloat = 236
    static let popoverSidebarWidth: CGFloat = 212
    static let windowContentTopInset: CGFloat = 0
    static let popoverContentTopInset: CGFloat = 0
    static let outerPadding: CGFloat = 0
}

private struct SettingsPanelContentView: View {
    @ObservedObject private var shortcutManager = GlobalShortcutManager.shared
    let presentation: SettingsPanelPresentation
    var onClose: (() -> Void)? = nil
    var onMinimize: (() -> Void)? = nil

    @StateObject private var viewModel = SettingsPanelViewModel()
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var screenSelector = ScreenSelector.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var customAreaStore = CustomAreaStore.shared
    @ObservedObject private var leftFeatureStore = LeftFeatureStore.shared
    @ObservedObject private var generatedPanelScanner = GeneratedPanelScanner.shared
    @ObservedObject private var productivityPermissionCenter = ProductivityPermissionCenter.shared
    @ObservedObject private var githubService = GitHubService.shared
    // Spec: mineradio-bridge-compat-layer —— 三平台登录状态指示
    @ObservedObject private var mineradioCoordinator = MineradioBridgeCoordinator.shared
    @State private var selectedCategory: SettingsCategory? = .general
    @State private var pendingHookReinstallProfile: ManagedHookClientProfile?
    @State private var pendingHookOptionsRequest: HookInstallOptionsRequest?
    @State private var showingCodexHookTrustGuide = false
    @State private var showingUninstallAllHooksConfirmation = false
    @State private var showingCustomHookInstallSheet = false
    @State private var isAccessibilityPollingActive = false
    @State private var arePreviewAnimationsActive = false
    @State private var showingClearCacheConfirmation = false
    @State private var loadingCategory: SettingsCategory?
    @State private var categoryRefreshTask: Task<Void, Never>?
    // 左侧功能列表中点击「编辑」时弹出的自定义区域编辑表单
    @State private var editingArea: CustomArea?
    // 左侧功能列表中点击 URL 功能「编辑」时弹出的 URL 功能编辑表单
    @State private var editingWebURLFeature: LeftFeature?
    // 删除确认：待删除的自定义功能（customArea）
    @State private var pendingDeleteAreaID: String?
    // 删除确认：待删除的网站 URL 功能
    @State private var pendingDeleteWebURLFeature: LeftFeature?
    // 左侧功能列表中点击内置功能「编辑」时弹出的编辑表单
    @State private var editingBuiltinFeature: LeftFeature?
    // 左侧功能列表中点击 NewsNow「编辑实例 URL」时弹出的编辑表单
    @State private var editingNewsNowFeature: LeftFeature?
    @State private var newsNowBaseURLDraft: String = ""
    @State private var newsNowKeepsCrossDomainLoginInWebView = true
    // Spec: mineradio-bridge-compat-layer —— Mineradio URL 编辑表单
    @State private var editingMineradioFeature: LeftFeature?
    @State private var editingShortcutFeature: LeftFeature?
    @State private var mineradioPageURLDraft: String = ""
    @State private var mineradioKeepsCrossDomainLoginInWebView = true
    // Spec: mineradio-bridge-compat-layer —— Mineradio 平台登录 sheet
    @State private var presentingMineradioLogin: MusicPlatform?
    // 左侧功能列表中点击「添加自定义区域」时弹出的新建表单
    @State private var showingAddCustomAreaSheet = false
    // 新建表单：功能类型（本地目录 / 网站 URL）
    @State private var newFeatureType: NewFeatureType = .localDirectory
    @State private var newCustomAreaName = ""
    // 新建表单：URL 类型输入（仅 .webURL 类型使用）
    @State private var newFeatureURLString = ""
    // 新建表单：图标 —— 文字输入（用户输入文字 / SF Symbol 名）
    @State private var newCustomAreaIconText = ""
    // 新建表单：图标 —— 图片标识符（img:<filename>，选择图片后写入）
    @State private var newCustomAreaIconImage: String?
    // 新建表单：图标图片选择器与错误信息
    @State private var showingIconImagePicker = false
    @State private var iconImageError: String?
    // 新建表单：是否允许请求外部接口（仅本地目录类型显示）
    @State private var newCustomAreaAllowsNetwork = false
    // 新建表单：跨域登录是否留在 WebView（仅网站 URL 类型显示）
    @State private var newWebURLKeepsCrossDomainLoginInWebView = true
    @State private var newWebURLLoadsMineradioBridge = false
    // Spec: webURL 模式自动获取图标/名称的 debounce token + 上次自动填入的名称（用于判断是否覆盖用户输入）
    @State private var metadataFetchToken: UUID?
    @State private var autoFilledName: String?
    @State private var autoFilledIconImage: String?
    @State private var isFetchingMetadata = false
    @State private var githubPATDraft = ""
    @State private var productivitySecretMessage: String?
    @State private var generatedPanelPromptCopied = false
    @State private var showingGeneratedPanelDirectoryImporter = false
    @State private var generatedPanelActionMessage: String?
    @State private var generatedPanelLaunchFailure: String?
    @State private var generatedPanelLaunchToken = UUID()

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .top)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.top, contentTopInset)
            .padding(.horizontal, SettingsPanelMetrics.outerPadding)
            .padding(.bottom, SettingsPanelMetrics.outerPadding)
            .frame(
                minWidth: minimumWidth,
                idealWidth: idealWidth,
                maxWidth: maximumWidth,
                minHeight: minimumHeight,
                idealHeight: idealHeight,
                maxHeight: maximumHeight,
                alignment: .topLeading
            )
        }
        .background(panelBackgroundColor)
        .ignoresSafeArea()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .preferredColorScheme(.dark)
        .environment(\.mascotAnimationsEnabled, arePreviewAnimationsActive)
        .onAppear {
            viewModel.refreshInitialState()
            let isVisible = presentation == .popover || currentWindow?.isVisible == true
            isAccessibilityPollingActive = isVisible
            arePreviewAnimationsActive = isVisible

            scheduleCategoryRefresh(for: currentCategory, showLoading: false)
        }
        .onDisappear {
            isAccessibilityPollingActive = false
            arePreviewAnimationsActive = false
            categoryRefreshTask?.cancel()
            categoryRefreshTask = nil
            loadingCategory = nil
        }
        .task(id: isAccessibilityPollingActive) {
            guard isAccessibilityPollingActive else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                viewModel.refreshAccessibilityStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowVisibilityDidChange)) { notification in
            guard presentation == .window,
                  let isVisible = notification.userInfo?[SettingsWindowVisibilityNotification.isVisibleKey] as? Bool else {
                return
            }

            isAccessibilityPollingActive = isVisible
            arePreviewAnimationsActive = isVisible
            if isVisible {
                scheduleCategoryRefresh(for: currentCategory, showLoading: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowCategorySelectionRequested)) { notification in
            guard presentation == .window,
                  let rawCategory = notification.userInfo?[SettingsWindowCategorySelectionRequest.categoryKey] as? String,
                  let category = SettingsCategory(rawValue: rawCategory) else {
                return
            }

            selectSidebarCategory(category)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            scheduleCategoryRefresh(for: currentCategory, showLoading: false)
        }
        .onChange(of: settings.appLanguage) { _, _ in
            viewModel.refreshLocalizedState()
        }
        .alert(
            "settings.reinstall_hooks",
            isPresented: Binding(
                get: { pendingHookReinstallProfile != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingHookReinstallProfile = nil
                    }
                }
            ),
            presenting: pendingHookReinstallProfile
        ) { profile in
            Button("common.cancel", role: .cancel) {}
            Button("settings.reinstall") {
                viewModel.reinstallHooks(for: profile)
                pendingHookReinstallProfile = nil
            }
        } message: { profile in
            Text(verbatim: AppLocalization.format(profile.reinstallDescriptionFormat, profile.title))
        }
        .alert(
            AppLocalization.string("settings.trust_codex_hooks"),
            isPresented: $showingCodexHookTrustGuide
        ) {
            Button(AppLocalization.string("settings.open_terminal_copy")) {
                viewModel.prepareCodexHookTrustReview(openTerminal: true)
            }
            Button(AppLocalization.string("settings.copy_command")) {
                viewModel.prepareCodexHookTrustReview(openTerminal: false)
            }
            Button(AppLocalization.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(appLocalized: "settings.codex_requires_you_to_review_command_hooks_paste")
        }
        .alert(
            AppLocalization.string("settings.uninstall_all_hooks_configuration_files_2"),
            isPresented: $showingUninstallAllHooksConfirmation
        ) {
            Button(AppLocalization.string("common.cancel"), role: .cancel) {}
            Button(AppLocalization.string("settings.uninstall_all_hooks_configuration_files"), role: .destructive) {
                viewModel.uninstallAllHooks()
            }
        } message: {
            Text(appLocalized: "settings.this_removes_the_managed_hooks_configuration_files_island")
        }
        .sheet(isPresented: $showingCustomHookInstallSheet) {
            CustomHookInstallSheet(viewModel: viewModel) {
                showingCustomHookInstallSheet = false
            }
        }
        .sheet(item: $pendingHookOptionsRequest) { request in
            HookInstallOptionsSheet(
                profile: request.profile,
                mode: request.mode,
                initialSelection: viewModel.currentHookSelection(for: request.profile),
                onConfirm: { selection in
                    switch request.mode {
                    case .install:
                        viewModel.installHooks(for: request.profile, selection: selection)
                    case .edit:
                        viewModel.reinstallHooks(for: request.profile, selection: selection)
                    }
                    pendingHookOptionsRequest = nil
                },
                onDismiss: {
                    pendingHookOptionsRequest = nil
                }
            )
        }
        .sheet(item: $editingArea) { area in
            // 复用 EditableCustomAreaView 编辑表单（本地目录模式）
            EditableCustomAreaView(area: area) { updated in
                customAreaStore.updateArea(updated)
                editingArea = nil
            }
        }
        .sheet(item: $editingWebURLFeature) { feature in
            // 复用 EditableCustomAreaView 编辑表单（网站 URL 模式）
            EditableCustomAreaView(feature: feature) { updated in
                leftFeatureStore.updateWebURLFeature(
                    id: updated.id,
                    name: updated.customDisplayName,
                    url: {
                        if case .webURL(let url) = updated.kind { return url }
                        return nil
                    }(),
                    iconName: updated.customIconName,
                    keepsCrossDomainLoginInWebView: updated.keepsCrossDomainLoginInWebView,
                    loadsMineradioBridge: updated.loadsMineradioBridge,
                    variant: nil
                )
                editingWebURLFeature = nil
            }
        }
        .sheet(item: $editingBuiltinFeature) { feature in
            // 内置功能（music / shelf）编辑表单
            EditableCustomAreaView(builtinFeature: feature) { updated in
                leftFeatureStore.setCustomIconName(id: updated.id, name: updated.customIconName)
                leftFeatureStore.setCustomDisplayName(id: updated.id, name: updated.customDisplayName)
                if updated.kind.isURLBacked {
                    leftFeatureStore.setWebViewCapabilities(
                        id: updated.id,
                        keepsCrossDomainLoginInWebView: updated.keepsCrossDomainLoginInWebView
                    )
                }
                editingBuiltinFeature = nil
            }
        }
        .sheet(item: $editingShortcutFeature) { feature in
            FeatureShortcutEditor(feature: feature) { shortcut in
                leftFeatureStore.setGlobalShortcut(id: feature.id, shortcut: shortcut)
                editingShortcutFeature = nil
            } onCancel: {
                editingShortcutFeature = nil
            }
        }
        .sheet(item: $editingNewsNowFeature) { feature in
            // NewsNow 实例 URL 编辑表单
            VStack(alignment: .leading, spacing: 16) {
                Text("settings.edit_ai_hot_url")
                    .font(.system(size: 14, weight: .semibold))
                TextField("https://aihot.virxact.com/", text: $newsNowBaseURLDraft)
                    .textFieldStyle(.roundedBorder)
                Text("settings.ai_industry_news_aggregator_uses_the_public_ai")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Toggle(
                    "settings.keep_cross_site_sign_in_in_webview",
                    isOn: $newsNowKeepsCrossDomainLoginInWebView
                )
                .font(.caption)
                HStack {
                    Spacer()
                    Button("common.cancel") {
                        editingNewsNowFeature = nil
                    }
                    Button("common.save") {
                        let trimmed = newsNowBaseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if isValidNewsNowURL(trimmed) {
                            leftFeatureStore.updateNewsNowBaseURL(id: feature.id, baseURL: trimmed)
                            leftFeatureStore.setWebViewCapabilities(
                                id: feature.id,
                                keepsCrossDomainLoginInWebView: newsNowKeepsCrossDomainLoginInWebView
                            )
                            editingNewsNowFeature = nil
                        }
                    }
                    .disabled(!isValidNewsNowURL(newsNowBaseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            .padding(20)
            .frame(width: 420)
            .onAppear {
                if case .newsnow(let baseURL) = feature.kind {
                    newsNowBaseURLDraft = baseURL
                }
                newsNowKeepsCrossDomainLoginInWebView = feature.keepsCrossDomainLoginInWebView
            }
        }
        // Spec: mineradio-bridge-compat-layer —— Mineradio 页面 URL 编辑表单
        .sheet(item: $editingMineradioFeature) { feature in
            VStack(alignment: .leading, spacing: 16) {
                Text("settings.edit_mineradio_page_url")
                    .font(.system(size: 14, weight: .semibold))
                TextField("https://mineradio.art/", text: $mineradioPageURLDraft)
                    .textFieldStyle(.roundedBorder)
                Text("settings.mineradio_web_player_url_uses_the_official_instance")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Toggle(
                    "settings.keep_cross_site_sign_in_in_webview",
                    isOn: $mineradioKeepsCrossDomainLoginInWebView
                )
                .font(.caption)
                HStack {
                    Spacer()
                    Button("common.cancel") {
                        editingMineradioFeature = nil
                    }
                    Button("common.save") {
                        let trimmed = mineradioPageURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if isValidMineradioURL(trimmed) {
                            leftFeatureStore.updateMineradioPageURL(id: feature.id, pageURL: trimmed)
                            leftFeatureStore.setWebViewCapabilities(
                                id: feature.id,
                                keepsCrossDomainLoginInWebView: mineradioKeepsCrossDomainLoginInWebView
                            )
                            editingMineradioFeature = nil
                        }
                    }
                    .disabled(!isValidMineradioURL(mineradioPageURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            .padding(20)
            .frame(width: 420)
            .onAppear {
                if case .mineradio(let pageURL) = feature.kind {
                    mineradioPageURLDraft = pageURL
                }
                mineradioKeepsCrossDomainLoginInWebView = feature.keepsCrossDomainLoginInWebView
            }
        }
        // Spec: mineradio-bridge-compat-layer —— 平台登录 sheet
        .sheet(item: $presentingMineradioLogin) { platform in
            MineradioLoginView(
                platform: platform,
                isPresented: Binding(
                    get: { presentingMineradioLogin != nil },
                    set: { if !$0 { presentingMineradioLogin = nil } }
                )
            )
            .frame(minWidth: 480, minHeight: 600)
        }
        // Spec: mineradio-bridge-compat-layer —— 退出登录确认
        .confirmationDialog(
            "settings.sign_out",
            isPresented: Binding(
                get: { mineradioLogoutPlatform != nil },
                set: { if !$0 { mineradioLogoutPlatform = nil } }
            ),
            titleVisibility: .visible,
            presenting: mineradioLogoutPlatform
        ) { platform in
            Button("settings.sign_out_2", role: .destructive) {
                mineradioCoordinator.logout(platform)
                mineradioLogoutPlatform = nil
            }
            Button("common.cancel", role: .cancel) {
                mineradioLogoutPlatform = nil
            }
        } message: { platform in
            Text(AppLocalization.format("settings.signing_out_clears_cookies_mineradio_will_no_longer", AppLocalization.string(platform.displayName)))
        }
        .sheet(isPresented: $showingAddCustomAreaSheet) {
            addCustomAreaSheet
        }
    }

    private var minimumWidth: CGFloat {
        switch presentation {
        case .window:
            return SettingsPanelMetrics.windowMinSize.width
        case .popover:
            return SettingsPanelMetrics.popoverSize.width
        }
    }

    private var maximumWidth: CGFloat {
        switch presentation {
        case .window:
            return SettingsPanelMetrics.windowMaxSize.width
        case .popover:
            return SettingsPanelMetrics.popoverSize.width
        }
    }

    private var idealWidth: CGFloat {
        switch presentation {
        case .window:
            return SettingsPanelMetrics.windowSize.width
        case .popover:
            return SettingsPanelMetrics.popoverSize.width
        }
    }

    private var minimumHeight: CGFloat {
        switch presentation {
        case .window:
            return SettingsPanelMetrics.windowMinSize.height
        case .popover:
            return SettingsPanelMetrics.popoverSize.height
        }
    }

    private var maximumHeight: CGFloat {
        switch presentation {
        case .window:
            return SettingsPanelMetrics.windowMaxSize.height
        case .popover:
            return SettingsPanelMetrics.popoverSize.height
        }
    }

    private var idealHeight: CGFloat {
        switch presentation {
        case .window:
            return SettingsPanelMetrics.windowSize.height
        case .popover:
            return SettingsPanelMetrics.popoverSize.height
        }
    }

    private var sidebarWidth: CGFloat {
        switch presentation {
        case .window:
            return SettingsPanelMetrics.windowSidebarWidth
        case .popover:
            return SettingsPanelMetrics.popoverSidebarWidth
        }
    }

    private var panelBackgroundColor: Color {
        .clear
    }

    private var contentTopInset: CGFloat {
        switch presentation {
        case .window:
            return SettingsPanelMetrics.windowContentTopInset
        case .popover:
            return SettingsPanelMetrics.popoverContentTopInset
        }
    }

    private var sidebarSections: [SettingsSidebarSection] {
        [
            SettingsSidebarSection(
                title: nil,
                categories: SettingsCategory.visibleCategories
            )
        ]
    }

    private var sidebarBackground: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 24,
            bottomLeadingRadius: 24,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
            .fill(Color.white.opacity(0.055))
            .overlay {
                SettingsGlassSurface(material: .sidebar, blendingMode: .withinWindow)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 24,
                            bottomLeadingRadius: 24,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                    )
                    .opacity(0.94)
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.04),
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 24,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 120, height: 120)
                    .blur(radius: 36)
                    .offset(x: 28, y: -26)
            }
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    bottomLeadingRadius: 24,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.20), radius: 24, y: 14)
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            // 背景层：填充完整高度，确保与右侧等高
            sidebarBackground
                .frame(maxHeight: .infinity)

            // 内容层
            VStack(alignment: .leading, spacing: 18) {
                if presentation == .window {
                    sidebarWindowControls
                }

                ForEach(sidebarSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if let title = section.title {
                                    Text(appLocalized: title)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white.opacity(0.32))
                                        .padding(.horizontal, 12)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(section.categories) { category in
                                        Button {
                                            selectSidebarCategory(category)
                                        } label: {
                                            SidebarItemView(
                                                category: category,
                                                isSelected: selectedCategory == category,
                                                showsNoticeDot: category == .integration && viewModel.hasIntegrationNotice
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .focusable(false)
                                        .onHover { hovering in
                                            if hovering {
                                                NSCursor.pointingHand.push()
                                            } else {
                                                NSCursor.pointingHand.pop()
                                            }
                                        }
                                        .accessibilityIdentifier("settings.sidebar.\(category.rawValue)")
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
            .padding(8)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in
                    guard let window = currentWindow,
                          let event = NSApp.currentEvent else { return }
                    window.performDrag(with: event)
                }
        )
    }

    private var sidebarWindowControls: some View {
        HStack(spacing: 10) {
            WindowControlButton(
                color: Color(red: 1.0, green: 0.37, blue: 0.36),
                accessibilityLabel: AppLocalization.runtimeString("common.close")
            ) {
                if let onClose {
                    onClose()
                } else {
                    currentWindow?.performClose(nil)
                }
            }

            WindowControlButton(
                color: Color(red: 1.0, green: 0.74, blue: 0.18),
                accessibilityLabel: AppLocalization.runtimeString("settings.minimize")
            ) {
                if let onMinimize {
                    onMinimize()
                } else {
                    currentWindow?.miniaturize(nil)
                }
            }

            SettingsWindowDragHandle()
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if loadingCategory == currentCategory {
                    SettingsCategoryLoadingView(category: currentCategory)
                } else {
                    switch currentCategory {
                    case .general:
                        generalContent
                    case .shortcuts:
                        shortcutsContent
                    case .display:
                        displayContent
                    case .mascot:
                        mascotContent
                    case .sound:
                        soundContent
                    case .integration:
                        integrationContent
                    case .leftContent:
                        leftContent
                    case .about:
                        aboutContent
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(currentCategory)
        .accessibilityIdentifier("settings.detail.\(currentCategory.rawValue)")
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 26,
                topTrailingRadius: 26,
                style: .continuous
            )
                .fill(Color.white.opacity(0.035))
                .overlay {
                    SettingsGlassSurface(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 26,
                                topTrailingRadius: 26,
                                style: .continuous
                            )
                        )
                        .opacity(0.96)
                }
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.11),
                            Color.white.opacity(0.03),
                            Color.black.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 26,
                            topTrailingRadius: 26,
                            style: .continuous
                        )
                    )
                }
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 26,
                topTrailingRadius: 26,
                style: .continuous
            )
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 24, y: 14)
    }

    private var currentCategory: SettingsCategory {
        selectedCategory ?? .general
    }

    private var currentWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    private func selectSidebarCategory(_ category: SettingsCategory) {
        selectedCategory = category

        let categoryToRefresh = currentCategory
        scheduleCategoryRefresh(
            for: categoryToRefresh,
            showLoading: shouldShowLoading(for: categoryToRefresh)
        )
    }

    private func shouldShowLoading(for category: SettingsCategory) -> Bool {
        switch category {
        case .display, .sound, .integration:
            return true
        case .general, .shortcuts, .mascot, .about, .leftContent:
            return false
        }
    }

    private func scheduleCategoryRefresh(for category: SettingsCategory, showLoading: Bool) {
        categoryRefreshTask?.cancel()
        categoryRefreshTask = nil

        if showLoading {
            loadingCategory = category
        } else if loadingCategory == category {
            loadingCategory = nil
        }

        categoryRefreshTask = Task { @MainActor in
            if showLoading {
                try? await Task.sleep(nanoseconds: 80_000_000)
            } else {
                await Task.yield()
            }

            guard !Task.isCancelled else { return }
            viewModel.refresh(for: category)

            guard !Task.isCancelled else { return }
            if loadingCategory == category {
                loadingCategory = nil
            }
        }
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: AppLocalization.runtimeString("settings.system")) {
                SettingsInfoLine(
                    title: AppLocalization.runtimeString("settings.language"),
                    subtitle: AppLocalization.runtimeString("settings.follow_the_system_language_by_default_or_pin")
                ) {
                    appLanguagePicker
                }
                SettingsLineDivider()

                SettingsToggleLine(
                    title: AppLocalization.runtimeString("settings.launch_at_login"),
                    subtitle: AppLocalization.runtimeString("settings.show_island_automatically_after_macos_starts"),
                    isOn: Binding(
                        get: { viewModel.launchAtLogin },
                        set: { viewModel.setLaunchAtLogin($0) }
                    )
                )
                SettingsLineDivider()

                SettingsInfoLine(title: AppLocalization.runtimeString("settings.display_2"), subtitle: AppLocalization.runtimeString("settings.choose_which_display_island_appears_on")) {
                    screenPicker
                }
            }

            SettingsSectionCard(title: AppLocalization.runtimeString("settings.behavior")) {
                SettingsToggleLine(
                    title: AppLocalization.runtimeString("settings.expand_flow_island_on_hover"),
                    subtitle: AppLocalization.runtimeString("settings.when_off_click_flow_island_to_expand_it"),
                    isOn: $settings.openOnHover
                )

                if settings.openOnHover {
                    SettingsSliderLine(
                        title: AppLocalization.runtimeString("settings.hover_delay"),
                        subtitle: AppLocalization.runtimeString("settings.how_long_to_hover_before_flow_island_expands"),
                        value: Binding<Double>(
                            get: { Double(settings.hoverOpenDelayMs) },
                            set: { settings.hoverOpenDelayMs = Int($0) }
                        ),
                        range: 0...1000,
                        step: 50,
                        format: { "\(Int($0))ms" }
                    )
                }
                SettingsLineDivider()

                SettingsToggleLine(
                    title: AppLocalization.runtimeString("settings.auto_collapse_on_mouse_leave"),
                    subtitle: AppLocalization.runtimeString("settings.automatically_close_the_hover_preview_panel_when_the"),
                    isOn: $settings.autoCollapseOnLeave
                )
                SettingsLineDivider()

                SettingsToggleLine(
                    title: AppLocalization.runtimeString("settings.keep_flow_island_expanded"),
                    subtitle: AppLocalization.runtimeString("settings.expand_on_launch_and_keep_the_panel_open"),
                    isOn: $settings.keepIslandOpen
                )
            }

            SettingsSectionCard(title: AppLocalization.runtimeString("settings.app")) {
                SettingsActionLine(
                    title: AppLocalization.runtimeString("settings.quit_app"),
                    subtitle: AppLocalization.runtimeString("settings.quit_cc_flow_immediately")
                ) {
                    NSApplication.shared.terminate(nil)
                } accessory: {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                }
            }
        }
    }

    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: AppLocalization.runtimeString("settings.display_2")) {
                SettingsInfoLine(
                    title: AppLocalization.runtimeString("settings.current_display"),
                    subtitle: AppLocalization.runtimeString("settings.reposition_the_island_window_after_switching")
                ) {
                    screenPicker
                }
                SettingsLineDivider()

                if let selectedScreen = screenSelector.selectedScreen {
                    SettingsValueLine(
                        title: AppLocalization.runtimeString("settings.current_output"),
                        value: selectedScreen.localizedName
                    )
                }
            }

            SettingsSectionCard(title: AppLocalization.runtimeString("settings.flow_island_settings")) {
                SettingsSliderLine(
                    title: AppLocalization.runtimeString("settings.flow_island_height"),
                    subtitle: AppLocalization.runtimeString("settings.adjust_compact_flow_island_height_to_fit_lyrics"),
                    value: Binding<Double>(
                        get: { Double(settings.compactLeftHeight) },
                        set: { settings.compactLeftHeight = CGFloat($0) }
                    ),
                    range: 24...80,
                    step: 1,
                    format: { "\($0.formatted(.number.precision(.fractionLength(0)))) pt" }
                )
                SettingsLineDivider()

                SettingsSliderLine(
                    title: AppLocalization.runtimeString("settings.flow_island_width"),
                    subtitle: AppLocalization.runtimeString("settings.adjust_compact_flow_island_width_narrow_widths_show"),
                    value: $settings.notchModuleWidth,
                    range: AppSettings.notchModuleWidthRange,
                    step: 10,
                    format: { "\($0.formatted(.number.precision(.fractionLength(0)))) pt" }
                )
                SettingsLineDivider()

                SettingsSliderLine(
                    title: AppLocalization.runtimeString("settings.default_expanded_width"),
                    subtitle: AppLocalization.runtimeString("settings.sets_one_width_for_active_sessions_notifications_and"),
                    value: $settings.expandedPanelWidth,
                    range: AppSettings.expandedPanelWidthRange,
                    step: 10,
                    format: { "\($0.formatted(.number.precision(.fractionLength(0)))) pt" }
                )
            }

        }
    }

    private func replayNotchDetachmentHint() {
        AppSettings.notchDetachmentHintPending = true
        AppSettings.floatingPetSettingsHintPending = true
        onClose?()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .ccFlowPresentNotchDetachmentHint, object: nil)
        }
    }

    private func replayFirstRunOnboardingDemo() {
        SettingsWindowController.shared.dismiss()
        AppSettings.notchDetachmentHintPending = false
        AppSettings.floatingPetSettingsHintPending = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            PresentationModeWelcomeWindowController.shared.present { selectedMode in
                AppSettings.surfaceMode = selectedMode
                AppSettings.presentationModeOnboardingPending = false
                AppSettings.notchDetachmentHintPending = false
                AppSettings.floatingPetSettingsHintPending = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    HookWalkthroughDemoRunner.shared.start()
                }
            }
        }
    }

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: AppLocalization.runtimeString("settings.global_shortcuts")) {
                ShortcutSettingsLine(
                    action: .openActiveSession,
                    shortcut: shortcutBinding(for: .openActiveSession)
                )
                SettingsLineDivider()
                ShortcutSettingsLine(
                    action: .openLeftFeature,
                    shortcut: shortcutBinding(for: .openLeftFeature)
                )
                SettingsLineDivider()
                ShortcutSettingsLine(
                    action: .openSessionList,
                    shortcut: shortcutBinding(for: .openSessionList)
                )
                SettingsLineDivider()
                ShortcutSettingsLine(
                    action: .giflowSelectionCapture,
                    shortcut: shortcutBinding(for: .giflowSelectionCapture)
                )
                SettingsLineDivider()
                ShortcutSettingsLine(
                    action: .giflowFullScreenCapture,
                    shortcut: shortcutBinding(for: .giflowFullScreenCapture)
                )
                SettingsLineDivider()
                ShortcutSettingsLine(
                    action: .giflowOpenRecordings,
                    shortcut: shortcutBinding(for: .giflowOpenRecordings)
                )
                SettingsLineDivider()
                ShortcutSettingsLine(action: .translationSelection, shortcut: shortcutBinding(for: .translationSelection))
                SettingsLineDivider()
                ShortcutSettingsLine(action: .translationScreenshot, shortcut: shortcutBinding(for: .translationScreenshot))
                SettingsLineDivider()
                ShortcutSettingsLine(action: .translationInput, shortcut: shortcutBinding(for: .translationInput))
            }

            SettingsSectionCard(title: AppLocalization.runtimeString("settings.info")) {
                SettingsInfoLine(
                    title: AppLocalization.runtimeString("settings.default_bindings"),
                    subtitle: AppLocalization.runtimeString("settings.defaults_option_j_opens_the_active_session_option")
                ) {
                    EmptyView()
                }
                SettingsLineDivider()

                SettingsInfoLine(
                    title: AppLocalization.runtimeString("settings.recording"),
                    subtitle: AppLocalization.runtimeString("settings.while_recording_press_the_new_key_combination_directly")
                ) {
                    EmptyView()
                }
                SettingsLineDivider()

                SettingsInfoLine(
                    title: AppLocalization.runtimeString("settings.session_list_keyboard_controls"),
                    subtitle: AppLocalization.runtimeString("settings.once_the_session_list_is_open_use_up")
                ) {
                    EmptyView()
                }
            }
        }
    }

    private var mascotContent: some View {
        MascotSettingsView()
    }

    private var soundContent: some View {
        SoundSettingsContent()
    }

    private var integrationContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: AppLocalization.runtimeString("settings.system_permissions")) {
                SettingsStatusLine(
                    title: AppLocalization.runtimeString("settings.accessibility"),
                    subtitle: viewModel.accessibilityEnabled ? AppLocalization.runtimeString("settings.authorized_for_window_focusing_and_foreground_detection") : AppLocalization.runtimeString("settings.not_authorized_some_auto_focus_features_are_unavailable"),
                    status: viewModel.accessibilityEnabled ? AppLocalization.runtimeString("settings.enabled") : AppLocalization.runtimeString("settings.pending"),
                    statusColor: viewModel.accessibilityEnabled ? TerminalColors.green : TerminalColors.amber
                ) {
                    if !viewModel.accessibilityEnabled {
                        viewModel.openAccessibilitySettings()
                    }
                }
            }

            SettingsSectionCard(title: AppLocalization.runtimeString("settings.approvals_questions")) {
                SettingsInfoLine(
                    title: AppLocalization.runtimeString("session.tool_approval"),
                    subtitle: settings.toolApprovalMode.subtitle
                ) {
                    Picker("", selection: $settings.toolApprovalMode) {
                        ForEach(ToolApprovalMode.allCases) { mode in
                            Text(appLocalized: mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .settingsMenuPicker(width: 120)
                }

                SettingsLineDivider()

                CompletionPromptRegexRulesSettingsView(settings: settings)
            }

            let hookProfiles = viewModel.visibleHookProfiles
            if !hookProfiles.isEmpty {
                SettingsSectionCard(title: AppLocalization.runtimeString("settings.hooks")) {
                    let profiles = hookProfiles
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        if index == 0 || profiles[index - 1].brand != profile.brand {
                            Text(hookGroupTitle(for: profile.brand))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.55))
                                .padding(.top, index == 0 ? 2 : 10)
                                .padding(.bottom, 3)
                        }

                        HookManagementLine(
                            profile: profile,
                            hookStatus: viewModel.hookPresentationStatus(for: profile),
                            isReinstalling: viewModel.isReinstallingHooks(for: profile),
                            reinstallFeedback: viewModel.hookReinstallFeedback(for: profile),
                            noticeMessage: viewModel.hookNotice(for: profile),
                            supportsEventSelection: profile.supportsEventSelection,
                            isInstallDisabled: !profile.supportsHookIntegration,
                            installAction: {
                                if profile.supportsEventSelection {
                                    pendingHookOptionsRequest = HookInstallOptionsRequest(
                                        profile: profile,
                                        mode: .install
                                    )
                                } else {
                                    viewModel.installHooks(for: profile)
                                }
                            },
                            configureAction: {
                                pendingHookOptionsRequest = HookInstallOptionsRequest(
                                    profile: profile,
                                    mode: .edit
                                )
                            },
                            openConfigurationDirectoryAction: {
                                viewModel.openHookConfigurationDirectory(for: profile)
                            },
                            trustGuideAction: {
                                showingCodexHookTrustGuide = true
                            },
                            reinstallAction: { pendingHookReinstallProfile = profile },
                            uninstallAction: { viewModel.uninstallHooks(for: profile) }
                        )

                        if index < profiles.count - 1
                            || !viewModel.customHookInstallations.isEmpty {
                            SettingsLineDivider()
                        }
                    }

                    let customInstallations = viewModel.customHookInstallations
                    ForEach(Array(customInstallations.enumerated()), id: \.element.id) { index, installation in
                        CustomHookInstallationLine(
                            installation: installation,
                            uninstallAction: { viewModel.uninstallCustomHook(id: installation.id) }
                        )

                        if index < customInstallations.count - 1 {
                            SettingsLineDivider()
                        }
                    }

                    SettingsLineDivider()

                    HStack {
                        Spacer()
                        Button(action: { showingCustomHookInstallSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(appLocalized: "settings.add_custom_configuration")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }

            SettingsSectionCard(title: AppLocalization.runtimeString("settings.hook_debug_logs")) {
                SettingsToggleLine(
                    title: AppLocalization.runtimeString("settings.record_hook_debug_logs"),
                    subtitle: AppLocalization.runtimeString("settings.when_off_the_bridge_stops_appending_hook_debug"),
                    isOn: $settings.hookDebugLoggingEnabled
                )
                SettingsLineDivider()

                SettingsSliderLine(
                    title: AppLocalization.runtimeString("settings.log_retention"),
                    subtitle: AppLocalization.runtimeString("settings.hook_debug_logs_older_than_this_are_deleted"),
                    value: Binding(
                        get: { Double(settings.hookDebugLogRetentionDays) },
                        set: { settings.hookDebugLogRetentionDays = Int($0.rounded()) }
                    ),
                    range: Double(BridgeRuntimeConfigSnapshot.minimumDebugLogRetentionDays)...Double(BridgeRuntimeConfigSnapshot.maximumDebugLogRetentionDays),
                    step: 1,
                    format: { AppLocalization.format("settings.days", String(describing: Int($0.rounded()))) }
                )
                .disabled(!settings.hookDebugLoggingEnabled)
                .opacity(settings.hookDebugLoggingEnabled ? 1 : 0.45)
                SettingsLineDivider()

                SettingsSliderLine(
                    title: AppLocalization.runtimeString("settings.maximum_log_usage"),
                    subtitle: AppLocalization.runtimeString("settings.when_library_logs_cc_flow_exceeds_this_size"),
                    value: Binding(
                        get: { Double(settings.hookDebugLogMaxDirectoryMegabytes) },
                        set: { settings.hookDebugLogMaxDirectoryMegabytes = Int($0.rounded()) }
                    ),
                    range: Double(BridgeRuntimeConfigSnapshot.minimumDebugLogMaxDirectoryMegabytes)...Double(BridgeRuntimeConfigSnapshot.maximumDebugLogMaxDirectoryMegabytes),
                    step: 16,
                    format: { "\(Int($0.rounded())) MB" }
                )
                .disabled(!settings.hookDebugLoggingEnabled)
                .opacity(settings.hookDebugLoggingEnabled ? 1 : 0.45)
            }

            Button(action: { showingUninstallAllHooksConfirmation = true }) {
                HStack(spacing: 7) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                    Text(appLocalized: "settings.uninstall_all_hooks_configuration_files")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(TerminalColors.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(appLocalized: "settings.uninstall_all_hooks_configuration_files"))
        }
    }

    private func hookGroupTitle(for brand: SessionClientBrand) -> String {
        switch brand {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .trae: return "TRAE"
        case .antigravity: return "Antigravity"
        case .neutral: return AppLocalization.runtimeString("settings.other")
        }
    }

    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: AppLocalization.runtimeString("settings.app_info")) {
                SettingsValueLine(title: AppLocalization.runtimeString("settings.version"), value: appVersion)
                SettingsLineDivider()
                SettingsValueLine(title: AppLocalization.runtimeString("settings.installed_2"), value: versionMetadata)
            }

            SettingsSectionCard(title: AppLocalization.runtimeString("settings.updates")) {
                SettingsToggleLine(
                    title: AppLocalization.runtimeString("settings.automatic_update_checks"),
                    subtitle: AppLocalization.runtimeString("settings.automatically_check_download_and_install_updates_on_launch"),
                    isOn: $settings.automaticUpdateChecksEnabled
                )
                SettingsLineDivider()

                SettingsActionLine(
                    title: updateTitle,
                    subtitle: updateSubtitle
                ) {
                    handleUpdateAction()
                } accessory: {
                    updateAccessory
                }

                if updateManager.canInstallPendingUpdateNow {
                    SettingsLineDivider()

                    SettingsActionLine(
                        title: AppLocalization.runtimeString("settings.restart_and_install_now"),
                        subtitle: AppLocalization.runtimeString("settings.quit_cc_flow_and_install_the_downloaded_update")
                    ) {
                        updateManager.installAndRelaunch()
                    } accessory: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(TerminalColors.green)
                    }
                }
            }

            SettingsSectionCard(title: AppLocalization.runtimeString("settings.links")) {
                SettingsActionLine(title: "GitHub", subtitle: AppLocalization.runtimeString("settings.visit_the_project_home_page_or_report_an")) {
                    if let url = URL(string: "https://github.com/kilig947-alt/cc-flow") {
                        NSWorkspace.shared.open(url)
                    }
                } accessory: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }

                SettingsLineDivider()

                SettingsActionLine(
                    title: AppLocalization.runtimeString("settings.export_diagnostics"),
                    subtitle: viewModel.logExportStatus
                ) {
                    viewModel.exportLogs()
                } accessory: {
                    if viewModel.isExportingLogs {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.8))
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            SettingsSectionCard(title: AppLocalization.runtimeString("settings.reset")) {
                SettingsActionLine(
                    title: AppLocalization.runtimeString("settings.clear_all_data"),
                    subtitle: AppLocalization.runtimeString("settings.uninstall_hooks_and_clear_preferences_and_local_data")
                ) {
                    showingClearCacheConfirmation = true
                } accessory: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TerminalColors.red)
                }
            }
        }
        .confirmationDialog(
            "settings.clear_all_data_2",
            isPresented: $showingClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("settings.clear_and_quit", role: .destructive) {
                AppCacheResetManager.performFullReset()
                AppCacheResetManager.terminateApp()
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("settings.this_will_uninstall_all_hooks_and_delete_preferences")
        }
    }

    /// 左侧内容设置：
    /// 1. Flow Island显示卡片 —— 选择 Flow Island 紧凑态展示的功能
    /// 2. 功能列表卡片 —— 管理所有左侧功能（启用/禁用、拖拽排序、编辑/删除自定义 HTML），
    ///    并直接提供「添加自定义区域」入口
    private var leftContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            flowIslandDisplayCard
            featureListCard
            generatedPanelDesignCard
            productivityCredentialsCard
            productivityPermissionsCard
        }
        .onAppear {
            productivityPermissionCenter.refresh()
        }
    }

    private var productivityPermissionsCard: some View {
        SettingsSectionCard(title: AppLocalization.runtimeString("settings.permissions_and_data_sources")) {
            VStack(spacing: 8) {
                ForEach(productivityPermissionCenter.items) { item in
                    HStack {
                        Image(systemName: item.isReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(item.isReady ? .green : .yellow)
                        Text(appLocalized: item.name)
                        Spacer()
                        Text(appLocalized: item.status).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
                HStack {
                    Spacer()
                    Button("settings.refresh_status") { productivityPermissionCenter.refresh() }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var productivityCredentialsCard: some View {
        SettingsSectionCard(title: AppLocalization.runtimeString("settings.productivity_connections")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("settings.github_uses_local_gh_authentication_first_a_personal")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Label(LocalizedStringKey(githubService.status), systemImage: githubService.profile == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(githubService.profile == nil ? Color.secondary : Color.green)
                HStack {
                    SecureField("GitHub Personal Access Token", text: $githubPATDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("common.save") {
                        do {
                            try ProductivitySecretsStore.shared.set(githubPATDraft, for: .githubPAT)
                            githubPATDraft = ""
                            productivitySecretMessage = AppLocalization.runtimeString("settings.saved_to_keychain")
                            GitHubService.shared.refresh()
                        } catch {
                            productivitySecretMessage = error.localizedDescription
                        }
                    }
                    .disabled(githubPATDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("common.delete", role: .destructive) {
                        do {
                            try ProductivitySecretsStore.shared.delete(.githubPAT)
                            productivitySecretMessage = AppLocalization.runtimeString("settings.fallback_token_deleted")
                        } catch {
                            productivitySecretMessage = error.localizedDescription
                        }
                    }
                }
                if let productivitySecretMessage {
                    Text(appLocalized: productivitySecretMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Left Content: TRAE Work Design Generator

    private var generatedPanelDesignCard: some View {
        SettingsSectionCard(title: AppLocalization.runtimeString("settings.generate_feature_with_design")) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("settings.choose_a_design_app_to_copy_the_prompt_then")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                HStack(spacing: 8) {
                    generatedPanelDesignLaunchButton(.codex)
                    generatedPanelDesignLaunchButton(.claude)
                    generatedPanelDesignLaunchButton(.traeWork)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                if let generatedPanelLaunchFailure {
                    Label(generatedPanelLaunchFailure, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Divider()
                    .opacity(0.35)
                    .padding(.top, 12)

                HStack(spacing: 8) {
                    Text("settings.feature_generation_prompt")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        copyGeneratedPanelPrompt()
                        generatedPanelPromptCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            generatedPanelPromptCopied = false
                        }
                    } label: {
                        Label(
                            generatedPanelPromptCopied ? AppLocalization.runtimeString("settings.copied") : AppLocalization.runtimeString("settings.copy_prompt"),
                            systemImage: generatedPanelPromptCopied ? "checkmark" : "doc.on.doc"
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(generatedPanelPromptCopied ? Color.green : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(generatedPanelPromptCopied ? Color.green.opacity(0.1) : Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                ScrollView {
                    Text(GeneratedPanelPrompt.text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 210)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
        }
        .fileImporter(
            isPresented: $showingGeneratedPanelDirectoryImporter,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                let didStartAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess { url.stopAccessingSecurityScopedResource() }
                }
                generatedPanelActionMessage = nil
                _ = generatedPanelScanner.importSelectedDirectory(url)
            case .failure(let error):
                generatedPanelActionMessage = AppLocalization.format("settings.failed_to_select_directory", String(describing: error.localizedDescription))
            }
        }
        .onReceive(generatedPanelScanner.$lastResult.dropFirst()) { result in
            if !result.importedNames.isEmpty {
                generatedPanelActionMessage = nil
            }
        }
    }

    private var generatedPanelStatusText: (text: String, symbol: String, isError: Bool)? {
        if generatedPanelScanner.isScanning {
            return nil
        }
        if let generatedPanelActionMessage {
            return (generatedPanelActionMessage, "exclamationmark.triangle.fill", true)
        }
        let result = generatedPanelScanner.lastResult
        if !result.importedNames.isEmpty {
            return (AppLocalization.format("settings.imported", result.importedNames.joined(separator: ", ")), "checkmark.circle.fill", false)
        }
        if let issue = result.issues.first {
            return ("\(issue.directoryName)：\(issue.message)", "exclamationmark.triangle.fill", true)
        }
        return (AppLocalization.runtimeString("settings.no_new_panels_found"), "checkmark.circle", false)
    }

    // MARK: - Left Content: Feature List

    /// 功能列表卡片：列出所有左侧功能（按 sortOrder 升序），
    /// 支持启用/禁用、拖拽排序；自定义 HTML 功能可编辑/删除，内置功能标记为「内置」。
    /// 标题右侧提供「添加自定义功能」入口，与功能管理合并在一处。
    private var featureListCard: some View {
        SettingsSectionCard(
            title: AppLocalization.runtimeString("settings.features"),
            titleLeadingAccessory: { generatedPanelRecoveryControls },
            titleAccessory: { addCustomAreaTitleButton }
        ) {
            List {
                ForEach(leftFeatureStore.features.sorted(by: { $0.sortOrder < $1.sortOrder })) { feature in
                    featureRow(feature)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                        .listRowSeparator(.hidden)
                }
                .onMove { indices, destination in
                    leftFeatureStore.moveFeature(from: indices, to: destination)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(height: featureListHeight)
        }
        .confirmationDialog(
            "settings.delete_this_custom_feature",
            isPresented: Binding(
                get: { pendingDeleteAreaID != nil },
                set: { if !$0 { pendingDeleteAreaID = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteAreaID
        ) { areaID in
            Button("common.delete", role: .destructive) {
                customAreaStore.removeArea(id: areaID)
                pendingDeleteAreaID = nil
            }
            Button("common.cancel", role: .cancel) {
                pendingDeleteAreaID = nil
            }
        } message: { _ in
            Text("settings.the_feature_will_be_removed_from_the_list")
        }
        .confirmationDialog(
            "settings.delete_this_website_feature",
            isPresented: Binding(
                get: { pendingDeleteWebURLFeature != nil },
                set: { if !$0 { pendingDeleteWebURLFeature = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteWebURLFeature
        ) { feature in
            Button("common.delete", role: .destructive) {
                leftFeatureStore.removeWebURLFeature(id: feature.id)
                pendingDeleteWebURLFeature = nil
            }
            Button("common.cancel", role: .cancel) {
                pendingDeleteWebURLFeature = nil
            }
        } message: { _ in
            Text("settings.the_url_feature_will_be_removed_from_the")
        }
    }

    private var featureListHeight: CGFloat {
        let rowHeight: CGFloat = 44
        let verticalListInsets: CGFloat = 16
        let minimumHeight: CGFloat = 56
        let maximumHeight: CGFloat = 330
        let contentHeight = CGFloat(leftFeatureStore.features.count) * rowHeight + verticalListInsets
        return min(max(contentHeight, minimumHeight), maximumHeight)
    }

    private var generatedPanelRecoveryControls: some View {
        ViewThatFits(in: .horizontal) {
            generatedPanelRecoveryControlRow(usesCompactButtons: false)
            generatedPanelRecoveryControlRow(usesCompactButtons: true)
        }
    }

    private func generatedPanelRecoveryControlRow(usesCompactButtons: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                generatedPanelActionMessage = nil
                generatedPanelScanner.scanNow()
            } label: {
                if usesCompactButtons {
                    Image(systemName: "arrow.clockwise")
                } else {
                    Label(
                        generatedPanelScanner.isScanning ? AppLocalization.runtimeString("settings.scanning") : AppLocalization.runtimeString("settings.scan_generated_features"),
                        systemImage: "arrow.clockwise"
                    )
                }
            }
            .disabled(generatedPanelScanner.isScanning)
            .help(Text(appLocalized: generatedPanelScanner.isScanning ? AppLocalization.runtimeString("settings.scanning_generated_features") : AppLocalization.runtimeString("settings.scan_generated_features")))
            .accessibilityLabel(Text(appLocalized: generatedPanelScanner.isScanning ? AppLocalization.runtimeString("settings.scanning_generated_features") : AppLocalization.runtimeString("settings.scan_generated_features")))

            Button {
                showingGeneratedPanelDirectoryImporter = true
            } label: {
                if usesCompactButtons {
                    Image(systemName: "folder.badge.plus")
                } else {
                    Label("settings.import_from_directory", systemImage: "folder.badge.plus")
                }
            }
            .help("settings.import_from_directory")
            .accessibilityLabel("settings.import_from_directory")

            if let status = generatedPanelStatusText {
                Label(LocalizedStringKey(status.text), systemImage: status.symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(status.isError ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: usesCompactButtons ? 120 : 160, alignment: .leading)
                    .help(status.text)
                    .accessibilityLabel(status.text)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func generatedPanelDesignLaunchButton(_ destination: PanelDesignDestination) -> some View {
        Button {
            copyGeneratedPanelPrompt()
            generatedPanelLaunchFailure = nil
            let launchToken = UUID()
            generatedPanelLaunchToken = launchToken
            PanelDesignAppLauncher.activate(destination) { succeeded in
                guard generatedPanelLaunchToken == launchToken else { return }
                generatedPanelLaunchFailure = succeeded
                    ? nil
                    : AppLocalization.format("settings.prompt_copied_but_could_not_open_make_sure", String(describing: destination.applicationDisplayName))
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 11))
                Text(appLocalized: destination.buttonTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("settings.copy_feature_prompt_and_open_app")
    }

    private func copyGeneratedPanelPrompt() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(GeneratedPanelPrompt.text, forType: .string)
    }

    /// 功能列表标题右侧的「添加自定义功能」按钮。
    private var addCustomAreaTitleButton: some View {
        Button {
            showingAddCustomAreaSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                Text("settings.add_custom_feature")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// 单个功能行：图标 + 名称（可点击进入编辑）+ 右侧操作组 + 启用开关。
    /// - `.customArea`: 打开目录（Finder）/ 编辑 / 删除
    /// - `.webURL`: 删除
    /// - `.music`: 内置功能仅显示「内置」标签
    @ViewBuilder
    private func featureRow(_ feature: LeftFeature) -> some View {
        HStack(spacing: 12) {
            // 图标 + 名称可点击进入编辑（内置功能点击无效）
            Button {
                editFeature(feature)
            } label: {
                HStack(spacing: 8) {
                    FeatureIconView(feature: feature, size: 14)
                        .frame(width: 20)
                    Text(feature.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            // 右侧操作组：按 kind 分发
            switch feature.kind {
            case .translation:
                Button("settings.translation_services") { TranslationStore.shared.openServiceSettings() }
                    .buttonStyle(.borderless)
                    .disabled(!feature.isEnabled)
                    .help(Text(appLocalized: feature.isEnabled ? AppLocalization.runtimeString("settings.configure_translation_services_in_flow_island") : AppLocalization.runtimeString("settings.enable_tflow_translation_first")))
                Button("settings.edit") { editingBuiltinFeature = feature }.buttonStyle(.borderless)
            case .usage, .systemMonitor, .calendar, .github, .giflow:
                Button("settings.edit") { editingBuiltinFeature = feature }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
            case .customArea(let areaID):
                if let area = customAreaStore.areas.first(where: { $0.id == areaID }) {
                    // 去 TRAE CN 修改（以该目录为工作区打开 IDE）
                    Button {
                        TraeSessionLauncher.openWorkspace(.traeCN, directoryURL: area.directoryURL)
                    } label: {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help("settings.open_in_trae_cn")

                    // 打开目录（Finder）
                    Button {
                        NSWorkspace.shared.open(area.directoryURL)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("settings.show_in_finder")

                    // 编辑
                    Button("settings.edit") { editCustomArea(areaID: areaID) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                }
                // 删除（弹出确认对话框）
                Button("common.delete") { pendingDeleteAreaID = areaID }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .foregroundColor(.red)

            case .webURL:
                // U 图标按钮：点击在系统默认浏览器中打开 URL
                Button {
                    if case .webURL(let urlString) = feature.kind,
                       let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("U")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.borderless)
                .help("settings.open_in_browser")

                // 编辑
                Button("settings.edit") { editingWebURLFeature = feature }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))

                // 删除（弹出确认对话框）
                Button("common.delete") { pendingDeleteWebURLFeature = feature }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .foregroundColor(.red)

            case .music:
                // 内置功能也支持编辑（图标 / 名称 / 展开尺寸 / 固定）
                Button("settings.edit") { editingBuiltinFeature = feature }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))

            case .newsnow:
                // 编辑实例 URL
                Button {
                    editingNewsNowFeature = feature
                } label: {
                    Image(systemName: "globe")
                }
                .buttonStyle(.borderless)
                .help("settings.edit_instance_url")

                // 编辑（图标 / 名称 / 展开尺寸 / 固定）
                Button("settings.edit") { editingBuiltinFeature = feature }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))

            case .mineradio:
                // Spec: mineradio-bridge-compat-layer —— 三平台登录状态指示
                ForEach(MusicPlatform.allCases, id: \.self) { platform in
                    mineradioLoginStatusButton(for: platform)
                }
                // 编辑页面 URL
                Button {
                    editingMineradioFeature = feature
                } label: {
                    Image(systemName: "globe")
                }
                .buttonStyle(.borderless)
                .help("settings.edit_page_url")
                // 编辑（图标 / 名称 / 展开尺寸 / 固定）
                Button("settings.edit") { editingBuiltinFeature = feature }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
            }

            Button {
                editingShortcutFeature = feature
            } label: {
                Image(systemName: "keyboard")
                    .foregroundColor(shortcutManager.registrationError(forFeatureID: feature.id) == nil ? nil : .red)
            }
            .buttonStyle(.borderless)
            .help(Text(appLocalized: shortcutManager.registrationError(forFeatureID: feature.id) ?? AppLocalization.runtimeString("settings.set_global_shortcut")))
            .accessibilityLabel(Text(appLocalized: "settings.set_global_shortcut"))

            // 启用开关（所有功能都有）
            Toggle("", isOn: Binding(
                get: { feature.isEnabled },
                set: { leftFeatureStore.setFeatureEnabled(id: feature.id, isEnabled: $0) }
            ))
            .labelsHidden()
            .settingsCompactSwitch()
        }
        .padding(.vertical, 4)
    }

    /// 点击功能行图标/名称进入编辑：
    /// - `.customArea`: 弹出本地目录编辑表单
    /// - `.webURL`: 弹出网站 URL 编辑表单
    /// - `.music`: 弹出内置功能编辑表单
    private func editFeature(_ feature: LeftFeature) {
        switch feature.kind {
        case .usage, .systemMonitor, .calendar, .github, .giflow, .translation:
            editingBuiltinFeature = feature
        case .customArea(let areaID):
            editCustomArea(areaID: areaID)
        case .webURL:
            editingWebURLFeature = feature
        case .music, .newsnow:
            editingBuiltinFeature = feature
        case .mineradio:
            editingMineradioFeature = feature
        }
    }

    /// 点击功能行「编辑」按钮：根据 areaID 查找对应 CustomArea 并弹出编辑表单。
    private func editCustomArea(areaID: String) {
        editingArea = customAreaStore.areas.first { $0.id == areaID }
    }

    /// 校验 NewsNow 实例 URL：必须 http/https scheme 且可构造 URL。
    private func isValidNewsNowURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return true
    }

    /// Spec: mineradio-bridge-compat-layer —— 校验 Mineradio 页面 URL（与 NewsNow 同逻辑）
    private func isValidMineradioURL(_ string: String) -> Bool {
        isValidNewsNowURL(string)
    }

    /// Spec: mineradio-bridge-compat-layer —— 单个平台登录状态指示按钮。
    /// 未登录 / `.unknown`：灰色图标，点击弹登录 sheet；
    /// 已登录：绿色图标 + 昵称，点击弹退出确认。
    @ViewBuilder
    private func mineradioLoginStatusButton(for platform: MusicPlatform) -> some View {
        let state = mineradioCoordinator.loginStates[platform] ?? .unknown
        Button {
            switch state {
            case .loggedIn:
                mineradioLogoutPlatform = platform
            default:
                presentingMineradioLogin = platform
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: platform.systemImageName)
                    .font(.system(size: 11))
                switch state {
                case .unknown:
                    Text(appLocalized: platform.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                case .loggedOut:
                    Text(appLocalized: platform.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                case .loggedIn(let nickname):
                    Text(nickname.isEmpty ? platform.displayName : nickname)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(state.isLoggedIn ? 0.08 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .help(Text(appLocalized: state.isLoggedIn ? AppLocalization.format("settings.click_to_sign_out_of", AppLocalization.string(platform.displayName)) : AppLocalization.format("settings.click_to_sign_in_to", AppLocalization.string(platform.displayName))))
    }

    /// Spec: mineradio-bridge-compat-layer —— 待退出登录的平台（confirmationDialog 用）
    @State private var mineradioLogoutPlatform: MusicPlatform?

    /// 新建功能表单：支持「本地目录」与「网站 URL」两种类型。
    /// 本地目录可「选择已有文件夹」或「留空按名称自动生成」；
    /// 网站 URL 需输入合法 http/https 链接。
    /// Spec: webURL 模式下 URL 放第一位，URL 合法时 debounce 后自动获取网站 favicon + 标题填入图标和名称字段。
    private var addCustomAreaSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.new_feature")
                .font(.headline)

            // 类型选择
            Picker("settings.type", selection: $newFeatureType) {
                ForEach(NewFeatureType.allCases) { type in
                    Text(appLocalized: type.titleKey).tag(type)
                }
            }
            .pickerStyle(.segmented)

            // Spec: 按类型渲染不同字段顺序
            switch newFeatureType {
            case .localDirectory:
                // 本地目录：图标 → 名称 → 目录提示 → 网络开关
                newFeatureIconRow
                newFeatureNameRow
                Text("settings.a_directory_will_be_generated_from_the_name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("custom_area.allow_external_requests", isOn: $newCustomAreaAllowsNetwork)
                    .font(.caption)

            case .webURL:
                // Spec: webURL 模式 URL 放第一位 → 名称 → 图标 → 跨域登录开关
                newFeatureURLRow
                newFeatureNameRow
                newFeatureIconRow
                Toggle("settings.keep_cross_site_sign_in_in_webview", isOn: $newWebURLKeepsCrossDomainLoginInWebView)
                    .font(.caption)
                    .help("custom_area.keep_authentication_redirects_and_popups_in_the_current")
                Toggle("custom_area.load_mineradio_bridge", isOn: $newWebURLLoadsMineradioBridge)
                    .font(.caption)
                    .help("custom_area.inject_the_mineradio_bridge_compatibility_layer_for_music")
            }

            HStack {
                Spacer()
                Button("common.cancel") {
                    resetAddCustomAreaForm()
                    showingAddCustomAreaSheet = false
                }
                Button("settings.add") {
                    addCustomArea()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isAddCustomAreaFormValid)
            }
        }
        .padding(20)
        .frame(width: 420)
        .fileImporter(
            isPresented: $showingIconImagePicker,
            allowedContentTypes: [UTType.image]
        ) { result in
            switch result {
            case .success(let url):
                iconImageError = nil
                Task { @MainActor in
                    let didStartAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if didStartAccess { url.stopAccessingSecurityScopedResource() }
                    }
                    do {
                        let data = try Data(contentsOf: url)
                        let ext = url.pathExtension
                        if let iconID = IconImageStore.saveImage(
                            data: data,
                            for: "new-feature-\(UUID().uuidString.prefix(8))",
                            ext: ext
                        ) {
                            newCustomAreaIconImage = iconID
                            // 选了图片后清空文字输入，避免歧义
                            newCustomAreaIconText = ""
                        } else {
                            iconImageError = AppLocalization.runtimeString("custom_area.failed_to_save_image")
                        }
                    } catch {
                        iconImageError = AppLocalization.format("custom_area.failed_to_read_image", String(describing: error.localizedDescription))
                    }
                }
            case .failure:
                break
            }
        }
    }

    // MARK: - New Feature Form Rows

    /// Spec: URL 输入行（webURL 模式第一位）。URL 合法时 debounce 600ms 后自动获取网站 favicon + 标题。
    private var newFeatureURLRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if isFetchingMetadata {
                    ProgressView()
                        .controlSize(.mini)
                    Text("custom_area.fetching_icon_and_name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            TextField("https://example.com", text: $newFeatureURLString)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onChange(of: newFeatureURLString) { newValue in
                    scheduleMetadataFetch(for: newValue)
                }
            if !newFeatureURLString.isEmpty, !isNewWebURLValid {
                Text("custom_area.enter_a_valid_http_or_https_url")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    /// 名称输入行。
    private var newFeatureNameRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("custom_area.name")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("custom_area.name", text: $newCustomAreaName)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// 图标输入行（文字 + 图片选择 + 实时预览）。
    private var newFeatureIconRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("custom_area.icon")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                FeatureIconView(iconID: resolvedNewCustomAreaIconID, fallbackSymbol: "globe", size: 18, color: .accentColor)
                    .frame(width: 22)
                TextField("custom_area.enter_text_or_choose_an_image", text: $newCustomAreaIconText)
                    .textFieldStyle(.roundedBorder)
                Button("custom_area.choose_image") {
                    showingIconImagePicker = true
                }
                if newCustomAreaIconImage != nil {
                    Button("custom_area.delete_image") {
                        newCustomAreaIconImage = nil
                        autoFilledIconImage = nil
                        iconImageError = nil
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                }
            }
            if let iconImageError {
                Text(appLocalized: iconImageError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    /// Spec: debounce 600ms 后触发 `FaviconFetcher.fetchMetadata`。
    /// 名称覆盖规则：当前名称为空，或等于上次自动填入的 `autoFilledName` 时才覆盖；
    /// 用户手动修改过则保留。
    /// 图标覆盖规则：当前无图片，或图片等于上次自动填入的 `autoFilledIconImage` 时才覆盖；
    /// 用户手动选择过图片则保留。
    private func scheduleMetadataFetch(for urlString: String) {
        // 校验 URL 合法性
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            isFetchingMetadata = false
            return
        }
        let token = UUID()
        metadataFetchToken = token
        isFetchingMetadata = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // debounce：若期间 URL 又变化，token 不匹配则跳过
            guard token == metadataFetchToken else { return }
            FaviconFetcher.fetchMetadata(for: url) { metadata in
                guard token == metadataFetchToken else { return }
                isFetchingMetadata = false
                // 名称：仅当为空或等于上次自动填入值时覆盖
                if let title = metadata.title, !title.isEmpty {
                    let trimmedName = newCustomAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedName.isEmpty || trimmedName == autoFilledName {
                        newCustomAreaName = title
                        autoFilledName = title
                    }
                }
                // 图标：仅当无图片或图片是上次自动填入的 favicon 时覆盖
                if let iconID = metadata.iconID {
                    if newCustomAreaIconImage == nil || newCustomAreaIconImage == autoFilledIconImage {
                        newCustomAreaIconImage = iconID
                        autoFilledIconImage = iconID
                        // 图片优先，清空文字输入避免歧义
                        newCustomAreaIconText = ""
                    }
                }
            }
        }
    }

    /// 新建表单图标预览的标识符：图片优先，否则文字；均空返回 nil（FeatureIconView 回退 globe）
    private var resolvedNewCustomAreaIconID: String? {
        if let img = newCustomAreaIconImage { return img }
        let trimmed = newCustomAreaIconText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : "text:\(trimmed)"
    }

    /// 新建表单中 .webURL 类型 URL 合法性校验（http/https）。
    private var isNewWebURLValid: Bool {
        guard let url = URL(string: newFeatureURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return true
    }

    /// 新建表单「添加」按钮可用条件：
    /// - 名称非空
    /// - .localDirectory: 总是允许（可选已有目录或自动生成）
    /// - .webURL: URL 必须合法 http/https
    private var isAddCustomAreaFormValid: Bool {
        let trimmedName = newCustomAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        switch newFeatureType {
        case .localDirectory:
            return true
        case .webURL:
            return isNewWebURLValid
        }
    }

    private func addCustomArea() {
        let trimmedName = newCustomAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        // 图标标识符合并：图片优先，否则文字加 text: 前缀；均空返回 nil
        let iconName: String? = {
            if let img = newCustomAreaIconImage { return img }
            let trimmed = newCustomAreaIconText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : "text:\(trimmed)"
        }()

        switch newFeatureType {
        case .localDirectory:
            // 本地目录统一按名称自动生成
            customAreaStore.addAreaWithAutoGeneratedDirectory(
                name: trimmedName,
                iconName: iconName,
                allowsNetworkAccess: newCustomAreaAllowsNetwork
            )
        case .webURL:
            guard isNewWebURLValid else { return }
            leftFeatureStore.appendWebURLFeature(
                name: trimmedName,
                url: newFeatureURLString,
                iconName: iconName,
                keepsCrossDomainLoginInWebView: newWebURLKeepsCrossDomainLoginInWebView,
                loadsMineradioBridge: newWebURLLoadsMineradioBridge,
                variant: .traeWorkCN
            )
        }
        resetAddCustomAreaForm()
        showingAddCustomAreaSheet = false
    }

    private func resetAddCustomAreaForm() {
        newFeatureType = .localDirectory
        newCustomAreaName = ""
        newFeatureURLString = ""
        newCustomAreaIconText = ""
        newCustomAreaIconImage = nil
        iconImageError = nil
        newCustomAreaAllowsNetwork = false
        newWebURLKeepsCrossDomainLoginInWebView = true
        newWebURLLoadsMineradioBridge = false
        // Spec: 重置自动获取相关 state
        metadataFetchToken = nil
        autoFilledName = nil
        autoFilledIconImage = nil
        isFetchingMetadata = false
    }

    // MARK: - Left Content: Flow Island Display

    /// Flow Island显示卡片：
    /// - Picker 选择 Flow Island 紧凑态展示的功能（「自动」或任一已启用功能）
    /// - 选择非「自动」功能时显示「显示提示」开关（控制自定义 HTML JS Bridge 提示是否在紧凑态显示）
    private var flowIslandDisplayCard: some View {
        SettingsSectionCard(title: AppLocalization.runtimeString("settings.flow_island_display")) {
            SettingsInfoLine(
                title: AppLocalization.runtimeString("settings.compact_feature"),
                subtitle: AppLocalization.runtimeString("settings.choose_the_feature_shown_in_compact_flow_island")
            ) {
                Picker("settings.compact_feature", selection: Binding(
                    get: { leftFeatureStore.compactFeatureID ?? "" },
                    set: { leftFeatureStore.setCompactFeature(id: $0.isEmpty ? nil : $0) }
                )) {
                    Text(appLocalized: "common.automatic").tag("")
                    ForEach(leftFeatureStore.enabledFeatures) { feature in
                        Text(feature.displayName).tag(feature.id)
                    }
                }
                .labelsHidden()
                .settingsMenuPicker(width: 168)
            }

            SettingsLineDivider()

            // Spec: 选择非「自动」功能时显示「显示提示」开关
            if leftFeatureStore.compactFeatureID != nil {
                SettingsInfoLine(
                    title: AppLocalization.runtimeString("settings.show_hints"),
                    subtitle: AppLocalization.runtimeString("settings.show_hints_sent_by_custom_html_through_js")
                ) {
                    Toggle("", isOn: $settings.showCompactHintEnabled)
                        .labelsHidden()
                        .settingsCompactSwitch()
                }

                SettingsLineDivider()
            }

            // Spec: 远程 URL 功能收起后保活开关
            SettingsInfoLine(
                title: AppLocalization.runtimeString("settings.keep_running_when_collapsed"),
                subtitle: AppLocalization.runtimeString("settings.keep_url_features_running_when_flow_island_collapses")
            ) {
                Toggle("", isOn: $settings.keepWebURLAliveWhenCollapsed)
                    .labelsHidden()
                    .settingsCompactSwitch()
            }
        }
    }

    private var screenPicker: some View {
        Picker("settings.display_2", selection: screenSelectionBinding) {
            Text(appLocalized: "common.automatic").tag("automatic")
            ForEach(screenSelector.availableScreens, id: \.self) { screen in
                Text(screen.localizedName).tag(screenToken(for: screen))
            }
        }
        .labelsHidden()
        .settingsMenuPicker(width: 168)
    }

    private var appLanguagePicker: some View {
        Picker("settings.language", selection: $settings.appLanguage) {
            ForEach(AppLanguage.allCases) { language in
                Text(appLocalized: language.title).tag(language)
            }
        }
        .labelsHidden()
        .settingsMenuPicker(width: 168)
    }

    private var screenSelectionBinding: Binding<String> {
        Binding(
            get: {
                if screenSelector.selectionMode == .automatic {
                    return "automatic"
                }
                if let selected = screenSelector.selectedScreen {
                    return screenToken(for: selected)
                }
                return "automatic"
            },
            set: { token in
                if token == "automatic" {
                    screenSelector.selectAutomatic()
                } else if let screen = screenSelector.availableScreens.first(where: { screenToken(for: $0) == token }) {
                    screenSelector.selectScreen(screen)
                }
                NotificationCenter.default.post(
                    name: NSApplication.didChangeScreenParametersNotification,
                    object: nil
                )
            }
        )
    }

    private func shortcutBinding(for action: GlobalShortcutAction) -> Binding<GlobalShortcut?> {
        Binding(
            get: { settings.shortcut(for: action) },
            set: { settings.setShortcut($0, for: action) }
        )
    }

    private func screenToken(for screen: NSScreen) -> String {
        let identifier = ScreenIdentifier(screen: screen)
        return "\(identifier.displayID ?? 0)-\(identifier.localizedName)"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var versionMetadata: String {
        guard let metadata = HookInstaller.getVersionMetadata(),
              let installedAt = metadata["installedAt"] as? String else {
            return AppLocalization.string("settings.first_install")
        }

        // Format the date
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: installedAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.locale = settings.locale
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }

        return installedAt
    }

    private var updateTitle: String {
        switch updateManager.state {
        case .idle, .upToDate:
            return AppLocalization.string("settings.check_for_updates")
        case .checking:
            return AppLocalization.string("settings.checking")
        case .found, .downloading, .extracting:
            return AppLocalization.string("settings.updating_in_background")
        case .readyToInstall:
            return AppLocalization.string("settings.waiting_to_restart_and_install")
        case .installing:
            return AppLocalization.string("settings.installing_update")
        case .error:
            return AppLocalization.string("settings.retry_update")
        }
    }

    private var updateSubtitle: String {
        switch updateManager.state {
        case .idle:
            return updateManager.isConfigured
                ? AppLocalization.string(
                    settings.automaticUpdateChecksEnabled
                        ? AppLocalization.runtimeString("settings.automatically_check_download_and_install_updates_on_launch_and")
                        : AppLocalization.runtimeString("settings.automatic_updates_are_off_you_can_check_manually")
                )
                : updateManager.configurationStatus.message
        case .upToDate:
            return AppLocalization.string("settings.you_re_already_on_the_latest_version")
        case .checking:
            return AppLocalization.string("settings.checking_for_updates_in_background")
        case .found(let version, _):
            return AppLocalization.format("settings.version_v_found_downloading_and_installing_silently", version)
        case .downloading:
            return AppLocalization.string("settings.downloading_update_in_background")
        case .extracting:
            return AppLocalization.string("settings.preparing_update")
        case .readyToInstall(let version):
            return AppLocalization.format("settings.v_is_ready_restart_now_or_wait_for", version)
        case .installing:
            return AppLocalization.string("settings.installing_and_restarting_silently")
        case .error:
            return AppLocalization.string("settings.background_update_failed_click_to_check_again")
        }
    }

    @ViewBuilder
    private var updateAccessory: some View {
        switch updateManager.state {
        case .checking, .downloading, .extracting, .installing:
            ProgressView()
                .controlSize(.small)
        case .upToDate:
            Text(appLocalized: "settings.latest")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TerminalColors.green)
        case .found(let version, _), .readyToInstall(let version):
            Text("v\(version)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TerminalColors.green)
        case .idle, .error:
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private func handleUpdateAction() {
        switch updateManager.state {
        case .idle, .upToDate, .error:
            updateManager.checkForUpdates()
        case .checking, .found, .downloading, .extracting, .readyToInstall, .installing:
            break
        }
    }
}

private struct CompletionPromptRegexRulesSettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    @State private var expandedRuleIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.completion_reply_detection")
                    .font(.system(size: 13, weight: .medium))
                Text("settings.when_a_stop_response_has_no_native_question")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)

            ForEach($settings.completionPromptRegexRules) { $rule in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedRuleIDs.contains(rule.id) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedRuleIDs.insert(rule.id)
                            } else {
                                expandedRuleIDs.remove(rule.id)
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        labeledEditor(
                            title: AppLocalization.runtimeString("settings.trigger_regex"),
                            text: $rule.triggerPattern,
                            minimumHeight: 56
                        )
                        if let error = CompletionPromptRegexParser.validationError(
                            for: rule.triggerPattern
                        ) {
                            validationText(error)
                        }

                        Toggle("settings.free_text_only_no_preset_options", isOn: $rule.isFreeformOnly)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))

                        if !rule.isFreeformOnly {
                            if rule.capturesTriggerGroupsAsOptions {
                                Text("settings.capture_groups_1_2_become_options_a_b")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else {
                                labeledEditor(
                                    title: AppLocalization.runtimeString("settings.option_regex_group_1_key_group_2_text"),
                                    text: $rule.optionPattern,
                                    minimumHeight: 56
                                )
                                if !rule.optionPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                   let error = CompletionPromptRegexParser.validationError(
                                       for: rule.optionPattern
                                   ) {
                                    validationText(error)
                                }
                            }

                            Toggle("settings.allow_multiple_selections", isOn: $rule.allowsMultiple)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))

                            if rule.capturesTriggerGroupsAsOptions {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("settings.reply_template")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                    TextField("completion.select_key_option", text: $rule.replyTemplate)
                                        .textFieldStyle(.roundedBorder)
                                }
                            } else if rule.optionPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                staticOptionsEditor(rule: $rule)
                            } else {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("settings.reply_template")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                    TextField("completion.select_key_option", text: $rule.replyTemplate)
                                        .textFieldStyle(.roundedBorder)
                                    Text("settings.use_key_and_option_placeholders")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                removeRule(rule.id)
                            } label: {
                                Label("settings.delete_rule", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.leading, 24)
                } label: {
                    HStack(spacing: 10) {
                        TextField("settings.rule_name", text: Binding(
                            get: {
                                rule.localizedName
                            },
                            set: { rule.name = $0 }
                        ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(appLocalized: ruleModeLabel(rule))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Toggle("translation.enabled", isOn: $rule.isEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .font(.system(size: 10, weight: .medium))
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 18)
            }

            HStack(spacing: 8) {
                Button("settings.add_rule", action: addRule)
                    .buttonStyle(.bordered)
                Button("settings.restore_default_templates") {
                    settings.completionPromptRegexRules = CompletionPromptRegexRule.defaultTemplates
                    expandedRuleIDs.removeAll()
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 4)
    }

    private func labeledEditor(
        title: String,
        text: Binding<String>,
        minimumHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(appLocalized: title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            TextEditor(text: text)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: minimumHeight)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }

    @ViewBuilder
    private func staticOptionsEditor(
        rule: Binding<CompletionPromptRegexRule>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("settings.fixed_options")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            ForEach(rule.staticOptions) { $option in
                HStack(spacing: 7) {
                    TextField("settings.button_label", text: $option.title)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    TextField("settings.reply_content", text: $option.reply)
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        removeStaticOption(ruleID: rule.wrappedValue.id, optionID: option.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                appendStaticOption(to: rule.wrappedValue.id)
            } label: {
                Label("settings.add_option", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    private func validationText(_ message: String) -> some View {
        Text(appLocalized: message)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(TerminalColors.amber)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func ruleModeLabel(_ rule: CompletionPromptRegexRule) -> String {
        if rule.isFreeformOnly {
            return AppLocalization.runtimeString("settings.free_text")
        }
        if rule.capturesTriggerGroupsAsOptions {
            return rule.allowsMultiple ? AppLocalization.runtimeString("settings.inline_multiple_choice") : AppLocalization.runtimeString("settings.inline_single_choice")
        }
        if rule.optionPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rule.allowsMultiple ? AppLocalization.runtimeString("settings.fixed_multiple_choice") : AppLocalization.runtimeString("settings.fixed_single_choice")
        }
        return rule.allowsMultiple ? AppLocalization.runtimeString("settings.extracted_multiple_choice") : AppLocalization.runtimeString("settings.extracted_single_choice")
    }

    private func addRule() {
        let rule = CompletionPromptRegexRule(
            name: AppLocalization.runtimeString("settings.custom_rule"),
            triggerPattern: #"(?is)请输入你的触发正则"#,
            staticOptions: [
                CompletionPromptStaticOption(title: "确认", reply: "确认，请继续。"),
                CompletionPromptStaticOption(title: "取消", reply: "请先暂停。")
            ]
        )
        settings.completionPromptRegexRules.append(rule)
        expandedRuleIDs.insert(rule.id)
    }

    private func removeRule(_ id: String) {
        settings.completionPromptRegexRules.removeAll { $0.id == id }
        expandedRuleIDs.remove(id)
    }

    private func appendStaticOption(to ruleID: String) {
        guard let index = settings.completionPromptRegexRules.firstIndex(where: { $0.id == ruleID }) else {
            return
        }
        settings.completionPromptRegexRules[index].staticOptions.append(
            CompletionPromptStaticOption(title: "新选项", reply: "新回复")
        )
    }

    private func removeStaticOption(ruleID: String, optionID: String) {
        guard let index = settings.completionPromptRegexRules.firstIndex(where: { $0.id == ruleID }) else {
            return
        }
        settings.completionPromptRegexRules[index].staticOptions.removeAll { $0.id == optionID }
    }
}

struct SettingsWindowView: View {
    var onClose: (() -> Void)? = nil
    var onMinimize: (() -> Void)? = nil

    var body: some View {
        AppLocalizedRootView {
            SettingsPanelContentView(
                presentation: .window,
                onClose: onClose,
                onMinimize: onMinimize
            )
            .accessibilityIdentifier("settings.root")
        }
    }
}

struct NotchSettingsPopoverView: View {
    var body: some View {
        AppLocalizedRootView {
            SettingsPanelContentView(presentation: .popover)
                .frame(width: SettingsPanelMetrics.popoverSize.width, height: SettingsPanelMetrics.popoverSize.height)
        }
    }
}

private struct SidebarItemView: View {
    let category: SettingsCategory
    let isSelected: Bool
    var showsNoticeDot: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: category.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(isSelected ? 0.95 : 1))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                isSelected
                                ? LinearGradient(
                                    colors: [
                                        category.tint.opacity(0.95),
                                        category.tint.opacity(0.60)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [
                                        category.tint.opacity(0.92),
                                        category.tint.opacity(0.74)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if showsNoticeDot {
                    Circle()
                        .fill(TerminalColors.amber)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.black.opacity(0.42), lineWidth: 1)
                        )
                        .offset(x: 2, y: -2)
                        .accessibilityLabel("settings.integration_notice_available")
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(appLocalized: category.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(isSelected ? 0.94 : 0.80))
                    .lineLimit(1)

                Text(appLocalized: category.subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(isSelected ? 0.60 : 0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(isSelected ? 0.10 : 0.04), lineWidth: 1)
        )
        .shadow(color: isSelected ? category.tint.opacity(0.18) : .clear, radius: 14, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct WindowControlButton: View {
    let color: Color
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
            )
            .contentShape(Circle())
            .onTapGesture(perform: action)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pointingHand.pop()
                }
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }
}

private enum PanelDesignDestination {
    case codex
    case claude
    case traeWork

    var buttonTitle: String {
        switch self {
        case .codex: return AppLocalization.runtimeString("settings.create_in_codex_design")
        case .claude: return AppLocalization.runtimeString("settings.create_in_claude_code_design")
        case .traeWork: return AppLocalization.runtimeString("settings.create_in_trae_work_design")
        }
    }

    var applicationDisplayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .traeWork: return "TRAE Work"
        }
    }
}

@MainActor
private enum PanelDesignAppLauncher {
    static func activate(
        _ destination: PanelDesignDestination,
        completion: @escaping (Bool) -> Void
    ) {
        switch destination {
        case .codex:
            activateDesktopApplication(
                bundleIdentifier: "com.openai.codex",
                fallbackApplicationName: "Codex",
                completion: completion
            )
        case .claude:
            activateDesktopApplication(
                bundleIdentifier: "com.anthropic.claudefordesktop",
                fallbackApplicationName: "Claude",
                completion: completion
            )
        case .traeWork:
            completion(TraeSessionLauncher.activate(.traeWorkCN))
        }
    }

    private static func activateDesktopApplication(
        bundleIdentifier: String,
        fallbackApplicationName: String,
        completion: @escaping (Bool) -> Void
    ) {
        let workspace = NSWorkspace.shared

        if let runningApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first {
            completion(runningApplication.activate(options: [.activateAllWindows]))
            return
        }

        let applicationURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
            ?? fallbackApplicationURLs(named: fallbackApplicationName).first {
                FileManager.default.fileExists(atPath: $0.path)
            }
        guard let applicationURL else {
            completion(false)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: applicationURL, configuration: configuration) { application, _ in
            DispatchQueue.main.async {
                if let application {
                    _ = application.activate(options: [.activateAllWindows])
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }

    private static func fallbackApplicationURLs(named applicationName: String) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ].map {
            $0.appendingPathComponent("\(applicationName).app", isDirectory: true)
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    private let titleLeadingAccessory: AnyView?
    private let titleAccessory: AnyView?
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.titleLeadingAccessory = nil
        self.titleAccessory = nil
        self.content = content()
    }

    init<Accessory: View>(
        title: String,
        @ViewBuilder titleAccessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleLeadingAccessory = nil
        self.titleAccessory = AnyView(titleAccessory())
        self.content = content()
    }

    init<LeadingAccessory: View, Accessory: View>(
        title: String,
        @ViewBuilder titleLeadingAccessory: () -> LeadingAccessory,
        @ViewBuilder titleAccessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleLeadingAccessory = AnyView(titleLeadingAccessory())
        self.titleAccessory = AnyView(titleAccessory())
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(appLocalized: title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                if let titleLeadingAccessory {
                    titleLeadingAccessory
                }

                Spacer(minLength: 12)

                if let titleAccessory {
                    titleAccessory
                }
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(
                        SettingsGlassSurface(material: .hudWindow, blendingMode: .withinWindow)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .opacity(0.96)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.08),
                                        Color.white.opacity(0.025),
                                        Color.black.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 18, y: 10)
        }
    }
}

private struct SettingsLineDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.10))
            .padding(.horizontal, 18)
    }
}

private struct HookManagementLine: View {
    let profile: ManagedHookClientProfile
    let hookStatus: SettingsPanelViewModel.HookPresentationStatus
    let isReinstalling: Bool
    let reinstallFeedback: SettingsPanelViewModel.HookReinstallFeedback?
    let noticeMessage: String?
    let supportsEventSelection: Bool
    let isInstallDisabled: Bool
    let installAction: () -> Void
    let configureAction: () -> Void
    let openConfigurationDirectoryAction: () -> Void
    let trustGuideAction: () -> Void
    let reinstallAction: () -> Void
    let uninstallAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                HookManagementIcon(profile: profile)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appLocalized: title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text(appLocalized: subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if isInstallDisabled, let noticeMessage {
                    Text(appLocalized: noticeMessage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(TerminalColors.amber.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TerminalColors.amber.opacity(0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(TerminalColors.amber.opacity(0.28), lineWidth: 1)
                        )
                } else {
                    Text(appLocalized: statusTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(statusForegroundColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(statusTint.opacity(hookStatus.isInstalled ? 0.18 : 0.08))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(statusTint.opacity(hookStatus.isInstalled ? 0.28 : 0.12), lineWidth: 1)
                        )
                }
            }

            HStack(spacing: 10) {
                if hookStatus.isInstalled {
                    if hookStatus == .awaitingCodexTrust {
                        HookManagementButton(
                            title: AppLocalization.runtimeString("settings.trust_guide"),
                            tint: TerminalColors.amber,
                            isDisabled: isReinstalling,
                            action: trustGuideAction
                        )
                    }
                    if supportsEventSelection {
                        HookManagementButton(
                            title: AppLocalization.runtimeString("settings.configure"),
                            tint: tint,
                            isDisabled: isReinstalling,
                            action: configureAction
                        )
                    }
                    HookManagementButton(
                        title: AppLocalization.runtimeString("settings.open_folder"),
                        tint: TerminalColors.blue,
                        isDisabled: isReinstalling,
                        action: openConfigurationDirectoryAction
                    )
                    HookManagementButton(
                        title: isReinstalling ? AppLocalization.runtimeString("settings.reinstalling") : AppLocalization.runtimeString("settings.reinstall"),
                        tint: tint,
                        isLoading: isReinstalling,
                        isDisabled: isReinstalling,
                        action: reinstallAction
                    )
                    HookManagementButton(
                        title: AppLocalization.runtimeString("settings.uninstall"),
                        tint: TerminalColors.amber,
                        isDisabled: isReinstalling,
                        action: uninstallAction
                    )
                } else {
                    HookManagementButton(
                        title: AppLocalization.runtimeString("settings.install"),
                        tint: tint,
                        isDisabled: isReinstalling || isInstallDisabled,
                        action: installAction
                    )
                }
            }

            if let reinstallFeedback {
                HStack(spacing: 8) {
                    Image(systemName: reinstallFeedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(reinstallFeedback.isError ? TerminalColors.amber : TerminalColors.green)

                    Text(reinstallFeedback.message)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.76))
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isInstallDisabled ? 0.45 : 1.0)
    }

    private var title: String {
        profile.title
    }

    private var subtitle: String {
        profile.subtitle
    }

    private var tint: Color {
        brandTint(profile.brand)
    }

    private var statusTitle: String {
        switch hookStatus {
        case .notInstalled: return AppLocalization.runtimeString("settings.not_installed")
        case .installed: return AppLocalization.runtimeString("settings.installed")
        case .awaitingCodexTrust: return AppLocalization.runtimeString("settings.trust_required")
        case .active: return AppLocalization.runtimeString("settings.active")
        }
    }

    private var statusTint: Color {
        switch hookStatus {
        case .awaitingCodexTrust: return TerminalColors.amber
        case .active: return TerminalColors.green
        case .installed: return tint
        case .notInstalled: return .white
        }
    }

    private var statusForegroundColor: Color {
        hookStatus.isInstalled ? statusTint : .white.opacity(0.65)
    }
}

private struct CustomHookInstallationLine: View {
    let installation: HookInstaller.CustomHookInstallation
    let uninstallAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                if let profile = ClientProfileRegistry.managedHookProfile(id: installation.profileID) {
                    HookManagementIcon(profile: profile)
                } else {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(appLocalized: installation.profileTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)

                        Text(appLocalized: "settings.custom")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(TerminalColors.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(TerminalColors.blue.opacity(0.18))
                            )
                    }

                    Text(installation.customPath)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                Text(appLocalized: "settings.installed")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(TerminalColors.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(TerminalColors.green.opacity(0.18))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(TerminalColors.green.opacity(0.28), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                HookManagementButton(
                    title: AppLocalization.runtimeString("settings.uninstall"),
                    tint: TerminalColors.amber,
                    action: uninstallAction
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CustomHookInstallSheet: View {
    @ObservedObject var viewModel: SettingsPanelViewModel
    let onDismiss: () -> Void

    @State private var selectedProfileID: String = ""
    @State private var customPath: String = ""

    private var availableProfiles: [ManagedHookClientProfile] {
        ClientProfileRegistry.managedHookProfiles
    }

    private var canInstall: Bool {
        !selectedProfileID.isEmpty && !customPath.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(appLocalized: "settings.add_custom_hook_configuration")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appLocalized: "settings.choose_app")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    Picker("", selection: $selectedProfileID) {
                        Text(appLocalized: "settings.please_select").tag("")
                        ForEach(availableProfiles) { profile in
                            Text(profile.title).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(appLocalized: "settings.installation_directory")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    HStack(spacing: 8) {
                        TextField("", text: $customPath, prompt: Text(verbatim: installPathPlaceholder))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                            )

                        Button(action: selectDirectory) {
                            Text(appLocalized: "settings.choose_directory")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if let resolvedFileName {
                        Text(resolvedInstallTargetDescription(resolvedFileName: resolvedFileName))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let installHint {
                        Text(verbatim: installHint)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            }

            HStack(spacing: 12) {
                Spacer()

                Button(action: onDismiss) {
                    Text(appLocalized: "common.cancel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: install) {
                    Text(appLocalized: "settings.install")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(canInstall ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(canInstall ? TerminalColors.blue.opacity(0.5) : .white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(canInstall ? TerminalColors.blue.opacity(0.5) : .white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canInstall)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private var resolvedFileName: String? {
        guard let profile = ClientProfileRegistry.managedHookProfile(id: selectedProfileID),
              !customPath.isEmpty else {
            return nil
        }
        return profile.primaryConfigurationURL.lastPathComponent
    }

    private var installPathPlaceholder: String {
        guard let profile = ClientProfileRegistry.managedHookProfile(id: selectedProfileID) else {
            return AppLocalization.runtimeString("settings.e_g_path_to_claude")
        }

        switch profile.installationKind {
        case .jsonHooks, .antigravityHooks, .tomlHooks:
            return AppLocalization.runtimeString("settings.e_g_path_to_claude")
        case .pluginFile:
            return AppLocalization.runtimeString("settings.e_g_path_to_plugins")
        case .pluginDirectory:
            return AppLocalization.runtimeString("settings.e_g_path_to_plugins")
        case .hookDirectory:
            return AppLocalization.runtimeString("settings.e_g_path_to_hooks")
        }
    }

    private var installHint: String? {
        return nil
    }

    private func resolvedInstallTargetDescription(resolvedFileName: String) -> String {
        guard let profile = ClientProfileRegistry.managedHookProfile(id: selectedProfileID) else {
            return AppLocalization.format("settings.will_write_to", customPath, resolvedFileName)
        }

        let baseURL = URL(fileURLWithPath: customPath)
        let targetURL: URL
        switch profile.installationKind {
        case .jsonHooks, .antigravityHooks, .pluginFile, .tomlHooks:
            targetURL = baseURL.appendingPathComponent(resolvedFileName)
        case .pluginDirectory:
            if baseURL.lastPathComponent == "plugins" {
                targetURL = baseURL.appendingPathComponent(resolvedFileName, isDirectory: true)
            } else {
                targetURL = baseURL.appendingPathComponent(resolvedFileName, isDirectory: true)
            }
        case .hookDirectory:
            if baseURL.lastPathComponent == "hooks" {
                targetURL = baseURL.appendingPathComponent(resolvedFileName, isDirectory: true)
            } else {
                targetURL = baseURL.appendingPathComponent(resolvedFileName, isDirectory: true)
            }
        }

        return AppLocalization.format("settings.will_write_to_2", targetURL.path)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = AppLocalization.string("settings.choose_hook_configuration_directory")
        panel.prompt = AppLocalization.string("settings.select")

        if panel.runModal() == .OK, let url = panel.url {
            customPath = url.path
        }
    }

    private func install() {
        guard canInstall else { return }
        viewModel.installCustomHook(profileID: selectedProfileID, directoryPath: customPath)
        onDismiss()
    }
}

enum HookInstallOptionsMode {
    case install
    case edit
}

struct HookInstallOptionsRequest: Identifiable {
    let id = UUID()
    let profile: ManagedHookClientProfile
    let mode: HookInstallOptionsMode
}

private struct HookInstallOptionsSheet: View {
    let profile: ManagedHookClientProfile
    let mode: HookInstallOptionsMode
    let initialSelection: HookInstallSelection
    let onConfirm: (HookInstallSelection) -> Void
    let onDismiss: () -> Void

    @State private var enabledEventNames: Set<String>
    @State private var advancedExpanded: Bool

    init(
        profile: ManagedHookClientProfile,
        mode: HookInstallOptionsMode,
        initialSelection: HookInstallSelection,
        onConfirm: @escaping (HookInstallSelection) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.profile = profile
        self.mode = mode
        self.initialSelection = initialSelection
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _enabledEventNames = State(initialValue: initialSelection.enabledEventNames)
        _advancedExpanded = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    categoryToggles
                    advancedSection
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 360)

            footer
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            HookManagementIcon(profile: profile)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: profile.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text(appLocalized: headerSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
    }

    private var categoryToggles: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(profile.availableEventCategories) { category in
                CategoryToggleRow(
                    category: category,
                    state: state(for: category),
                    onToggle: { toggleCategory(category) }
                )

                if category != profile.availableEventCategories.last {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                        .padding(.horizontal, 14)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(profile.availableEventCategories) { category in
                    let events = profile.events(in: category)
                    if !events.isEmpty {
                        Text(appLocalized: category.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .padding(.bottom, 4)

                        ForEach(events, id: \.name) { event in
                            EventToggleRow(
                                event: event,
                                isOn: enabledEventNames.contains(event.name),
                                onToggle: { toggleEvent(event.name) }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        } label: {
            Text(appLocalized: "settings.advanced_toggle_individual_events")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.78))
        }
        .tint(.white.opacity(0.6))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(appLocalized: footerHint)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: onDismiss) {
                Text(appLocalized: "common.cancel")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: confirm) {
                Text(appLocalized: confirmTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(canConfirm ? .white : .white.opacity(0.4))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(canConfirm ? brandTint(profile.brand).opacity(0.5) : .white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(canConfirm ? brandTint(profile.brand).opacity(0.55) : .white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canConfirm)
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .install:
            return AppLocalization.runtimeString("settings.pick_which_hook_event_categories_to_install_use")
        case .edit:
            return AppLocalization.runtimeString("settings.adjust_which_hook_events_are_active_saving_rewrites")
        }
    }

    private var footerHint: String {
        AppLocalization.string("settings.everything_is_enabled_by_default_disable_an_event")
    }

    private var confirmTitle: String {
        switch mode {
        case .install: return AppLocalization.runtimeString("settings.install")
        case .edit: return AppLocalization.runtimeString("common.save")
        }
    }

    private var canConfirm: Bool {
        !enabledEventNames.isEmpty
    }

    private func confirm() {
        guard canConfirm else { return }
        onConfirm(HookInstallSelection(enabledEventNames: enabledEventNames))
    }

    private func state(for category: HookInstallEventCategory) -> CategoryToggleState {
        let names = profile.events(in: category).map(\.name)
        guard !names.isEmpty else { return .off }
        let enabledCount = names.filter { enabledEventNames.contains($0) }.count
        if enabledCount == 0 { return .off }
        if enabledCount == names.count { return .on }
        return .mixed
    }

    private func toggleCategory(_ category: HookInstallEventCategory) {
        let names = profile.events(in: category).map(\.name)
        let currentState = state(for: category)
        switch currentState {
        case .on:
            for name in names { enabledEventNames.remove(name) }
        case .off, .mixed:
            for name in names { enabledEventNames.insert(name) }
        }
    }

    private func toggleEvent(_ name: String) {
        if enabledEventNames.contains(name) {
            enabledEventNames.remove(name)
        } else {
            enabledEventNames.insert(name)
        }
    }
}

private enum CategoryToggleState {
    case on
    case off
    case mixed
}

private struct CategoryToggleRow: View {
    let category: HookInstallEventCategory
    let state: CategoryToggleState
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: category.iconSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.78))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(appLocalized: category.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(appLocalized: category.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: onToggle) {
                indicator
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .on:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(TerminalColors.green)
        case .mixed:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(TerminalColors.amber)
        case .off:
            Image(systemName: "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}

private struct EventToggleRow: View {
    let event: HookInstallEventDescriptor
    let isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(verbatim: event.name)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.86))

            if let timeout = event.timeout {
                Text(verbatim: "\(timeout)s")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.05))
                    )
            }

            Spacer(minLength: 12)

            Button(action: onToggle) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isOn ? TerminalColors.green : .white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

private struct HookManagementIcon: View {
    let profile: ManagedHookClientProfile

    var body: some View {
        SettingsClientIcon(
            logoAssetName: profile.logoAssetName,
            prefersBundledLogoOverAppIcon: profile.prefersBundledLogoOverAppIcon,
            localAppBundleIdentifiers: profile.localAppBundleIdentifiers,
            iconSymbolName: profile.iconSymbolName
        )
    }
}

private struct SettingsClientIcon: View {
    let logoAssetName: String?
    let prefersBundledLogoOverAppIcon: Bool
    let localAppBundleIdentifiers: [String]
    let iconSymbolName: String

    var body: some View {
        if let preferredLogoAssetName {
            Image(preferredLogoAssetName)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 28, height: 28)
                .frame(width: 34, height: 34)
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
                .accessibilityHidden(true)
        } else if let resolvedAppIcon {
            Image(nsImage: resolvedAppIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 34, height: 34)
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
        } else {
            Image(systemName: iconSymbolName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }

    private var resolvedAppIcon: NSImage? {
        ClientAppLocator.icon(bundleIdentifiers: localAppBundleIdentifiers)
    }

    private var preferredLogoAssetName: String? {
        guard let logoAssetName else {
            return nil
        }

        return prefersBundledLogoOverAppIcon || resolvedAppIcon == nil
            ? logoAssetName
            : nil
    }
}

private func brandTint(_ brand: SessionClientBrand) -> Color {
    brand.tintColor
}

private struct HookManagementButton: View {
    let title: String
    let tint: Color
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.86))
                }

                Text(appLocalized: title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.22))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.34), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
    }
}

private struct SettingsToggleLine: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 16) {
                Text(appLocalized: title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 12)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .settingsCompactSwitch()
            }

            if let subtitle {
                Text(appLocalized: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
    }
}

private extension View {
    func settingsCompactSwitch(scale: CGFloat = 0.84) -> some View {
        self
            .toggleStyle(.switch)
            .controlSize(.small)
            .scaleEffect(scale)
            .frame(width: 32, height: 18)
    }

    func settingsMenuPicker(width: CGFloat) -> some View {
        self
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: width, alignment: .trailing)
    }
}

private struct SettingsInfoLine<Accessory: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 16) {
                Text(appLocalized: title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 12)

                accessory
            }

            if let subtitle {
                Text(appLocalized: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SoundPackSourceInfoLine<Accessory: View>: View {
    @ViewBuilder let accessory: Accessory

    private let sourcePaths = [
        "~/.openpeon/packs",
        ".claude/hooks/peon-ping/packs"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Text(appLocalized: "settings.current_sound_pack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 12)

                accessory
            }

            Text(appLocalized: "settings.automatically_scan_the_following_directories_or_import_a")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(sourcePaths, id: \.self) { path in
                    SettingsCodeCapsule(text: path, systemImage: "folder")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsActionLine<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let action: () -> Void
    @ViewBuilder let accessory: Accessory

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appLocalized: title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    if let subtitle {
                        Text(appLocalized: subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                accessory
                    .frame(minWidth: 36, minHeight: 36, alignment: .center)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SoundPackImportActionLine<Accessory: View>: View {
    let action: () -> Void
    @ViewBuilder let accessory: Accessory

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 16) {
                    Text(appLocalized: "settings.import_local_sound_pack")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer(minLength: 12)

                    accessory
                }

                Text(appLocalized: "settings.choose_a_local_directory_to_import_it_into")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(appLocalized: "settings.the_directory_must_contain_this_manifest_file")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.42))

                    SettingsCodeCapsule(text: "openpeon.json", systemImage: "doc.text")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCodeCapsule: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.42))

            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.74))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SettingsValueLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(appLocalized: title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Spacer(minLength: 12)

            Text(appLocalized: value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSliderLine: View {
    let title: String
    let subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    var showsTickMarks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(appLocalized: title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 12)

                Text(format(value))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
            }

            if let subtitle {
                Text(appLocalized: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Slider(value: $value, in: range, step: step)
                .tint(TerminalColors.blue)

            if showsTickMarks {
                HStack(spacing: 0) {
                    ForEach(0..<17, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 1, height: 6)

                        Spacer(minLength: 0)
                    }

                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 1, height: 6)
                }
                .padding(.horizontal, 6)
                .padding(.top, -7)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct ShortcutSettingsLine: View {
    let action: GlobalShortcutAction
    @Binding var shortcut: GlobalShortcut?

    var body: some View {
        ShortcutRecorderControl(
            action: action,
            shortcut: $shortcut,
            defaultShortcut: action.defaultShortcut
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeatureShortcutEditor: View {
    let feature: LeftFeature
    let onSave: (GlobalShortcut?) -> Void
    let onCancel: () -> Void

    @State private var shortcut: GlobalShortcut?
    @State private var isRecording = false
    @State private var errorText: String?
    @State private var eventMonitor: Any?

    init(
        feature: LeftFeature,
        onSave: @escaping (GlobalShortcut?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.feature = feature
        self.onSave = onSave
        self.onCancel = onCancel
        _shortcut = State(initialValue: feature.globalShortcut)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(feature.displayName)
                .font(.system(size: 16, weight: .bold))
            Text(appLocalized: "settings.set_a_global_shortcut_to_open_this_feature")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                if let shortcut {
                    ShortcutVisualLabel(shortcut: shortcut)
                } else {
                    Text(appLocalized: "settings.not_set")
                        .foregroundColor(.secondary)
                }
                Spacer()
                if shortcut != nil {
                    Button("settings.clear") {
                        shortcut = nil
                        errorText = nil
                    }
                }
                Button("settings.reset") {
                    shortcut = nil
                    errorText = nil
                }
                Button(isRecording ? AppLocalization.runtimeString("settings.press_new_shortcut") : AppLocalization.runtimeString("settings.record_shortcut")) {
                    isRecording ? stopRecording() : startRecording()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 44)

            Text(appLocalized: errorText ?? (isRecording ? AppLocalization.runtimeString("settings.recording_press_esc_to_cancel_or_delete_to") : AppLocalization.runtimeString("settings.use_at_least_one_modifier_key")))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(errorText == nil ? .secondary : .red)
                .accessibilityLabel(Text(errorText ?? ""))

            HStack {
                Spacer()
                Button("common.cancel") { stopRecording(); onCancel() }
                Button("common.save") {
                    if let shortcut,
                       let owner = LeftFeatureStore.shared.conflictingShortcutOwner(
                           for: shortcut,
                           excludingFeatureID: feature.id
                       ) {
                        errorText = AppLocalization.format("settings.this_shortcut_is_already_used_by", String(describing: owner))
                        NSSound.beep()
                    } else {
                        onSave(shortcut)
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(errorText != nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        errorText = nil
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            shortcut = nil
            errorText = nil
            stopRecording()
            return
        }
        guard let recorded = GlobalShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags) else {
            errorText = AppLocalization.runtimeString("settings.use_at_least_one_modifier_key")
            return
        }
        if let owner = LeftFeatureStore.shared.conflictingShortcutOwner(
            for: recorded,
            excludingFeatureID: feature.id
        ) {
            errorText = AppLocalization.format("settings.this_shortcut_is_already_used_by", String(describing: owner))
            NSSound.beep()
            return
        }
        shortcut = recorded
        errorText = nil
        stopRecording()
    }
}

private struct ShortcutRecorderControl: View {
    @ObservedObject private var shortcutManager = GlobalShortcutManager.shared
    let action: GlobalShortcutAction
    @Binding var shortcut: GlobalShortcut?
    let defaultShortcut: GlobalShortcut?

    @State private var isRecording = false
    @State private var helperTextKey: String?
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appLocalized: action.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text(appLocalized: action.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                recordButton
            }

            HStack(alignment: .center, spacing: 8) {
                Text(appLocalized: "settings.current")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.40))

                if let shortcut {
                    ShortcutVisualLabel(
                        shortcut: shortcut,
                        fontSize: 11,
                        foregroundColor: .white.opacity(0.92),
                        keyBackground: Color.black.opacity(0.28),
                        keyBorder: Color.white.opacity(0.08),
                        keyMinWidth: 24,
                        keyHorizontalPadding: 7,
                        keyVerticalPadding: 5,
                        keyCornerRadius: 10
                    )
                } else {
                    Text(appLocalized: "settings.not_set")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.42))
                }

                Spacer(minLength: 12)

                if shortcut != nil {
                    Button {
                        shortcut = nil
                        helperTextKey = nil
                        stopRecording()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(ShortcutIconButtonStyle())
                    .help(AppLocalization.string("settings.clear_shortcut"))
                    .accessibilityLabel(Text(appLocalized: "settings.clear_shortcut"))
                }

                if defaultShortcut != nil {
                    Button {
                        applyShortcut(defaultShortcut)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(ShortcutIconButtonStyle())
                    .help(AppLocalization.string("settings.restore_default_shortcut"))
                    .accessibilityLabel(Text(appLocalized: "settings.restore_default_shortcut"))
                }
            }

            Text(appLocalized: helperTextKey
                ?? shortcutManager.registrationError(for: action)
                ?? (isRecording ? AppLocalization.runtimeString("settings.recording_press_esc_to_cancel_or_delete_to") : AppLocalization.runtimeString("settings.use_at_least_one_modifier_key")))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(helperTextKey == nil && shortcutManager.registrationError(for: action) == nil
                    ? (isRecording ? TerminalColors.green.opacity(0.90) : .white.opacity(0.42))
                    : .red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var recordButton: some View {
        Button {
            toggleRecording()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                    .font(.system(size: 11, weight: .bold))

                Text(appLocalized: isRecording ? AppLocalization.runtimeString("settings.press_new_shortcut") : AppLocalization.runtimeString("settings.record_shortcut"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isRecording ? .black : .white.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isRecording ? TerminalColors.green.opacity(0.96) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isRecording ? TerminalColors.green.opacity(0.9) : Color.white.opacity(0.10),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help(Text(appLocalized: AppLocalization.string(isRecording ? AppLocalization.runtimeString("settings.stop_recording_shortcut") : AppLocalization.runtimeString("settings.start_recording_shortcut"))))
        .accessibilityLabel(Text(appLocalized: isRecording ? AppLocalization.runtimeString("settings.stop_recording_shortcut") : AppLocalization.runtimeString("settings.start_recording_shortcut")))
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        helperTextKey = nil
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleRecording(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handleRecording(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            helperTextKey = nil
            stopRecording()
            return
        }

        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            shortcut = nil
            helperTextKey = nil
            stopRecording()
            return
        }

        guard let recordedShortcut = GlobalShortcut(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) else {
            helperTextKey = AppLocalization.runtimeString("settings.use_at_least_one_modifier_key")
            return
        }

        applyShortcut(recordedShortcut)
    }

    private func applyShortcut(_ candidate: GlobalShortcut?) {
        if let candidate,
           let owner = LeftFeatureStore.shared.conflictingShortcutOwner(
               for: candidate,
               excludingAction: action
           ) {
            helperTextKey = AppLocalization.format("settings.this_shortcut_is_already_used_by", String(describing: owner))
            NSSound.beep()
            return
        }
        shortcut = candidate
        helperTextKey = nil
        stopRecording()
    }
}

private struct ShortcutIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white.opacity(configuration.isPressed ? 0.76 : 0.88))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.11 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            )
    }
}

private struct AutoRoutePromptsIdleDelayPicker: View {
    @Binding var delay: AutoRoutePromptsIdleDelay

    var body: some View {
        Picker("", selection: $delay) {
            ForEach(AutoRoutePromptsIdleDelay.allCases) { candidate in
                Text(appLocalized: candidate.title).tag(candidate)
            }
        }
        .labelsHidden()
        .accessibilityLabel(Text(appLocalized: "settings.silent_duration"))
        .settingsMenuPicker(width: 132)
    }
}

private struct ClosedNotchTrailingContentPicker: View {
    @Binding var mode: ClosedNotchTrailingContentMode
    var body: some View {
        Picker("", selection: $mode) {
            ForEach(ClosedNotchTrailingContentMode.allCases) { candidate in
                Text(appLocalized: candidate.title)
                    .tag(candidate)
            }
        }
        .labelsHidden()
        .accessibilityLabel(Text(appLocalized: "settings.right_side_content"))
        .settingsMenuPicker(width: 190)
    }
}

private struct FloatingPetSizeModePicker: View {
    @Binding var mode: FloatingPetSizeMode

    var body: some View {
        Picker("", selection: $mode) {
            ForEach(FloatingPetSizeMode.allCases) { candidate in
                Text(appLocalized: candidate.title).tag(candidate)
            }
        }
        .labelsHidden()
        .accessibilityLabel(Text(appLocalized: "settings.mascot_size"))
        .settingsMenuPicker(width: 132)
        .help(AppLocalization.string(mode.subtitle))
    }
}

struct IslandSurfaceModeSelector: View {
    @Binding var mode: IslandSurfaceMode
    var title: String? = AppLocalization.runtimeString("settings.presentation_mode")
    var subtitle: String? = AppLocalization.runtimeString("settings.choose_how_cc_flow_renders_by_default_you")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(appLocalized: title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            if let subtitle {
                Text(appLocalized: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                ForEach(IslandSurfaceMode.allCases) { candidate in
                    IslandSurfaceModeCard(
                        mode: candidate,
                        isSelected: mode == candidate
                    ) {
                        mode = candidate
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

struct IslandSurfaceModeCard: View {
    let mode: IslandSurfaceMode
    let isSelected: Bool
    let action: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(previewBackground)
                        .aspectRatio(7.0 / 3.0, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(previewBorder, lineWidth: 1)
                        )
                        .overlay {
                            IslandSurfaceModePreviewScene(
                                surfaceMode: mode,
                                notchDisplayMode: settings.notchDisplayMode,
                                floatingPetSizeMode: settings.floatingPetSizeMode
                            )
                            .padding(12)
                        }
                }

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appLocalized: mode.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)

                        Text(appLocalized: mode.subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? accentColor : .white.opacity(0.26))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.09 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? accentColor.opacity(0.56) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: isSelected ? accentColor.opacity(0.18) : .clear, radius: 16, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var accentColor: Color {
        switch mode {
        case .notch:
            return Color(red: 0.24, green: 0.72, blue: 0.98)
        case .floatingPet:
            return Color(red: 0.98, green: 0.64, blue: 0.26)
        }
    }

    private var previewBackground: LinearGradient {
        switch mode {
        case .notch:
            return LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.18, blue: 0.30),
                    Color(red: 0.05, green: 0.09, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .floatingPet:
            return LinearGradient(
                colors: [
                    Color(red: 0.27, green: 0.17, blue: 0.08),
                    Color(red: 0.10, green: 0.08, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var previewBorder: Color {
        isSelected ? accentColor.opacity(0.42) : Color.white.opacity(0.10)
    }
}

private struct IslandSurfaceModePreviewScene: View {
    let surfaceMode: IslandSurfaceMode
    let notchDisplayMode: NotchDisplayMode
    let floatingPetSizeMode: FloatingPetSizeMode
    @ObservedObject private var settings = AppSettings.shared
    @State private var isHovered = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.035))

                switch surfaceMode {
                case .notch:
                    notchPreview(in: proxy.size)
                case .floatingPet:
                    floatingPreview(in: proxy.size)
                }
            }
        }
        .environment(\.mascotAnimationsEnabled, isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func notchPreview(in size: CGSize) -> some View {
        let notchWidth = min(max(size.width * 0.9, 112), 168)
        let notchHeight = min(max(size.height * 0.28, 22), 28)

        return VStack(spacing: 0) {
            NotchDisplayPreviewMock(
                mode: notchDisplayMode,
                mascotKind: settings.previewMascotKind,
                width: notchWidth,
                height: notchHeight
            )
            .padding(.top, 10)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Text(appLocalized: "settings.top_cc_flow")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.42))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private func floatingPreview(in size: CGSize) -> some View {
        let mascotSize = 34 * previewScale
        let numberSize = 12 * min(previewScale, 1.14)

        return ZStack(alignment: .bottomTrailing) {
            VStack {
                HStack {
                    Text(appLocalized: "settings.bottom_right_floating")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.46))
                    Spacer()
                }
                Spacer()
            }
            .padding(10)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .frame(width: min(24, size.width * 0.10), height: 2)

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: min(12, size.width * 0.05), height: 2)
                }

                HStack(alignment: .bottom, spacing: 3) {
                    MascotView(
                        kind: settings.previewMascotKind,
                        status: .idle,
                        size: mascotSize
                    )

                    Text("2")
                        .font(.system(size: numberSize, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.26))
                        .offset(y: -1)
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 12)
        }
    }

    private var previewScale: CGFloat {
        switch floatingPetSizeMode {
        case .automatic:
            return 1.08
        case .standard:
            return 1
        case .large:
            return 1.16
        }
    }
}

private struct DisplayPreviewMascotPicker: View {
    private let accessibilityTitleKey = AppLocalization.runtimeString("settings.default_mascot")
    @Binding var kind: MascotKind
    // 从扫描器取动态主题包列表，避免 MascotKind.allCases 只剩内置 claude 一个选项
    @ObservedObject private var scanner = MascotThemeScanner.shared

    var body: some View {
        Picker(selection: $kind) {
            ForEach(scanner.themes) { theme in
                Text(
                    verbatim: AppLocalization.format(
                        "common.pair",
                        AppLocalization.string(theme.manifest.kind?.titleKey ?? "settings.general"),
                        AppLocalization.string(theme.displayName)
                    )
                )
                .tag(MascotKind(themeID: theme.id))
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .accessibilityLabel(Text(verbatim: AppLocalization.string(accessibilityTitleKey)))
        .pickerStyle(.menu)
        .frame(minWidth: 180, alignment: .trailing)
    }
}

private struct FloatingPetPlacementInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized: "settings.floating_pet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Text(appLocalized: "settings.the_floating_pet_appears_near_the_bottom_right")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct NotchDisplayPreviewMock: View {
    let mode: NotchDisplayMode
    let mascotKind: MascotKind
    let width: CGFloat
    let height: CGFloat

    private let actualClosedWidth: CGFloat = 274
    private let actualSideWidth: CGFloat = 30
    private let actualCenterWidth: CGFloat = 186

    var body: some View {
        let sideSlotWidth = width * (actualSideWidth / actualClosedWidth)
        let centerSlotWidth = width * (actualCenterWidth / actualClosedWidth)

        return HStack(spacing: 0) {
            HStack {
                MascotView(kind: mascotKind, status: .idle, size: 14)
            }
            .frame(width: sideSlotWidth, alignment: .center)

            HStack {
                if mode == .detailed {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 14)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.white.opacity(0.76))
                                .frame(width: 42, height: 3)
                                .padding(.leading, 8)
                        }
                        .frame(width: centerSlotWidth * 0.92, alignment: .center)
                } else {
                    Color.clear
                        .frame(width: centerSlotWidth * 0.92)
                }
            }
            .frame(width: centerSlotWidth, alignment: .center)

            HStack {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 18, height: 14)
                    .overlay(
                        Text("3")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    )
            }
            .frame(width: sideSlotWidth, alignment: .center)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(Color.black.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
    }
}

private struct SettingsStatusLine: View {
    let title: String
    let subtitle: String?
    let status: String
    let statusColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 16) {
                    Text(appLocalized: title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer(minLength: 12)

                    HStack(spacing: 10) {
                        Text(appLocalized: status)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(statusColor)

                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                if let subtitle {
                    Text(appLocalized: subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SoundEventSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        SettingsSectionCard(title: title) {
            VStack(spacing: 0) {
                content
            }
        }
    }
}

private struct SoundEventTextBlock: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(appLocalized: title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.88)

            Text(appLocalized: subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }
}

private struct SoundPreviewButton: View {
    let isEnabled: Bool
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.30, weight: .bold))
                .foregroundColor(.white.opacity(isEnabled ? 0.86 : 0.32))
                .offset(x: 1)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isEnabled ? 0.075 : 0.025))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(isEnabled ? 0.13 : 0.05), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help("settings.preview")
    }
}

private struct SoundControlCluster<PickerContent: View>: View {
    @Binding var isEnabled: Bool
    let pickerWidth: CGFloat
    let preview: () -> Void
    @ViewBuilder let picker: PickerContent

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            picker
                .settingsMenuPicker(width: pickerWidth)
                .disabled(!isEnabled)
                .frame(width: pickerWidth, alignment: .trailing)

            SoundPreviewButton(isEnabled: isEnabled, action: preview)

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .settingsCompactSwitch(scale: 0.88)
                .frame(width: 36, alignment: .center)
        }
        .frame(width: pickerWidth + 80, alignment: .trailing)
    }
}

private struct SoundEventSettingsLine: View {
    let event: NotificationEvent
    @Binding var isEnabled: Bool
    @Binding var selectedSound: NotificationSound
    let preview: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            SoundEventTextBlock(title: event.title, subtitle: event.subtitle)

            Spacer(minLength: 24)

            SoundControlCluster(isEnabled: $isEnabled, pickerWidth: 190, preview: preview) {
                Picker(event.title, selection: $selectedSound) {
                    ForEach(NotificationSound.allCases, id: \.self) { sound in
                        Text(sound.rawValue).tag(sound)
                    }
                }
                .id(selectedSound)
                .labelsHidden()
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }
}

private struct SoundPackEventLine: View {
    let event: NotificationEvent
    @Binding var isEnabled: Bool
    let preview: () -> Void

    private var categorySummary: String {
        event.cespCategories.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                SoundEventTextBlock(title: event.title, subtitle: event.subtitle)

                Text(appLocalized: categorySummary)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer(minLength: 24)

            HStack(spacing: 8) {
                SoundPreviewButton(isEnabled: isEnabled, action: preview)

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .settingsCompactSwitch(scale: 0.88)
                    .frame(width: 36, alignment: .center)
            }
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }
}
