import Combine
import CryptoKit
import Foundation
import Network

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
    private var listener: NWListener?
    private var consumers = 0

    private init() {}

    var pairingToken: String {
        if let token = ProductivitySecretsStore.shared.value(for: .browserPairingToken) { return token }
        let token = Self.makeToken()
        try? ProductivitySecretsStore.shared.set(token, for: .browserPairingToken)
        return token
    }

    func rotateToken() -> String {
        let token = Self.makeToken(); try? ProductivitySecretsStore.shared.set(token, for: .browserPairingToken); return token
    }

    func start() {
        consumers += 1; guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
            listener.stateUpdateHandler = { [weak self] state in Task { @MainActor in
                switch state { case .ready: self?.status = "正在监听 Chrome、Edge 与 Safari"
                case .failed(let error): self?.status = error.localizedDescription
                default: break }
            } }
            listener.start(queue: DispatchQueue(label: "ai.ccflow.browser-bridge")); self.listener = listener
        } catch { status = error.localizedDescription }
    }

    func stop() { consumers = max(0, consumers - 1); guard consumers == 0 else { return }; listener?.cancel(); listener = nil; status = "未启动" }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "ai.ccflow.browser-client"))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128_000) { [weak self] data, _, _, _ in
            Task { @MainActor in self?.handleHTTP(data ?? Data(), connection: connection) }
        }
    }

    private func handleHTTP(_ data: Data, connection: NWConnection) {
        guard let text = String(data: data, encoding: .utf8), let separator = text.range(of: "\r\n\r\n") else { respond(400, connection); return }
        let body = Data(text[separator.upperBound...].utf8)
        guard body.count <= 64_000, let envelope = try? JSONDecoder().decode(BrowserBridgeEnvelope.self, from: body),
              envelope.version == 1, envelope.token == pairingToken else { respond(401, connection); return }
        switch envelope.type {
        case "pageSaved":
            if let raw = envelope.url, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                BrowserResourceService.shared.add(url: url, title: envelope.title, browser: envelope.browser)
            }
        case "download":
            let event = BrowserDownloadEvent(id: envelope.id ?? UUID().uuidString, browser: envelope.browser,
                filename: envelope.filename ?? "下载", state: envelope.state ?? "unknown",
                receivedBytes: envelope.receivedBytes ?? 0, totalBytes: envelope.totalBytes ?? 0, updatedAt: Date())
            downloads.removeAll { $0.id == event.id && $0.browser == event.browser }; downloads.insert(event, at: 0)
            downloads = Array(downloads.prefix(100))
        default: respond(422, connection); return
        }
        respond(200, connection)
    }

    private func respond(_ code: Int, _ connection: NWConnection) {
        let body = code == 200 ? "{\"ok\":true}" : "{\"ok\":false}"
        let response = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    nonisolated private static func makeToken() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }
}
