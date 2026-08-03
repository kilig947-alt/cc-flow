import Foundation

enum SessionResumeCommand {
    nonisolated static func clipboardText(for session: SessionState) -> String {
        clipboardText(provider: session.provider, sessionId: session.sessionId)
    }

    nonisolated static func clipboardText(
        provider: SessionProvider,
        sessionId: String
    ) -> String {
        let normalizedSessionId = normalizedSessionId(
            sessionId,
            provider: provider
        )
        let argument = shellQuotedIfNeeded(normalizedSessionId)

        switch provider {
        case .codex:
            return "codex resume \(argument)"
        case .claude:
            return "claude --resume \(argument)"
        case .trae, .antigravity:
            // These clients do not expose a stable public CLI resume command.
            return normalizedSessionId
        }
    }

    private nonisolated static func normalizedSessionId(
        _ sessionId: String,
        provider: SessionProvider
    ) -> String {
        let prefix = provider.rawValue + ":"
        if sessionId.hasPrefix(prefix) {
            return String(sessionId.dropFirst(prefix.count))
        }
        return sessionId
    }

    private nonisolated static func shellQuotedIfNeeded(_ value: String) -> String {
        let safeCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"
        )
        if !value.isEmpty,
           value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
