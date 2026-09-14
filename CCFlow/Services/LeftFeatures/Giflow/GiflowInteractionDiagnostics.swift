import AppKit

/// Debug-only click tracing. Records routing/state, never clipboard contents or media filenames.
@MainActor
enum GiflowInteractionDiagnostics {
    static func record(_ message: String) {
        #if DEBUG
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cc-flow-giflow-clicks.log")
        let line = "\(Date().timeIntervalSince1970) pid=\(Foundation.ProcessInfo.processInfo.processIdentifier) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {}
        #endif
    }
}
