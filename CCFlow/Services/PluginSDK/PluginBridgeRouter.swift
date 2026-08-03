import AppKit
import Foundation
import WebKit

struct PluginManifest: Decodable, Equatable {
    let manifestVersion: Int
    let id: String
    let name: String?
    let version: String
    let entryPoint: String?
    let sdkVersion: String
    let capabilities: [String]

    static func load(from directory: URL) -> PluginManifest? {
        let url = directory.appendingPathComponent("cc-flow-panel.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PluginManifest.self, from: data)
    }
}

enum PluginBridgeError: Error {
    case invalidArgument(String)
    case methodNotFound(String)
    case capabilityRequired(String)
    case userDenied(String)
    case notAvailable(String)

    var payload: [String: Any] {
        switch self {
        case .invalidArgument(let message): return ["code": "INVALID_ARGUMENT", "message": message]
        case .methodNotFound(let method): return ["code": "METHOD_NOT_FOUND", "message": "Unknown Plugin SDK method: \(method)"]
        case .capabilityRequired(let capability): return ["code": "CAPABILITY_REQUIRED", "message": "Plugin must declare capability: \(capability)"]
        case .userDenied(let capability): return ["code": "USER_DENIED", "message": "User denied capability: \(capability)"]
        case .notAvailable(let message): return ["code": "NOT_AVAILABLE", "message": message]
        }
    }
}

@MainActor
final class PluginBridgeMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    var area: CustomArea?
    private var manifest: PluginManifest? {
        guard let area else { return nil }
        return PluginManifest.load(from: area.directoryURL)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard message.frameInfo.isMainFrame else {
            replyHandler(failure(.notAvailable("Plugin SDK calls are only accepted from the main frame.")), nil)
            return
        }
        guard let area, let manifest, manifest.manifestVersion == 2 else {
            replyHandler(failure(.notAvailable("The complete Plugin SDK requires a local manifestVersion 2 plugin.")), nil)
            return
        }
        guard let callerURL = message.frameInfo.request.url,
              callerURL.isFileURL,
              isInsidePluginDirectory(callerURL, area: area) else {
            replyHandler(failure(.notAvailable("Plugin SDK calls must originate from the local plugin directory.")), nil)
            return
        }
        guard let request = message.body as? [String: Any],
              let method = request["method"] as? String,
              let params = request["params"] as? [String: Any] else {
            replyHandler(failure(.invalidArgument("Expected { method, params } request object.")), nil)
            return
        }

        Task { @MainActor in
            do {
                let result = try await PluginBridgeRouter.dispatch(method: method, params: params, manifest: manifest, area: area)
                replyHandler(["ok": true, "result": result], nil)
            } catch let error as PluginBridgeError {
                replyHandler(self.failure(error), nil)
            } catch {
                replyHandler(["ok": false, "error": ["code": "INTERNAL_ERROR", "message": error.localizedDescription]], nil)
            }
        }
    }

    private func failure(_ error: PluginBridgeError) -> [String: Any] {
        ["ok": false, "error": error.payload]
    }

    private func isInsidePluginDirectory(_ url: URL, area: CustomArea) -> Bool {
        let root = area.directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}

@MainActor
enum PluginBridgeRouter {
    private static let sensitiveCapabilities: Set<String> = [
        "clipboard.read", "clipboard.write", "apps.open", "apps.launch", "sessions.focus"
    ]

