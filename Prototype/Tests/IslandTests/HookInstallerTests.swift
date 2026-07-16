import Foundation
@testable import IslandApp
import Testing

@Test
func installerMergesClaudeHooksWithoutDroppingExistingValues() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let settingsURL = root.appending(path: ".claude/settings.json")
    try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let existing = """
    {
      "env": {"EXISTING_VAR": "1"},
      "hooks": {
        "SessionStart": [{
          "hooks": [{"type": "command", "command": "/usr/bin/true"}],
          "matcher": "*"
        }]
      }
    }
    """
    try Data(existing.utf8).write(to: settingsURL)

    let installer = HookInstaller(homeDirectory: root)
    try installer.installDefaultHookAssets()

    let data = try Data(contentsOf: settingsURL)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let env = try #require(json["env"] as? [String: Any])
    #expect(env["EXISTING_VAR"] as? String == "1")
    #expect(env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] as? String == "1")

    let hooks = try #require(json["hooks"] as? [String: Any])
    let sessionStart = try #require(hooks["SessionStart"] as? [[String: Any]])
    #expect(sessionStart.count >= 2)
    let sessionStartCommands = sessionStart.compactMap { hook in
        ((hook["hooks"] as? [[String: Any]])?.first?["command"] as? String)
    }
    #expect(sessionStartCommands.contains { $0.contains("/.cc-flow/bin/cc-flow-bridge --source claude") })

    let permissionRequest = try #require(hooks["PermissionRequest"] as? [[String: Any]])
    let installedHook = try #require(permissionRequest.last?["hooks"] as? [[String: Any]])
    #expect(installedHook.first?["timeout"] as? Int == 86_400)
    #expect(hooks["SessionEnd"] != nil)
    #expect(hooks["PreCompact"] != nil)
}

@Test
func installerCreatesLauncherUnderCCFlowSupportDirectory() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let installer = HookInstaller(homeDirectory: root)
    try installer.installDefaultHookAssets()

    let launcherURL = root.appending(path: ".cc-flow/bin/cc-flow-bridge")
    #expect(FileManager.default.fileExists(atPath: launcherURL.path()))

    let launcher = try String(contentsOf: launcherURL, encoding: .utf8)
    #expect(launcher.contains("CCFlowBridge"))
    #expect(launcher.contains("IslandBridge"))
}

@Test
func installerWritesClaudeUsageSnapshotThroughPrivateSecureTemporaryFile() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let installer = HookInstaller(homeDirectory: root)
    try installer.installDefaultHookAssets()

    let scriptURL = root.appending(path: ".cc-flow/bin/cc-flow-statusline")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)
    #expect(script.contains("umask 077"))
    #expect(script.contains("Library/Application Support/cc-flow"))
    #expect(script.contains("mktemp"))
    #expect(!script.contains("/tmp/cc-flow-usage"))
    #expect(!script.contains("/tmp/cc-flow-rate-limits"))
}

@Test
func installerAcceptsJSONCSettingsFiles() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let settingsURL = root.appending(path: ".claude/settings.json")
    try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let existing = """
    {
      // user-defined environment should be preserved
      "env": {
        "EXISTING_VAR": "1",
      },
      "hooks": {
        "SessionStart": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "/usr/bin/true",
              },
            ],
            "matcher": "*",
          },
        ],
      },
    }
    """
    try Data(existing.utf8).write(to: settingsURL)

    let installer = HookInstaller(homeDirectory: root)
    try installer.installDefaultHookAssets()

    let data = try Data(contentsOf: settingsURL)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let env = try #require(json["env"] as? [String: Any])
    #expect(env["EXISTING_VAR"] as? String == "1")

    let hooks = try #require(json["hooks"] as? [String: Any])
    let sessionStart = try #require(hooks["SessionStart"] as? [[String: Any]])
    let commands = sessionStart.compactMap { hook in
        ((hook["hooks"] as? [[String: Any]])?.first?["command"] as? String)
    }
    #expect(commands.contains("/usr/bin/true"))
    #expect(commands.contains { $0.contains("/.cc-flow/bin/cc-flow-bridge --source claude") })
}

@Test
func installerPreservesUserCodexHooksAndRemovesLegacyManagedEntries() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let hooksURL = root.appending(path: ".codex/hooks.json")
    try FileManager.default.createDirectory(at: hooksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/usr/bin/true"}]},{"hooks":[{"type":"command","command":"/Users/test/.trae-flow/bin/trae-flow-bridge --source codex"}]}]}}"#.utf8)
        .write(to: hooksURL)

    let installer = HookInstaller(homeDirectory: root)
    try installer.installDefaultHookAssets()
    try installer.installDefaultHookAssets()

    let data = try Data(contentsOf: hooksURL)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let hooks = try #require(json["hooks"] as? [String: Any])
    let sessionStart = try #require(hooks["SessionStart"] as? [[String: Any]])
    let commands = sessionStart.compactMap { entry in
        (entry["hooks"] as? [[String: Any]])?.first?["command"] as? String
    }

    #expect(commands.contains("/usr/bin/true"))
    #expect(commands.filter { $0.contains("/.cc-flow/bin/cc-flow-bridge --source codex") }.count == 1)
    #expect(commands.contains(where: { $0.contains("/.trae-flow/") }) == false)
}
