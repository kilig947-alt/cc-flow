import AppKit

/// Chromium's focused AX element can omit AXSelectedText even with a visible selection.
/// Copy while the source app still owns focus, then restore the user's clipboard.
nonisolated enum TranslationSelectionReader {
    @concurrent
    static func copySelection(from application: NSRunningApplication?) async -> String? {
        guard let application, application.processIdentifier != Foundation.ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else { return nil }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        return await copySelection(on: .general) {
            guard !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else { return }
            down.postToPid(application.processIdentifier)
            up.postToPid(application.processIdentifier)
        }
    }

    @concurrent
    static func copySelection(on clipboard: NSPasteboard, sendCopy: () -> Void) async -> String? {
        guard !Task.isCancelled else { return nil }
        let originalCount = clipboard.changeCount
        let saved = (clipboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        guard !Task.isCancelled, clipboard.changeCount == originalCount else { return nil }
        sendCopy()
        for _ in 0..<15 {
            do { try await Task.sleep(for: .milliseconds(40)) } catch { break }
            if clipboard.changeCount != originalCount { break }
        }
        guard clipboard.changeCount != originalCount else { return nil }
        let value = clipboard.string(forType: .string)
        // No suspension between reading the copied value and restoring the snapshot.
        let restored = saved.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        clipboard.clearContents()
        clipboard.writeObjects(restored)
        return Task.isCancelled ? nil : value
    }
}

nonisolated enum TranslationInput: Sendable {
    case text(String), image(Data), empty, permissionRequired, cancelled
}

/// AX IPC and lazy pasteboard representations can block. Run them on this actor,
/// while serializing copy/restore transactions across repeated shortcut presses.
actor TranslationInputReader {
    static let shared = TranslationInputReader()
    private var reading = false

    func read(selectionFrom pid: pid_t? = nil) async -> TranslationInput {
        while reading {
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return .cancelled }
        }
        guard !Task.isCancelled else { return .cancelled }
        reading = true
        defer { reading = false }
        if let pid {
            guard AXIsProcessTrusted() else { return .permissionRequired }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            var focused: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let element = focused as! AXUIElement
                AXUIElementSetMessagingTimeout(element, 0.25)
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
                   let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return Task.isCancelled ? .cancelled : .text(text)
                }
            }
            guard !Task.isCancelled else { return .cancelled }
            if let text = await TranslationSelectionReader.copySelection(from: NSRunningApplication(processIdentifier: pid)),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return Task.isCancelled ? .cancelled : .text(text)
            }
        }
        guard !Task.isCancelled else { return .cancelled }
        let clipboard = NSPasteboard.general
        if let text = clipboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        if let image = NSImage(pasteboard: clipboard), let data = image.tiffRepresentation { return .image(data) }
        return .empty
    }
}