    static func dispatch(method: String, params: [String: Any], manifest: PluginManifest, area: CustomArea) async throws -> Any {
        let definition = PluginSDKCatalog.schema.methods.first { $0.name == method }
        guard let definition else { throw PluginBridgeError.methodNotFound(method) }
        if let capability = definition.capability {
            guard manifest.capabilities.contains(capability) else { throw PluginBridgeError.capabilityRequired(capability) }
            var justGranted = false
            if !PluginCapabilityGrantStore.isGranted(capability, areaID: area.id, manifest: manifest) {
                let granted = await confirmGrant(capability: capability, plugin: manifest)
                if !granted {
                    throw PluginBridgeError.userDenied(capability)
                }
                PluginCapabilityGrantStore.grant(capability, areaID: area.id, manifest: manifest)
                justGranted = true
            }
            if !justGranted,
               sensitiveCapabilities.contains(capability),
               !PluginSensitiveCapabilityGrantStore.isGranted(
                   capability,
                   areaID: area.id,
                   manifest: manifest
               ) {
                let decision = await confirm(capability: capability, plugin: manifest)
                switch decision {
                case .allowOnce:
                    break
                case .allowWhileAppIsRunning:
                    PluginSensitiveCapabilityGrantStore.grant(
                        capability,
                        areaID: area.id,
                        manifest: manifest
                    )
                case .deny:
                    throw PluginBridgeError.userDenied(capability)
                }
            }
        }

        switch method {
        case "core.getVersion":
            return ["sdkVersion": PluginSDKCatalog.schema.sdkVersion, "schemaVersion": PluginSDKCatalog.schema.schemaVersion]
        case "core.getCapabilities":
            return [
                "declared": manifest.capabilities,
                "granted": manifest.capabilities.filter { PluginCapabilityGrantStore.isGranted($0, areaID: area.id, manifest: manifest) }
            ]
        case "island.hint.show":
            let text = try requiredString("text", params: params, maximumLength: 2_000)
            let duration = min(max(params["duration"] as? Int ?? 5_000, 500), 60_000)
            CustomAreaHintStore.shared.postHint(areaID: area.id, text: text, durationMs: duration)
            return ["shown": true]
        case "island.hint.clear":
            CustomAreaHintStore.shared.clearHint(for: area.id)
            return ["cleared": true]
        case "system.getMetrics":
            let data = try JSONEncoder().encode(SystemMetricsProvider.shared.sample())
            return try JSONSerialization.jsonObject(with: data)
        case "system.getAppearance":
            return [
                "colorScheme": NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light",
                "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "increaseContrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ]
        case "system.clipboard.readText":
            return ["text": NSPasteboard.general.string(forType: .string) ?? ""]
        case "system.clipboard.writeText":
            let text = try requiredString("text", params: params, maximumLength: 1_000_000)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return ["written": true]
        case "apps.openURL":
            let raw = try requiredString("url", params: params, maximumLength: 8_192)
            guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                throw PluginBridgeError.invalidArgument("Only http/https URLs are allowed.")
            }
            return ["opened": NSWorkspace.shared.open(url)]
        case "apps.launch":
            let bundleID = try requiredString("bundleIdentifier", params: params, maximumLength: 255)
            let launched = NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleID, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
            return ["launched": launched]
        case "sessions.list":
            let sessions = await SessionStore.shared.allSessions()
            return sessions.map(summary)
        case "sessions.focus":
            let sessionID = try requiredString("sessionId", params: params, maximumLength: 512)
            guard let session = await SessionStore.shared.session(for: sessionID) else {
                throw PluginBridgeError.notAvailable("Session not found.")
            }
            return ["focused": await SessionLauncher.shared.activate(session)]
        default:
            throw PluginBridgeError.methodNotFound(method)
        }
    }

    private static func summary(_ session: SessionState) -> [String: Any] {
        return [
            "sessionId": session.sessionId,
            "provider": session.provider.rawValue,
            "client": session.clientDisplayName,
            "phase": String(describing: session.phase),
            "needsAttention": session.needsAttention,
            "createdAt": ISO8601DateFormatter().string(from: session.createdAt),
            "lastActivity": ISO8601DateFormatter().string(from: session.lastActivity)
        ]
    }

    private static func requiredString(_ key: String, params: [String: Any], maximumLength: Int) throws -> String {
        guard let value = params[key] as? String, !value.isEmpty, value.count <= maximumLength else {
            throw PluginBridgeError.invalidArgument("\(key) must be a non-empty string up to \(maximumLength) characters.")
        }
        return value
    }

    private static func presentAlert(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)

        let targetWindow: NSWindow? = {
            if let window = SettingsWindowController.shared.window, window.isVisible {
                return window
            }
            if let key = NSApp.keyWindow, key.isVisible {
                return key
            }
            if let main = NSApp.mainWindow, main.isVisible {
                return main
            }
            return nil
        }()

