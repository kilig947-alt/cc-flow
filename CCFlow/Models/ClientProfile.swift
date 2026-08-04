import Darwin
import Foundation

enum UserHomeDirectoryResolver {
    nonisolated static var hookConfigurationHomeDirectory: URL {
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// `$HOME/.codex/pets/` —— codex CLI 已安装宠物目录
    /// 与 codex 共享同一目录约定：每个子目录 `<pet-id>/` 下放 `pet.json` 与 sprite sheet
    nonisolated static var codexPetsDirectory: URL {
        hookConfigurationHomeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("pets", isDirectory: true)
    }

    /// `$HOME/.cc-flow/pets/` —— CC FLOW 用户自装宠物目录
    /// 优先级高于 codex 已安装主题包，用于让用户在不污染 codex 目录的前提下覆盖同名主题包
    nonisolated static var ccFlowPetsDirectory: URL {
        hookConfigurationHomeDirectory
            .appendingPathComponent(".cc-flow", isDirectory: true)
            .appendingPathComponent("pets", isDirectory: true)
    }
}

enum HookProtocolFamily: Sendable {
    case claudeHooks
    case codexHooks
    case opencodePlugin
    case traeHooks
    case antigravityHooks

    // Keep explicit raw-value decoding stable for persisted profile metadata.
    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "claudehooks": self = .claudeHooks
        case "codexhooks": self = .codexHooks
        case "opencodeplugin": self = .opencodePlugin
        case "traehooks": self = .traeHooks
        case "antigravityhooks": self = .antigravityHooks
        default: return nil
        }
    }
}

enum SessionClientBrand: String, Codable, Equatable, Sendable {
    case claude
    case codex
    case opencode
    case trae
    case antigravity
    case neutral
}

enum SessionAssistantLabelMode: String, Sendable {
    case providerDisplayName
    case badgeLabel
}

enum HookInstallEntryTemplate: Sendable {
    case plain
    case matcher(String)
}

enum ManagedHookInstallationKind: Sendable, Equatable {
    case jsonHooks
    case antigravityHooks
    case pluginFile
    case pluginDirectory
    case hookDirectory
    case tomlHooks
}

struct HookInstallEventDescriptor: Sendable {
    let name: String
    let templates: [HookInstallEntryTemplate]
    let timeout: Int?

    init(name: String, templates: [HookInstallEntryTemplate], timeout: Int? = nil) {
        self.name = name
        self.templates = templates
        self.timeout = timeout
    }

    nonisolated var category: HookInstallEventCategory {
        HookInstallEventCategory.category(forEventName: name)
    }
}

enum HookInstallEventCategory: String, CaseIterable, Sendable, Identifiable {
    case approvals
    case notifications
    case lifecycle
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .approvals: return "审批"
        case .notifications: return "通知"
        case .lifecycle: return "生命周期"
        case .activity: return "活动追踪"
        }
    }

    var subtitle: String {
        switch self {
        case .approvals: return "工具调用审批与权限请求，可能需要用户回应"
        case .notifications: return "用户提示与通知事件"
        case .lifecycle: return "会话开始/结束与子任务事件"
        case .activity: return "工具完成、压缩等后台事件"
        }
    }

    var iconSymbolName: String {
        switch self {
        case .approvals: return "checkmark.shield.fill"
        case .notifications: return "bell.fill"
        case .lifecycle: return "circle.lefthalf.filled"
        case .activity: return "waveform.path"
        }
    }

    static func category(forEventName name: String) -> HookInstallEventCategory {
        switch name {
        case "PreToolUse", "PermissionRequest":
            return .approvals
        case "Notification", "UserPromptSubmit", "userPromptSubmitted":
            return .notifications
        case "SessionStart", "SessionEnd", "Stop", "SubagentStart", "SubagentStop",
             "BeforeAgent", "AfterAgent",
             "sessionStart", "sessionEnd", "agentStop", "subagentStop",
             "command:new", "command:reset", "command:stop":
            return .lifecycle
        case "PostToolUse", "PostToolUseFailure", "PreCompact", "PreCompress",
             "BeforeTool", "AfterTool",
             "preToolUse", "postToolUse", "errorOccurred",
             "message:received", "message:sent",
             "session:compact:before", "session:compact:after", "session:patch":
            return .activity
        default:
            return .activity
        }
    }
}

