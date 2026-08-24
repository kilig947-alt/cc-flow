import AppKit
import Combine
import CryptoKit
import Foundation
import Network

extension Notification.Name {
    static let ccFlowCollapseForBrowserConnection = Notification.Name("ccFlowCollapseForBrowserConnection")
}

enum BrowserExtensionTarget: String, CaseIterable, Identifiable {
    case chrome
    case edge
    case safari

    var id: String { rawValue }
    var displayName: String {
        switch self { case .chrome: "Chrome"; case .edge: "Edge"; case .safari: "Safari" }
    }
    var systemImage: String {
        switch self { case .chrome: "globe"; case .edge: "network"; case .safari: "safari" }
    }
    var bundleIdentifier: String {
        switch self {
        case .chrome: "com.google.Chrome"
        case .edge: "com.microsoft.edgemac"
        case .safari: "com.apple.Safari"
        }
    }
    var extensionManagementURL: URL? {
        switch self {
        case .chrome: URL(string: "chrome://extensions/")
        case .edge: URL(string: "edge://extensions/")
        case .safari: nil
        }
    }
}

struct BrowserDownloadEvent: Identifiable, Equatable {
    let id: String
    let browser: String
    let filename: String
    let state: String
    let receivedBytes: Int64
    let totalBytes: Int64
    let updatedAt: Date
}

private struct BrowserBridgeEnvelope: Decodable {
    let version: Int
    let token: String
    let type: String
    let browser: String
    let id: String?
    let url: String?
    let title: String?
    let filename: String?
    let state: String?
    let receivedBytes: Int64?
    let totalBytes: Int64?
}

@MainActor
final class BrowserBridgeService: ObservableObject {
    static let shared = BrowserBridgeService()
    static let port: UInt16 = 43128
    @Published private(set) var downloads: [BrowserDownloadEvent] = []
    @Published private(set) var status = "未启动"
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var isExtensionConnected = false
    private var listener: NWListener?
    private var consumers = 0
    private var disconnectTask: Task<Void, Never>?
    /// 仅在用户显式显示、连接或轮换配对令牌后填充。
    /// 扩展的后台 heartbeat 不得自行触发钥匙串读取。
    private var activePairingToken: String?
    private let downloadStatesKey = "productivity.browserDownloadStates.v1"
    private var downloadStates: [String: String]

    private init() {
        downloadStates = UserDefaults.standard.dictionary(forKey: downloadStatesKey) as? [String: String] ?? [:]
    }

    var pairingToken: String {
        if let activePairingToken { return activePairingToken }
        if let token = ProductivitySecretsStore.shared.value(for: .browserPairingToken) {
            activePairingToken = token
            return token
        }
        let token = Self.makeToken()
        try? ProductivitySecretsStore.shared.set(token, for: .browserPairingToken)
        activePairingToken = token
        return token
    }

    func rotateToken() -> String {
        let token = Self.makeToken()
        try? ProductivitySecretsStore.shared.set(token, for: .browserPairingToken)
        activePairingToken = token
        disconnectTask?.cancel()
        disconnectTask = nil
        isExtensionConnected = false
        if listener != nil { status = "监听中，尚未连接浏览器扩展" }
        return token
    }

