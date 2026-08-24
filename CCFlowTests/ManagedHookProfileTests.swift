import XCTest
@testable import CC_FLOW

final class ManagedHookProfileTests: XCTestCase {
    func testClaudeAndCodexAreDefaultProfilesWhileTraeIsOptional() throws {
        let claude = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "claude-hooks"))
        let codex = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "codex-hooks"))
        let trae = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "trae-hooks"))

        XCTAssertTrue(claude.defaultEnabled)
        XCTAssertTrue(claude.alwaysVisibleInSettings)
        XCTAssertTrue(codex.defaultEnabled)
        XCTAssertTrue(codex.alwaysVisibleInSettings)
        XCTAssertFalse(trae.defaultEnabled)
        XCTAssertFalse(trae.alwaysVisibleInSettings)
    }

    func testTraeProfilesExposeOnlyOfficiallyAvailableHookIntegrations() throws {
        let trae = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "trae-hooks"))
        let traeCN = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "trae-cn-hooks"))
        let work = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "trae-solo-hooks"))
        let workCN = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "trae-solo-cn-hooks"))

        XCTAssertTrue(trae.supportsHookIntegration)
        XCTAssertTrue(traeCN.supportsHookIntegration)
        XCTAssertFalse(work.supportsHookIntegration)
        XCTAssertFalse(workCN.supportsHookIntegration)
        for profile in [trae, traeCN, work, workCN] {
            XCTAssertFalse(profile.defaultEnabled, profile.id)
            XCTAssertFalse(profile.alwaysVisibleInSettings, profile.id)
        }
    }

    func testOpenCodeUsesManagedPluginAndIsOptIn() throws {
        let profile = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "opencode-plugin"))

        XCTAssertEqual(profile.installationKind, .pluginFile)
        XCTAssertTrue(profile.primaryConfigurationURL.path.hasSuffix("/.config/opencode/plugins/cc-flow.ts"))
        XCTAssertFalse(profile.defaultEnabled)
        XCTAssertTrue(profile.alwaysVisibleInSettings)

        let source = HookInstaller.managedPluginSource(for: profile)
        XCTAssertTrue(source.contains("CC FLOW managed integration: opencode-plugin"))
        XCTAssertTrue(source.contains(#"event.type === "permission.asked""#))
        XCTAssertTrue(source.contains(#"event.type === "question.asked""#))
        XCTAssertTrue(source.contains(#""--source", "opencode""#))
        XCTAssertTrue(
            source.contains("const deliveryQueues = new Map()"),
            "OpenCode dispatches plugin events without awaiting async handlers, so deliveries must be serialized per session"
        )
        XCTAssertTrue(source.contains("const sessionStatuses = new Map()"))
        XCTAssertTrue(
            source.contains("const messageRoles = new Map()"),
            "OpenCode part events need the role from their preceding message.updated event"
        )
        XCTAssertTrue(source.contains("const lastAssistantMessages = new Map()"))
        XCTAssertTrue(source.contains("payload.message_role = messageRole"))
        XCTAssertTrue(source.contains("payload.last_assistant_message = lastAssistantMessage"))
        XCTAssertTrue(source.contains("if (!deliveredEventTypes.has(event?.type)) return Promise.resolve()"))
        XCTAssertFalse(source.contains(#""message.part.delta""#))
        XCTAssertTrue(source.contains("enqueueDelivery(event, directory, client)"))
    }

    func testPersistedEmptyHookSelectionDoesNotRestoreDefaults() {
        XCTAssertTrue(HookInstaller.resolvedPreferredTargets(persistedValues: []).isEmpty)
        XCTAssertEqual(
            HookInstaller.resolvedPreferredTargets(persistedValues: nil),
            ClientProfileRegistry.defaultManagedHookProfileIDs()
        )
    }

    func testCodexInstallPreservesUserHookReplacesLegacyAndIsIdempotent() throws {
        let profile = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "codex-hooks"))
        let existing = Data(#"{"theme":"dark","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/usr/bin/true"}]},{"hooks":[{"type":"command","command":"/Users/me/.trae-flow/bin/trae-flow-bridge --source codex"}]}]}}"#.utf8)

        let first = HookInstaller.updatedHookConfigurationData(existingData: existing, profile: profile)
        let second = HookInstaller.updatedHookConfigurationData(existingData: first, profile: profile)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: second) as? [String: Any])
        XCTAssertEqual(json["theme"] as? String, "dark")

        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let sessionStart = try XCTUnwrap(hooks["SessionStart"] as? [[String: Any]])
        let commands = sessionStart.compactMap(Self.command(from:))
        XCTAssertTrue(commands.contains("/usr/bin/true"))
        XCTAssertEqual(commands.filter { $0.contains("/.cc-flow/bin/cc-flow-bridge --source codex") }.count, 1)
        XCTAssertFalse(commands.contains(where: { $0.contains("/.trae-flow/") }))
    }

    func testUninstallRemovesOnlyManagedHooks() throws {
        let profile = try XCTUnwrap(ClientProfileRegistry.managedHookProfile(id: "claude-hooks"))
        let installed = HookInstaller.updatedHookConfigurationData(
            existingData: Data(#"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/usr/bin/true"}]}]}}"#.utf8),
            profile: profile
        )
        let removed = HookInstaller.removingManagedHookConfigurationData(existingData: installed)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: removed) as? [String: Any])
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let sessionStart = try XCTUnwrap(hooks["SessionStart"] as? [[String: Any]])
        XCTAssertEqual(sessionStart.compactMap(Self.command(from:)), ["/usr/bin/true"])
    }

    private static func command(from entry: [String: Any]) -> String? {
        (entry["hooks"] as? [[String: Any]])?.first?["command"] as? String
    }
}