        if let targetWindow {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: targetWindow) { response in
                    continuation.resume(returning: response)
                }
            }
        } else {
            alert.window.level = SettingsWindowLayout.windowLevel
            alert.window.makeKeyAndOrderFront(nil)
            return alert.runModal()
        }
    }

    private static func confirm(
        capability: String,
        plugin: PluginManifest
    ) async -> PluginSensitivePermissionDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "允许 \(plugin.name ?? plugin.id) 使用 \(capability)？"
        alert.informativeText = "这是敏感操作。你可以仅允许当前调用，或在本次 App 运行期间持续允许；重启 App 后将重新询问。"
        alert.addButton(withTitle: "允许一次")
        alert.addButton(withTitle: "App 打开期间允许")
        alert.addButton(withTitle: "拒绝")
        switch await presentAlert(alert) {
        case .alertFirstButtonReturn:
            return .allowOnce
        case .alertSecondButtonReturn:
            return .allowWhileAppIsRunning
        default:
            return .deny
        }
    }

    private static func confirmGrant(capability: String, plugin: PluginManifest) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "插件请求权限"
        alert.informativeText = "\(plugin.name ?? plugin.id) 请求在当前插件版本中使用 \(capability)。插件版本或权限清单变化后将重新授权。"
        alert.addButton(withTitle: "授权")
        alert.addButton(withTitle: "拒绝")
        return await presentAlert(alert) == .alertFirstButtonReturn
    }
}

enum PluginSensitivePermissionDecision: Equatable {
    case allowOnce
    case allowWhileAppIsRunning
    case deny
}

@MainActor
enum PluginSensitiveCapabilityGrantStore {
    private static var grants: Set<String> = []

    static func isGranted(_ capability: String, areaID: String, manifest: PluginManifest) -> Bool {
        grants.contains(grantKey(capability: capability, areaID: areaID, manifest: manifest))
    }

    static func grant(_ capability: String, areaID: String, manifest: PluginManifest) {
        grants.insert(grantKey(capability: capability, areaID: areaID, manifest: manifest))
    }

    static func resetForTesting() {
        grants.removeAll()
    }

    private static func grantKey(capability: String, areaID: String, manifest: PluginManifest) -> String {
        "\(areaID)|\(manifest.id)|\(manifest.version)|\(manifest.capabilities.sorted().joined(separator: ","))|\(capability)"
    }
}

private enum PluginCapabilityGrantStore {
    private static let defaultsKey = "pluginSDKCapabilityGrants.v1"

    static func isGranted(_ capability: String, areaID: String, manifest: PluginManifest) -> Bool {
        grants()[grantKey(areaID: areaID, manifest: manifest)]?.contains(capability) == true
    }

    static func grant(_ capability: String, areaID: String, manifest: PluginManifest) {
        var value = grants()
        let key = grantKey(areaID: areaID, manifest: manifest)
        var capabilities = value[key] ?? []
        capabilities.insert(capability)
        value = value.filter { $0.key == key || !$0.key.hasPrefix(areaID + "|") }
        value[key] = capabilities
        UserDefaults.standard.set(value.mapValues(Array.init), forKey: defaultsKey)
    }

    private static func grantKey(areaID: String, manifest: PluginManifest) -> String {
        "\(areaID)|\(manifest.id)|\(manifest.version)|\(manifest.capabilities.sorted().joined(separator: ","))"
    }

    private static func grants() -> [String: Set<String>] {
        let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String]] ?? [:]
        return raw.mapValues(Set.init)
    }
}

final class PluginSDKSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard task.request.url?.host == "v1", task.request.url?.path == "/index.js",
              let url = Bundle.main.url(forResource: "cc-flow-sdk", withExtension: "js", subdirectory: "PluginSDK")
                ?? Bundle.main.url(forResource: "cc-flow-sdk", withExtension: "js"),
              let data = try? Data(contentsOf: url) else {
            task.didFailWithError(PluginBridgeError.notAvailable("Plugin SDK module resource is unavailable."))
            return
        }
        let response = HTTPURLResponse(
            url: task.request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/javascript; charset=utf-8", "Access-Control-Allow-Origin": "*"]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
