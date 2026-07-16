import AppKit
import Combine
import Foundation

struct MailSignal: Identifiable, Equatable {
    let id: String
    let sender: String
    let subject: String
    let receivedAt: Date
    let verificationCode: String?
}

@MainActor
final class MailAssistantService: ObservableObject {
    static let shared = MailAssistantService()
    @Published private(set) var signals: [MailSignal] = []
    @Published private(set) var status = "点击刷新以读取 Mail 最近邮件"
    @Published private(set) var isLoading = false
    private init() {}

    func refresh() {
        guard !isLoading else { return }
        isLoading = true; status = "正在读取…"
        Task.detached(priority: .utility) {
            let script = """
            tell application "Mail"
              set recentMessages to messages 1 thru (min of {30, count of messages of inbox}) of inbox
              set output to ""
              repeat with m in recentMessages
                set output to output & (message id of m as text) & tab & (sender of m as text) & tab & (subject of m as text) & tab & (date received of m as text) & linefeed
              end repeat
              return output
            end tell
            """
            let process = Process(); let pipe = Pipe(); let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]; process.standardOutput = pipe; process.standardError = errorPipe
            do {
                try process.run(); process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                let signals = text.split(separator: "\n").compactMap(Self.parseLine)
                let errorText = String(data: errorData, encoding: .utf8) ?? ""
                await MainActor.run {
                    self.signals = signals
                    self.status = process.terminationStatus == 0 ? "已读取 \(signals.count) 封最近邮件" : (errorText.isEmpty ? "无法读取 Mail" : errorText)
                    self.isLoading = false
                }
            } catch { await MainActor.run { self.status = error.localizedDescription; self.isLoading = false } }
        }
    }

    nonisolated private static func parseLine(_ line: Substring) -> MailSignal? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 3 else { return nil }
        let combined = fields[2]
        let code = firstCode(in: combined)
        return MailSignal(id: fields[0], sender: fields[1], subject: fields[2], receivedAt: Date(), verificationCode: code)
    }

    nonisolated static func firstCode(in text: String) -> String? {
        let regex = try? NSRegularExpression(pattern: "(?<![0-9])[0-9]{4,8}(?![0-9])")
        guard let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }
}
