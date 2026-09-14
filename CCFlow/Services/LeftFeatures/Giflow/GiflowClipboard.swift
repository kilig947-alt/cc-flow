import AppKit
import UniformTypeIdentifiers

/// Publishes the original file and animation without synchronously decoding a TIFF on the UI thread.
enum GiflowClipboard {
    static func write(fileURL: URL, to pasteboard: NSPasteboard) throws {
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setPropertyList([fileURL.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        if fileURL.pathExtension.lowercased() == "gif" {
            // Read before clearing, so an unavailable file preserves the previous clipboard.
            item.setData(try Data(contentsOf: fileURL), forType: NSPasteboard.PasteboardType(UTType.gif.identifier))
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw NSError(domain: "GiflowClipboard", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法写入系统剪贴板，请重试"])
        }
    }
}
