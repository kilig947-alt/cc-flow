import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum FollowUpMessageDeliveryRoute: Equatable {
    case direct
    case focusPasteAndSubmit

    static func resolve(for session: SessionState) -> Self {
        session.supportsTmuxCLIMessaging ? .direct : .focusPasteAndSubmit
    }
}

enum FollowUpMessageDeliveryResult: Equatable {
    case sentDirectly
    case sentViaTerminal
}

enum FollowUpMessageDeliveryError: LocalizedError {
    case accessibilityPermissionRequired
    case exactTerminalNotFound
    case keyboardEventUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "需要开启辅助功能权限，才能自动粘贴并发送。"
        case .exactTerminalNotFound:
            return "无法定位原会话所在的终端标签，未发送以避免发到错误终端。"
        case .keyboardEventUnavailable:
            return "无法生成键盘事件，回复尚未发送。"
        }
    }
}

extension SessionMonitor {
    /// Delivers a follow-up answer all the way to the target session.
    /// tmux sessions use the direct CLI route; other supported terminals are
    /// selected exactly before paste + Return is synthesized.
    func deliverFollowUpMessage(
        _ text: String,
        to session: SessionState
    ) async throws -> FollowUpMessageDeliveryResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .sentDirectly }

        if FollowUpMessageDeliveryRoute.resolve(for: session) == .direct {
            try await sendSessionMessage(sessionId: session.sessionId, text: trimmed)
            return .sentDirectly
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)

        guard AXIsProcessTrusted() else {
            throw FollowUpMessageDeliveryError.accessibilityPermissionRequired
        }
        guard await SessionLauncher.shared.focusForTextInput(session) else {
            throw FollowUpMessageDeliveryError.exactTerminalNotFound
        }

        // Let the terminal finish changing its selected tab and key window
        // before posting input events.
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard Self.pasteAndSubmitFollowUpMessage() else {
            throw FollowUpMessageDeliveryError.keyboardEventUnavailable
        }
        return .sentViaTerminal
    }

    private static func pasteAndSubmitFollowUpMessage() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let pasteDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let pasteUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false),
              let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else {
            return false
        }

        pasteDown.flags = .maskCommand
        pasteUp.flags = .maskCommand
        pasteDown.post(tap: .cghidEventTap)
        pasteUp.post(tap: .cghidEventTap)
        returnDown.post(tap: .cghidEventTap)
        returnUp.post(tap: .cghidEventTap)
        return true
    }
}
