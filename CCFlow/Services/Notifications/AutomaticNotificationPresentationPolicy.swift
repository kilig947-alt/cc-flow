import Foundation

enum AutomaticNotificationPresentationDecision: Equatable {
    case expand
    case broadcast
    case `defer`
    case discard
}

enum AutomaticNotificationPriority: Equatable {
    case standard
    case manualAttention
}

enum AutomaticNotificationPresentationPolicy {
    static func resolve(
        mode: NotificationPresentationMode,
        smartSuppressionTriggered: Bool,
        isPanelOpen: Bool,
        isFullscreenSuppressed: Bool,
        isReminderMuted: Bool,
        isLeftFeatureOpen: Bool = false,
        priority: AutomaticNotificationPriority = .standard
    ) -> AutomaticNotificationPresentationDecision {
        // Consume this delivery, rather than replaying it after the user leaves
        // their feature. Session attention state remains available in the badge.
        if isReminderMuted || isLeftFeatureOpen {
            return .discard
        }
        if isFullscreenSuppressed {
            return .defer
        }
        if mode == .quiet {
            return isPanelOpen ? .defer : .broadcast
        }
        if priority == .standard,
           !isPanelOpen,
           smartSuppressionTriggered {
            return .broadcast
        }
        return .expand
    }
}