struct HookInstallSelection: Sendable, Equatable {
    var enabledEventNames: Set<String>

    static func defaultSelection(for profile: ManagedHookClientProfile) -> HookInstallSelection {
        HookInstallSelection(enabledEventNames: Set(profile.events.map(\.name)))
    }

    func filteredEvents(for profile: ManagedHookClientProfile) -> [HookInstallEventDescriptor] {
        profile.events.filter { enabledEventNames.contains($0.name) }
    }

    var isEmpty: Bool { enabledEventNames.isEmpty }
}

struct ManagedHookClientProfile: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let installationKind: ManagedHookInstallationKind
    let alwaysVisibleInSettings: Bool
    let logoAssetName: String?
    let prefersBundledLogoOverAppIcon: Bool
    let localAppBundleIdentifiers: [String]
    let iconSymbolName: String
    let configurationRelativePaths: [String]
    let activationConfigurationRelativePath: String?
    let activationEntryName: String?
    let bridgeSource: String
    let bridgeExtraArguments: [String]
    let defaultEnabled: Bool
    let brand: SessionClientBrand
    let events: [HookInstallEventDescriptor]
    let supportsHookIntegration: Bool

    init(
        id: String,
        title: String,
        subtitle: String,
        installationKind: ManagedHookInstallationKind = .jsonHooks,
        alwaysVisibleInSettings: Bool = false,
        logoAssetName: String? = nil,
        prefersBundledLogoOverAppIcon: Bool = false,
        localAppBundleIdentifiers: [String] = [],
        iconSymbolName: String,
        configurationRelativePath: String,
        activationConfigurationRelativePath: String? = nil,
        activationEntryName: String? = nil,
        bridgeSource: String,
        bridgeExtraArguments: [String],
        defaultEnabled: Bool,
        brand: SessionClientBrand,
        events: [HookInstallEventDescriptor],
        supportsHookIntegration: Bool = true
    ) {
        self.init(
            id: id,
            title: title,
            subtitle: subtitle,
            installationKind: installationKind,
            alwaysVisibleInSettings: alwaysVisibleInSettings,
            logoAssetName: logoAssetName,
            prefersBundledLogoOverAppIcon: prefersBundledLogoOverAppIcon,
            localAppBundleIdentifiers: localAppBundleIdentifiers,
            iconSymbolName: iconSymbolName,
            configurationRelativePaths: [configurationRelativePath],
            activationConfigurationRelativePath: activationConfigurationRelativePath,
            activationEntryName: activationEntryName,
            bridgeSource: bridgeSource,
            bridgeExtraArguments: bridgeExtraArguments,
            defaultEnabled: defaultEnabled,
            brand: brand,
            events: events,
            supportsHookIntegration: supportsHookIntegration
        )
    }

    init(
        id: String,
        title: String,
        subtitle: String,
        installationKind: ManagedHookInstallationKind = .jsonHooks,
        alwaysVisibleInSettings: Bool = false,
        logoAssetName: String? = nil,
        prefersBundledLogoOverAppIcon: Bool = false,
        localAppBundleIdentifiers: [String] = [],
        iconSymbolName: String,
        configurationRelativePaths: [String],
        activationConfigurationRelativePath: String? = nil,
        activationEntryName: String? = nil,
        bridgeSource: String,
        bridgeExtraArguments: [String],
        defaultEnabled: Bool,
        brand: SessionClientBrand,
        events: [HookInstallEventDescriptor],
        supportsHookIntegration: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.installationKind = installationKind
        self.alwaysVisibleInSettings = alwaysVisibleInSettings
        self.logoAssetName = logoAssetName
        self.prefersBundledLogoOverAppIcon = prefersBundledLogoOverAppIcon
        self.localAppBundleIdentifiers = localAppBundleIdentifiers
        self.iconSymbolName = iconSymbolName
        self.configurationRelativePaths = configurationRelativePaths
        self.activationConfigurationRelativePath = activationConfigurationRelativePath
        self.activationEntryName = activationEntryName
        self.bridgeSource = bridgeSource
        self.bridgeExtraArguments = bridgeExtraArguments
        self.defaultEnabled = defaultEnabled
        self.brand = brand
        self.events = events
        self.supportsHookIntegration = supportsHookIntegration
    }

    nonisolated var configurationURLs: [URL] {
        configurationURLs(homeDirectory: UserHomeDirectoryResolver.hookConfigurationHomeDirectory)
    }

    nonisolated var primaryConfigurationURL: URL {
        configurationURLs[0]
    }

    nonisolated var activationConfigurationURL: URL? {
        guard let activationConfigurationRelativePath else {
            return nil
        }
        return Self.resolveConfigurationURL(relativePath: activationConfigurationRelativePath)
    }

    nonisolated func configurationURLs(homeDirectory: URL) -> [URL] {
        configurationRelativePaths.map {
            Self.resolveConfigurationURL(relativePath: $0, homeDirectory: homeDirectory)
        }
    }

    nonisolated func primaryConfigurationURL(homeDirectory: URL) -> URL {
        configurationURLs(homeDirectory: homeDirectory)[0]
    }

    nonisolated func activationConfigurationURL(homeDirectory: URL) -> URL? {
        guard let activationConfigurationRelativePath else {
            return nil
        }
        return Self.resolveConfigurationURL(
            relativePath: activationConfigurationRelativePath,
            homeDirectory: homeDirectory
        )
    }

    nonisolated var supportsEventSelection: Bool {
        guard !events.isEmpty else { return false }
        switch installationKind {
        case .jsonHooks, .antigravityHooks:
            return true
        case .pluginFile, .pluginDirectory, .hookDirectory, .tomlHooks:
            return false
        }
    }

    nonisolated var availableEventCategories: [HookInstallEventCategory] {
        let present = Set(events.map(\.category))
        return HookInstallEventCategory.allCases.filter { present.contains($0) }
    }

    nonisolated func events(in category: HookInstallEventCategory) -> [HookInstallEventDescriptor] {
        events.filter { $0.category == category }
    }

    nonisolated var reinstallDescriptionFormat: String {
        switch installationKind {
        case .jsonHooks:
            return "这会重新写入 %@ 的 CC FLOW hooks 配置，并保留其他非 CC FLOW hooks。"
        case .antigravityHooks:
            return "这会重新写入 %@ 的 CC FLOW Hook 组，并保留其他 Hook 组。"
        case .pluginFile:
            return "这会重新生成 %@ 的 CC FLOW 插件文件，并覆盖旧的 CC FLOW 托管版本。"
        case .pluginDirectory:
            return "这会重新生成 %@ 的 CC FLOW 插件目录，并覆盖旧的 CC FLOW 托管版本。"
        case .hookDirectory:
            return "这会重新生成 %@ 的 CC FLOW hook 目录。"
        case .tomlHooks:
            return "这会重新写入 %@ 的 CC FLOW hooks TOML 配置，并保留其他非 CC FLOW 设置。"
        }
    }

    nonisolated private static func resolveConfigurationURL(relativePath: String) -> URL {
        resolveConfigurationURL(
            relativePath: relativePath,
            homeDirectory: UserHomeDirectoryResolver.hookConfigurationHomeDirectory
        )
    }

    nonisolated private static func resolveConfigurationURL(
        relativePath: String,
        homeDirectory: URL
    ) -> URL {
        return relativePath
            .split(separator: "/")
            .reduce(homeDirectory) { partialURL, component in
                partialURL.appendingPathComponent(String(component))
            }
    }
}

