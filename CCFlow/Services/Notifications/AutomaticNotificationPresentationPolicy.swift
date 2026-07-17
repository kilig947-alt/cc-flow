import Foundation

enum AutomaticNotificationPresentationDecision: Equatable {
    case expand
    case broadcast
    case `defer`
    case discard
}

enum AutomaticNotificationPresentationPolicy {
    static func resolve(
        mode: NotificationPresentationMode,
        smartSuppressionTriggered: Bool,
        isPanelOpen: Bool,
        isFullscreenSuppressed: Bool,
        isReminderMuted: Bool
    ) -> AutomaticNotificationPresentationDecision {
        if isReminderMuted {
            return .discard
        }
        if isFullscreenSuppressed {
            return .defer
        }
        if mode == .quiet {
            return isPanelOpen ? .defer : .broadcast
        }
        if !isPanelOpen && smartSuppressionTriggered {
            return .broadcast
        }
        return .expand
    }
}