    func connect(to target: BrowserExtensionTarget) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingToken, forType: .string)
        NotificationCenter.default.post(name: .ccFlowCollapseForBrowserConnection, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.launch(target)
        }
    }

    private func launch(_ target: BrowserExtensionTarget) {
        let workspace = NSWorkspace.shared
        guard let applicationURL = workspace.urlForApplication(withBundleIdentifier: target.bundleIdentifier) else {
            presentConnectionAlert(
                title: "未找到 \(target.displayName)",
                message: "请先安装 \(target.displayName)，然后重新点击连接。配对令牌已经复制。"
            )
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let managementURL = target.extensionManagementURL {
            workspace.open([managementURL], withApplicationAt: applicationURL, configuration: configuration) { [weak self] _, error in
                guard let error else { return }
                Task { @MainActor in
                    self?.presentConnectionAlert(title: "无法打开 \(target.displayName)", message: error.localizedDescription)
                }
            }
        } else {
            presentConnectionAlert(
                title: "Safari 配对令牌已复制",
                message: "请在 Safari 中打开“Safari → 设置 → 扩展”，启用 CC FLOW Safari，再到扩展选项中粘贴令牌。"
            )
            workspace.openApplication(at: applicationURL, configuration: configuration) { [weak self] _, error in
                guard let error else { return }
                Task { @MainActor in
                    self?.presentConnectionAlert(title: "无法打开 Safari", message: error.localizedDescription)
                }
            }
        }
    }

    private func presentConnectionAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func start() {
        consumers += 1; guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
            listener.stateUpdateHandler = { [weak self] state in Task { @MainActor in
                switch state { case .ready: self?.status = "监听中，尚未连接浏览器扩展"
                case .failed(let error): self?.status = error.localizedDescription
                default: break }
            } }
            listener.start(queue: DispatchQueue(label: "ai.ccflow.browser-bridge")); self.listener = listener
        } catch { status = error.localizedDescription }
    }

    func stop() {
        consumers = max(0, consumers - 1)
        guard consumers == 0 else { return }
        listener?.cancel()
        listener = nil
        disconnectTask?.cancel()
        disconnectTask = nil
        isExtensionConnected = false
        status = "未启动"
    }

    private func accept(_ connection: NWConnection) {
        guard Self.isLoopback(connection.endpoint) else { connection.cancel(); return }
        connection.start(queue: DispatchQueue(label: "ai.ccflow.browser-client"))
        receiveHTTP(connection, buffer: Data())
    }

    nonisolated static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        let value = String(describing: host).lowercased()
        return value == "127.0.0.1" || value == "::1" || value == "localhost" || value.hasSuffix(":127.0.0.1")
    }

    private func receiveHTTP(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_000) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var next = buffer; next.append(data ?? Data())
                guard next.count <= 128_000, error == nil else { self.respond(413, connection); return }
                if self.isCompleteHTTPRequest(next) || isComplete { self.handleHTTP(next, connection: connection) }
                else { self.receiveHTTP(connection, buffer: next) }
            }
        }
    }

    private func isCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8), let separator = text.range(of: "\r\n\r\n") else { return false }
        let headers = String(text[..<separator.lowerBound])
        let lengthLine = headers.split(separator: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
        let expected = lengthLine.flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
        return text[separator.upperBound...].utf8.count >= expected
    }

    private func handleHTTP(_ data: Data, connection: NWConnection) {
        guard let text = String(data: data, encoding: .utf8), let separator = text.range(of: "\r\n\r\n") else { respond(400, connection); return }
        let body = Data(text[separator.upperBound...].utf8)
        guard body.count <= 64_000,
              let envelope = try? JSONDecoder().decode(BrowserBridgeEnvelope.self, from: body),
              envelope.version == 1 else {
            status = "扩展协议无法识别，请重新安装最新版扩展"
            respond(400, connection)
            return
        }
        guard let activePairingToken else {
            status = "请先在 CC FLOW 中显示或复制配对令牌"
            respond(503, connection)
            return
        }
        guard envelope.token == activePairingToken else {
            status = "扩展配对失败，请在扩展设置中更新配对令牌"
            respond(401, connection)
            return
        }
        switch envelope.type {
        case "heartbeat":
            break
        case "pageSaved":
            if let raw = envelope.url, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                BrowserResourceService.shared.add(url: url, title: envelope.title, browser: envelope.browser, notify: true)
            }
        case "download":
            let stableFallbackID = "\(envelope.filename ?? "download")|\(envelope.url ?? "")"
            let event = BrowserDownloadEvent(id: envelope.id ?? stableFallbackID, browser: envelope.browser,
                filename: envelope.filename ?? "下载", state: envelope.state ?? "unknown",
                receivedBytes: envelope.receivedBytes ?? 0, totalBytes: envelope.totalBytes ?? 0, updatedAt: Date())
            let stateKey = "\(event.browser)|\(event.id)"
            let previousState = downloadStates[stateKey]
            downloads.removeAll { $0.id == event.id && $0.browser == event.browser }; downloads.insert(event, at: 0)
            downloads = Array(downloads.prefix(100))
            for transition in ProductivityProactiveEventCenter.downloadTransitions(previousState: previousState, newState: event.state) {
                let summary = transition == .downloadCompleted ? "下载完成：\(event.filename)" : "新下载：\(event.filename)"
                ProductivityProactiveEventCenter.shared.publish(
                    targetFeatureID: LeftFeature.downloadMonitorID,
                    kind: transition,
                    summary: summary
                )
            }
            if previousState?.lowercased() != "complete" {
                downloadStates[stateKey] = event.state
                if downloadStates.count > 1_000 {
                    for key in downloadStates.keys.sorted().prefix(downloadStates.count - 1_000) { downloadStates[key] = nil }
                }
                UserDefaults.standard.set(downloadStates, forKey: downloadStatesKey)
            }
        default: respond(422, connection); return
        }
        if envelope.type != "heartbeat" { lastEventAt = Date() }
        markExtensionConnected(browser: envelope.browser)
        respond(200, connection)
    }

    private func markExtensionConnected(browser: String) {
        isExtensionConnected = true
        status = "已连接 \(browser)"
        disconnectTask?.cancel()
        disconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(75))
            guard !Task.isCancelled, let self else { return }
            self.isExtensionConnected = false
            self.status = "监听中，尚未连接浏览器扩展"
        }
    }

    private func respond(_ code: Int, _ connection: NWConnection) {
        let body = code == 200 ? "{\"ok\":true}" : "{\"ok\":false}"
        let response = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    nonisolated private static func makeToken() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }
}