struct SessionClientProfile: Identifiable, Sendable {
    let id: String
    let provider: SessionProvider
    let family: HookProtocolFamily
    let kind: SessionClientKind
    let displayName: String
    let assistantLabelMode: SessionAssistantLabelMode
    let brand: SessionClientBrand
    let defaultBundleIdentifier: String?
    let defaultOrigin: String?
    let recognizedKinds: Set<String>
    let exactAliases: Set<String>
    let keywordAliases: Set<String>
    let bundleIdentifiers: Set<String>

    nonisolated func matchScore(
        explicitKind: String?,
        explicitName: String?,
        explicitBundleIdentifier: String?,
        terminalBundleIdentifier: String?,
        origin: String?,
        originator: String?,
        threadSource: String?,
        processName: String?
    ) -> Int {
        var score = 0

        if let normalizedKind = Self.normalize(explicitKind), recognizedKinds.contains(normalizedKind) {
            score += 100
        }

        let bundleCandidates = [explicitBundleIdentifier, terminalBundleIdentifier]
            .compactMap(Self.normalize)
        if bundleCandidates.contains(where: bundleIdentifiers.contains) {
            score += 90
        }

        let exactCandidates = [explicitName, originator, processName, origin, threadSource]
            .compactMap(Self.normalize)
        if exactCandidates.contains(where: exactAliases.contains) {
            score += 60
        }

        if exactCandidates.contains(where: containsKeywordAlias(_:)) {
            score += 20
        }

        return score
    }

