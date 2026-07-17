import Foundation

struct SessionManualAttentionTracker {
    private struct AttentionKey: Hashable {
        enum Kind: String {
            case approval
            case question
            case terminalRouted
        }

        let stableID: String
        let kind: Kind
        let token: String
    }

    private var acknowledgedKeys = Set<AttentionKey>()

    /// Returns the newest attention request without marking it delivered.
    /// Call `acknowledge(_:)` only after its visual route is presented.
    mutating func nextAttentionSession(from instances: [SessionState]) -> SessionState? {
        let candidates = instances.compactMap { session -> (SessionState, AttentionKey)? in
            guard let key = attentionKey(for: session) else { return nil }
            return (session, key)
        }
        let currentKeys = Set(candidates.map(\.1))
        acknowledgedKeys.formIntersection(currentKeys)

        return candidates
            .filter { !acknowledgedKeys.contains($0.1) }
            .map(\.0)
            .sorted(by: attentionSort)
            .first
    }

    mutating func acknowledge(_ session: SessionState) {
        guard let key = attentionKey(for: session) else { return }
        acknowledgedKeys.insert(key)
    }

    /// Compatibility path for callers that deliver immediately.
    mutating func consumeNewAttentionSession(from instances: [SessionState]) -> SessionState? {
        guard let session = nextAttentionSession(from: instances) else { return nil }
        acknowledge(session)
        return session
    }

    private func attentionKey(for session: SessionState) -> AttentionKey? {
        if session.needsApprovalResponse {
            return AttentionKey(
                stableID: session.stableId,
                kind: .approval,
                token: session.activePermission?.toolUseId ?? ""
            )
        }
        if session.needsQuestionResponse {
            return AttentionKey(
                stableID: session.stableId,
                kind: .question,
                token: session.intervention?.id ?? ""
            )
        }
        if session.suppressInAppPromptControls {
            return AttentionKey(
                stableID: session.stableId,
                kind: .terminalRouted,
                token: session.activePermission?.toolUseId
                    ?? session.intervention?.id
                    ?? session.phase.description
            )
        }
        return nil
    }

    nonisolated private func attentionSort(_ lhs: SessionState, _ rhs: SessionState) -> Bool {
        let lhsDate = lhs.attentionRequestedAt ?? lhs.lastUserMessageDate ?? lhs.lastActivity
        let rhsDate = rhs.attentionRequestedAt ?? rhs.lastUserMessageDate ?? rhs.lastActivity
        return lhsDate > rhsDate
    }
}
