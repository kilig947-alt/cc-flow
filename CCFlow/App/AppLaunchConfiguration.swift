import AppKit
import Darwin
import Foundation

struct AppLaunchConfiguration: Equatable {
    let isUITesting: Bool
    let isRunningTests: Bool
    let shouldInstallIntegrations: Bool
    let shouldCreateNotchWindow: Bool
    let shouldObserveScreens: Bool
    let shouldEnforceSingleInstance: Bool
    let shouldPresentSettingsWindowOnLaunch: Bool
    let activationPolicy: NSApplication.ActivationPolicy

    init(
        environment: [String: String] = Foundation.ProcessInfo.processInfo.environment,
        isDebuggerAttached _: Bool = Self.detectDebuggerAttached()
    ) {
        let isUITesting = Self.flag("UI_TEST_MODE", environment: environment)
        let isRunningUnderXCTest = environment["XCTestConfigurationFilePath"] != nil
        let shouldShowSettings = Self.flag("SHOW_SETTINGS_ON_LAUNCH", environment: environment)
        let shouldAllowMultipleInstances = Self.flag("ALLOW_MULTIPLE_INSTANCES", environment: environment)
        let isRunningTests = isUITesting || isRunningUnderXCTest

        self.isUITesting = isUITesting
        self.isRunningTests = isRunningTests
        self.shouldInstallIntegrations = !isRunningTests
        self.shouldCreateNotchWindow = !isRunningTests
        self.shouldObserveScreens = !isRunningTests
        self.shouldEnforceSingleInstance = !isRunningTests && !shouldAllowMultipleInstances
        self.shouldPresentSettingsWindowOnLaunch = isUITesting || shouldShowSettings
        self.activationPolicy = .regular
    }

    private static func flag(_ suffix: String, environment: [String: String]) -> Bool {
        environment["CC_FLOW_\(suffix)"] == "1"
            || environment["TRAE_FLOW_\(suffix)"] == "1"
            || environment["ISLAND_\(suffix)"] == "1"
    }

    private static func detectDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        let result = sysctl(&name, u_int(name.count), &info, &size, nil, 0)
        guard result == 0 else {
            return false
        }

        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}

struct AppLaunchFlow: Equatable {
    let shouldStartMonitoringImmediately: Bool
    let shouldPresentSurfaceModeOnboarding: Bool
    let shouldCreateInitialIslandWindow: Bool
    let shouldPresentSettingsWindowImmediately: Bool
    let shouldPresentSettingsWindowAfterOnboarding: Bool

    init(
        configuration: AppLaunchConfiguration,
        presentationModeOnboardingPending: Bool = false
    ) {
        let shouldPresentOnboarding = false

        self.shouldStartMonitoringImmediately = !configuration.isRunningTests
        self.shouldPresentSurfaceModeOnboarding = shouldPresentOnboarding
        self.shouldCreateInitialIslandWindow = configuration.shouldCreateNotchWindow
        self.shouldPresentSettingsWindowImmediately = configuration.shouldPresentSettingsWindowOnLaunch
        self.shouldPresentSettingsWindowAfterOnboarding = false
    }
}

struct NotchDetachmentHintExperience {
    private static let preparedVersionDefaultsKey = "notchDetachmentHintExperiencePreparedVersion"

    static func prepareForLaunch(
        defaults: UserDefaults = .standard,
        previousVersion: String?,
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        markHintsPending: (() -> Void)? = nil
    ) {
        let normalizedCurrentVersion = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCurrentVersion.isEmpty else {
            return
        }

        let preparedVersion = defaults.string(forKey: preparedVersionDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard preparedVersion.isEmpty else {
            return
        }

        defer {
            defaults.set(normalizedCurrentVersion, forKey: preparedVersionDefaultsKey)
        }

        let normalizedPreviousVersion = previousVersion?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if normalizedPreviousVersion.isEmpty || normalizedPreviousVersion == normalizedCurrentVersion {
            return
        }

        if let markHintsPending {
            markHintsPending()
        } else {
            defaults.set(true, forKey: AppSettingsDefaultKeys.notchDetachmentHintPending)
            defaults.set(true, forKey: AppSettingsDefaultKeys.floatingPetSettingsHintPending)
        }
    }
}