    nonisolated func matchesLabelAlias(_ rawValue: String) -> Bool {
        guard let normalized = Self.normalize(rawValue) else {
            return false
        }
        return exactAliases.contains(normalized)
            || recognizedKinds.contains(normalized)
            || containsKeywordAlias(normalized)
    }

    nonisolated func labelAliasScore(_ rawValue: String) -> Int {
        guard let normalized = Self.normalize(rawValue) else {
            return 0
        }
        if exactAliases.contains(normalized) || recognizedKinds.contains(normalized) {
            return 2
        }
        if containsKeywordAlias(normalized) {
            return 1
        }
        return 0
    }

    nonisolated private func containsKeywordAlias(_ normalizedValue: String) -> Bool {
        keywordAliases.contains { normalizedValue.contains($0) }
    }

    nonisolated private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

enum ClientProfileRegistry {
    // 四个 managedHookProfile 覆盖全部四个 TRAE 变体，每个变体写入独立的 hooks.json：
    // - trae-hooks      覆盖 Trae      （com.trae.app），      写入 ~/.trae/hooks.json
    // - trae-cn-hooks   覆盖 Trae CN   （cn.trae.app），       写入 ~/.trae-cn/hooks.json
    // - trae-solo-hooks 覆盖 TRAE SOLO （com.trae.solo.app）， 写入 ~/.trae-solo/hooks.json
    // - trae-solo-cn-hooks 覆盖 TRAE SOLO CN（cn.trae.solo.app），写入 ~/.trae-solo-cn/hooks.json
    // TRAE SOLO / TRAE SOLO CN 即 Spec 中的 TRAE Work / TRAE Work CN（本地 .app 名为 TRAE SOLO）。
    // 变体区分通过 bridge 命令的 `--client-name` 与终端 bundle ID 完成，不再使用 `--variant` 参数。
    nonisolated static let managedHookProfiles: [ManagedHookClientProfile] = [
        ManagedHookClientProfile(
            id: "claude-hooks",
            title: "Claude Code",
            subtitle: "管理 ~/.claude/settings.json，接收 Claude Code 生命周期与审批事件",
            alwaysVisibleInSettings: true,
            logoAssetName: "ClaudeCodeLogo",
            prefersBundledLogoOverAppIcon: true,
            iconSymbolName: "sparkles",
            configurationRelativePath: ".claude/settings.json",
            bridgeSource: "claude",
            bridgeExtraArguments: [
                "--client-kind", "claude-code",
                "--client-name", "Claude Code",
                "--client-originator", "Claude Code"
            ],
            defaultEnabled: true,
            brand: .claude,
            events: [
                HookInstallEventDescriptor(name: "SessionStart", templates: [.plain]),
                HookInstallEventDescriptor(name: "UserPromptSubmit", templates: [.plain]),
                HookInstallEventDescriptor(name: "PermissionRequest", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PreToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PostToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PostToolUseFailure", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Notification", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PreCompact", templates: [.plain]),
                HookInstallEventDescriptor(name: "SubagentStart", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "SubagentStop", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Stop", templates: [.plain]),
                HookInstallEventDescriptor(name: "SessionEnd", templates: [.plain]),
            ],
            supportsHookIntegration: true
        ),
        ManagedHookClientProfile(
            id: "codex-hooks",
            title: "Codex",
            subtitle: "管理 ~/.codex/hooks.json，接收 Codex 生命周期与审批事件",
            alwaysVisibleInSettings: true,
            logoAssetName: "OpenAILogo",
            prefersBundledLogoOverAppIcon: true,
            iconSymbolName: "terminal.fill",
            configurationRelativePath: ".codex/hooks.json",
            bridgeSource: "codex",
            bridgeExtraArguments: [
                "--client-kind", "codex",
                "--client-name", "Codex",
                "--client-originator", "Codex"
            ],
            defaultEnabled: true,
            brand: .codex,
            events: [
                HookInstallEventDescriptor(name: "SessionStart", templates: [.matcher("startup|resume|clear|compact")]),
                HookInstallEventDescriptor(name: "UserPromptSubmit", templates: [.plain]),
                HookInstallEventDescriptor(name: "PermissionRequest", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PreToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PostToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PreCompact", templates: [.matcher("manual|auto")]),
                HookInstallEventDescriptor(name: "PostCompact", templates: [.matcher("manual|auto")]),
                HookInstallEventDescriptor(name: "SubagentStart", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "SubagentStop", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Stop", templates: [.plain]),
            ],
            supportsHookIntegration: true
        ),
        ManagedHookClientProfile(
            id: "opencode-plugin",
            title: "OpenCode",
            subtitle: "管理 ~/.config/opencode/plugins/cc-flow.ts，接收 OpenCode 会话、工具、审批与提问事件",
            installationKind: .pluginFile,
            alwaysVisibleInSettings: true,
            iconSymbolName: "chevron.left.forwardslash.chevron.right",
            configurationRelativePath: ".config/opencode/plugins/cc-flow.ts",
            activationConfigurationRelativePath: ".config/opencode/opencode.json",
            bridgeSource: "opencode",
            bridgeExtraArguments: [
                "--client-kind", "opencode",
                "--client-name", "OpenCode",
                "--client-originator", "OpenCode"
            ],
            defaultEnabled: false,
            brand: .opencode,
            events: [],
            supportsHookIntegration: true
        ),
        ManagedHookClientProfile(
            id: "antigravity-hooks",
            title: "Antigravity",
            subtitle: "管理 ~/.gemini/config/hooks.json，接收 Antigravity 工具、调用与停止事件",
            installationKind: .antigravityHooks,
            alwaysVisibleInSettings: false,
            localAppBundleIdentifiers: ["com.google.antigravity"],
            iconSymbolName: "atom",
            configurationRelativePath: ".gemini/config/hooks.json",
            bridgeSource: "antigravity",
            bridgeExtraArguments: [
                "--client-kind", "antigravity",
                "--client-name", "Antigravity",
                "--client-bundle-id", "com.google.antigravity",
                "--client-originator", "Antigravity"
            ],
            defaultEnabled: false,
            brand: .antigravity,
            events: [
                HookInstallEventDescriptor(name: "SessionStart", templates: [.plain]),
                HookInstallEventDescriptor(name: "UserPromptSubmit", templates: [.plain]),
                HookInstallEventDescriptor(name: "PermissionRequest", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PreToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PostToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PostToolUseFailure", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Notification", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PreCompact", templates: [.plain]),
                HookInstallEventDescriptor(name: "SubagentStart", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "SubagentStop", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Stop", templates: [.plain]),
                HookInstallEventDescriptor(name: "SessionEnd", templates: [.plain]),
            ],
            supportsHookIntegration: true
        ),
        ManagedHookClientProfile(
            id: "trae-hooks",
            title: "Trae",
            subtitle: "管理 ~/.trae/hooks.json，按 Trae 官方 Hook 协议接入 Trae",
            alwaysVisibleInSettings: false,
            localAppBundleIdentifiers: [
                "com.trae.app"
            ],
            iconSymbolName: "bolt.square.fill",
            configurationRelativePath: ".trae/hooks.json",
            bridgeSource: "trae",
            bridgeExtraArguments: [
                "--client-kind", "trae",
                "--client-name", "Trae",
                "--client-bundle-id", "com.trae.app",
                "--client-originator", "Trae"
            ],
            defaultEnabled: false,
            brand: .trae,
            events: [
                HookInstallEventDescriptor(name: "SessionStart", templates: [.plain]),
                HookInstallEventDescriptor(name: "UserPromptSubmit", templates: [.plain]),
                HookInstallEventDescriptor(name: "PreToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PostToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Notification", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Stop", templates: [.plain]),
            ],
            supportsHookIntegration: true
        ),
        ManagedHookClientProfile(
            id: "trae-cn-hooks",
            title: "Trae CN",
            subtitle: "管理 ~/.trae-cn/hooks.json，按 Trae 官方 Hook 协议接入 Trae CN",
            alwaysVisibleInSettings: false,
            localAppBundleIdentifiers: [
                "cn.trae.app"
            ],
            iconSymbolName: "bolt.square.fill",
            configurationRelativePath: ".trae-cn/hooks.json",
            bridgeSource: "trae",
            bridgeExtraArguments: [
                "--client-kind", "trae",
                "--client-name", "Trae CN",
                "--client-bundle-id", "cn.trae.app",
                "--client-originator", "Trae CN"
            ],
            defaultEnabled: false,
            brand: .trae,
            events: [
                HookInstallEventDescriptor(name: "SessionStart", templates: [.plain]),
                HookInstallEventDescriptor(name: "UserPromptSubmit", templates: [.plain]),
                HookInstallEventDescriptor(name: "PreToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PostToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Notification", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Stop", templates: [.plain]),
            ],
            supportsHookIntegration: true
        ),
        ManagedHookClientProfile(
            id: "trae-solo-hooks",
            title: "TRAE Work",
            subtitle: "检测 TRAE Work 会话；客户端当前未提供可管理的官方 Hooks 配置",
            alwaysVisibleInSettings: false,
            localAppBundleIdentifiers: [
                "com.trae.solo.app"
            ],
            iconSymbolName: "bolt.square.fill",
            configurationRelativePath: ".trae-solo/hooks.json",
            bridgeSource: "trae",
            bridgeExtraArguments: [
                "--client-kind", "trae",
                "--client-name", "TRAE Work",
                "--client-bundle-id", "com.trae.solo.app",
                "--client-originator", "TRAE SOLO"
            ],
            defaultEnabled: false,
            brand: .trae,
            events: [
                HookInstallEventDescriptor(name: "SessionStart", templates: [.plain]),
                HookInstallEventDescriptor(name: "UserPromptSubmit", templates: [.plain]),
                HookInstallEventDescriptor(name: "PreToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PostToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Notification", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Stop", templates: [.plain]),
            ],
            supportsHookIntegration: false
        ),
        ManagedHookClientProfile(
            id: "trae-solo-cn-hooks",
            title: "TRAE Work CN",
            subtitle: "检测 TRAE Work CN 会话；客户端当前未提供可管理的官方 Hooks 配置",
            alwaysVisibleInSettings: false,
            localAppBundleIdentifiers: [
                "cn.trae.solo.app"
            ],
            iconSymbolName: "bolt.square.fill",
            configurationRelativePath: ".trae-solo-cn/hooks.json",
            bridgeSource: "trae",
            bridgeExtraArguments: [
                "--client-kind", "trae",
                "--client-name", "TRAE Work CN",
                "--client-bundle-id", "cn.trae.solo.app",
                "--client-originator", "TRAE SOLO CN"
            ],
            defaultEnabled: false,
            brand: .trae,
            events: [
                HookInstallEventDescriptor(name: "SessionStart", templates: [.plain]),
                HookInstallEventDescriptor(name: "UserPromptSubmit", templates: [.plain]),
                HookInstallEventDescriptor(name: "PreToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "PostToolUse", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Notification", templates: [.matcher("*")]),
                HookInstallEventDescriptor(name: "Stop", templates: [.plain]),
            ],
            supportsHookIntegration: false
        ),
    ]

    // 与 TRAEFLOW 对齐：单个 runtimeProfile（id: "trae"）覆盖全部 TRAE 变体。
    // 变体区分（Trae / Trae CN / SOLO / Work）由 `clientInfo.bundleIdentifier` 经
    // `TraeVariant.fromBundleIdentifier` 解析，不再依赖 runtimeProfile id。
    nonisolated static let runtimeProfiles: [SessionClientProfile] = [
        SessionClientProfile(
            id: "claude",
            provider: .claude,
            family: .claudeHooks,
            kind: .claudeCode,
            displayName: "Claude Code",
            assistantLabelMode: .providerDisplayName,
            brand: .claude,
            defaultBundleIdentifier: nil,
            defaultOrigin: "terminal",
            recognizedKinds: ["claude", "claude-code", "claudecode"],
            exactAliases: ["claude", "claude-code", "claude code", "claudecode"],
            keywordAliases: ["claude"],
            bundleIdentifiers: []
        ),
        SessionClientProfile(
            id: "codex",
            provider: .codex,
            family: .codexHooks,
            kind: .codex,
            displayName: "Codex",
            assistantLabelMode: .providerDisplayName,
            brand: .codex,
            defaultBundleIdentifier: nil,
            defaultOrigin: "terminal",
            recognizedKinds: ["codex", "codex-cli", "codex-app"],
            exactAliases: ["codex", "codex-cli", "codex cli", "codex-app", "codex app"],
            keywordAliases: ["codex"],
            bundleIdentifiers: []
        ),
        SessionClientProfile(
            id: "opencode",
            provider: .opencode,
            family: .opencodePlugin,
            kind: .opencode,
            displayName: "OpenCode",
            assistantLabelMode: .badgeLabel,
            brand: .opencode,
            defaultBundleIdentifier: nil,
            defaultOrigin: "terminal",
            recognizedKinds: ["opencode", "open-code"],
            exactAliases: ["opencode", "open code", "open-code"],
            keywordAliases: ["opencode"],
            bundleIdentifiers: []
        ),
        SessionClientProfile(
            id: "antigravity",
            provider: .antigravity,
            family: .antigravityHooks,
            kind: .antigravity,
            displayName: "Antigravity",
            assistantLabelMode: .providerDisplayName,
            brand: .antigravity,
            defaultBundleIdentifier: "com.google.antigravity",
            defaultOrigin: "ide",
            recognizedKinds: ["antigravity", "antigravity-ide"],
            exactAliases: ["antigravity", "antigravity ide", "antigravity-ide"],
            keywordAliases: ["antigravity"],
            bundleIdentifiers: ["com.google.antigravity"]
        ),
        SessionClientProfile(
            id: "trae",
            provider: .trae,
            family: .traeHooks,
            kind: .trae,
            displayName: "Trae",
            assistantLabelMode: .badgeLabel,
            brand: .trae,
            defaultBundleIdentifier: nil,
            defaultOrigin: "ide",
            recognizedKinds: [
                "trae", "trae-ide", "trae ide", "trae-ai", "trae ai",
                "trae-cn", "trae-cn-ide", "trae cn", "trae-cn-ai", "trae cn ai",
                "trae-solo", "trae solo",
                "trae-solo-cn", "trae solo cn",
                "trae-work", "trae work",
                "trae-work-cn", "trae work cn"
            ],
            exactAliases: [
                "trae", "trae-ide", "trae ide", "trae-ai", "trae ai",
                "trae-cn", "trae-cn-ide", "trae cn", "trae-cn-ai", "trae cn ai",
                "trae-solo", "trae solo",
                "trae-solo-cn", "trae solo cn",
                "trae-work", "trae work",
                "trae-work-cn", "trae work cn"
            ],
            keywordAliases: ["trae"],
            bundleIdentifiers: [
                "com.trae.app",
                "cn.trae.app",
                "com.trae.solo.app",
                "cn.trae.solo.app"
            ]
        ),
    ]

    nonisolated static func managedHookProfile(id: String) -> ManagedHookClientProfile? {
        managedHookProfiles.first { $0.id == id }
    }

    nonisolated static func runtimeProfile(id: String?) -> SessionClientProfile? {
        guard let id else { return nil }
        return runtimeProfiles.first { $0.id == id }
    }

    nonisolated static func defaultManagedHookProfileIDs() -> Set<String> {
        Set(managedHookProfiles.filter(\.defaultEnabled).map(\.id))
    }

    nonisolated static func defaultRuntimeProfile(for provider: SessionProvider, kind: SessionClientKind? = nil) -> SessionClientProfile? {
        switch provider {
        case .claude: return runtimeProfile(id: "claude")
        case .codex: return runtimeProfile(id: "codex")
        case .opencode: return runtimeProfile(id: "opencode")
        case .trae: return runtimeProfile(id: "trae")
        case .antigravity: return runtimeProfile(id: "antigravity")
        }
    }

    nonisolated static func matchRuntimeProfile(
        provider: SessionProvider,
        explicitKind: String?,
        explicitName: String?,
        explicitBundleIdentifier: String?,
        terminalBundleIdentifier: String?,
        origin: String?,
        originator: String?,
        threadSource: String?,
        processName: String?
    ) -> SessionClientProfile? {
        (
            runtimeProfiles
            .filter { $0.provider == provider }
            .map { profile in
                (
                    profile: profile,
                    score: profile.matchScore(
                        explicitKind: explicitKind,
                        explicitName: explicitName,
                        explicitBundleIdentifier: explicitBundleIdentifier,
                        terminalBundleIdentifier: terminalBundleIdentifier,
                        origin: origin,
                        originator: originator,
                        threadSource: threadSource,
                        processName: processName
                    )
                )
            }
            .filter { $0.score > 0 }
            .max { lhs, rhs in lhs.score < rhs.score }
        )?.profile
    }

    nonisolated static func canonicalDisplayName(
        for rawValue: String,
        provider: SessionProvider,
        kind: SessionClientKind
    ) -> String? {
        let profiles = runtimeProfiles.filter { $0.provider == provider || $0.kind == kind }
        return profiles
            .map { profile in
                (profile: profile, score: profile.labelAliasScore(rawValue))
            }
            .filter { $0.score > 0 }
            .max { lhs, rhs in lhs.score < rhs.score }?
            .profile
            .displayName
    }
}
