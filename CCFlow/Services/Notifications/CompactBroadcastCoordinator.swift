import Combine
import Foundation

enum CompactBroadcastSide: Hashable, Sendable {
    case leftFeature
    case session
}

enum CompactBroadcastTarget: Equatable, Sendable {
    case leftFeature(id: String)
    case session(stableID: String)
}

struct CompactBroadcast: Equatable, Identifiable, Sendable {
    let id: UUID
    let deduplicationKey: String
    let side: CompactBroadcastSide
    let target: CompactBroadcastTarget
    let iconName: String
    let summary: String
    let createdAt: Date
    let expiresAt: Date

    init(
        id: UUID = UUID(),
        deduplicationKey: String,
        side: CompactBroadcastSide,
        target: CompactBroadcastTarget,
        iconName: String,
        summary: String,
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.deduplicationKey = deduplicationKey
        self.side = side
        self.target = target
        self.iconName = iconName
        self.summary = summary
        self.createdAt = createdAt
        self.expiresAt = expiresAt ?? createdAt.addingTimeInterval(5)
    }
}

struct CompactBroadcastQueueState: Equatable, Sendable {
    private(set) var activeLeftFeature: CompactBroadcast?
    private(set) var activeSession: CompactBroadcast?

    mutating func enqueue(
        _ broadcast: CompactBroadcast,
        now: Date = Date(),
        isValid: (CompactBroadcastTarget) -> Bool = { _ in true }
    ) {
        guard broadcast.expiresAt > now, isValid(broadcast.target) else { return }
        switch broadcast.side {
        case .leftFeature:
            activeLeftFeature = broadcast
        case .session:
            activeSession = broadcast
        }
    }

    mutating func consume(_ side: CompactBroadcastSide) {
        switch side {
        case .leftFeature:
            activeLeftFeature = nil
        case .session:
            activeSession = nil
        }
    }

    mutating func clear() {
        activeLeftFeature = nil
        activeSession = nil
    }
}

@MainActor
final class CompactBroadcastCoordinator: ObservableObject {
    static let shared = CompactBroadcastCoordinator()

    @Published private(set) var activeLeftFeature: CompactBroadcast?
    @Published private(set) var activeSession: CompactBroadcast?

    private var state = CompactBroadcastQueueState()
    private var dismissalTasks: [CompactBroadcastSide: Task<Void, Never>] = [:]
    private let displayDuration: TimeInterval?
    private var targetValidator: (CompactBroadcastTarget) -> Bool = { _ in true }

    init(displayDuration: TimeInterval? = 5) {
        self.displayDuration = displayDuration
    }

    func enqueue(_ broadcast: CompactBroadcast) {
        state.enqueue(broadcast, isValid: targetValidator)
        publishState()
        let active = broadcast.side == .leftFeature ? activeLeftFeature : activeSession
        if active?.id == broadcast.id {
            scheduleDismissal(for: broadcast.side, id: broadcast.id)
        }
    }

    func consume(_ side: CompactBroadcastSide) {
        dismissalTasks[side]?.cancel()
        dismissalTasks[side] = nil
        state.consume(side)
        publishState()
    }

    func clear() {
        dismissalTasks.values.forEach { $0.cancel() }
        dismissalTasks.removeAll()
        state.clear()
        publishState()
    }

    func setTargetValidator(_ validator: @escaping (CompactBroadcastTarget) -> Bool) {
        targetValidator = validator
        discardInvalidActiveItems()
    }

    private func discardInvalidActiveItems() {
        if let activeLeftFeature,
           activeLeftFeature.expiresAt <= Date() || !targetValidator(activeLeftFeature.target) {
            consume(.leftFeature)
        }
        if let activeSession,
           activeSession.expiresAt <= Date() || !targetValidator(activeSession.target) {
            consume(.session)
        }
    }

    private func publishState() {
        activeLeftFeature = state.activeLeftFeature
        activeSession = state.activeSession
    }

    private func scheduleDismissal(for side: CompactBroadcastSide, id: UUID) {
        dismissalTasks[side]?.cancel()
        guard let displayDuration else {
            dismissalTasks[side] = nil
            return
        }
        let active = side == .leftFeature ? activeLeftFeature : activeSession
        let remainingLifetime = active.map { max(0, $0.expiresAt.timeIntervalSinceNow) } ?? displayDuration
        let delay = min(displayDuration, remainingLifetime)
        dismissalTasks[side] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let activeID = side == .leftFeature ? activeLeftFeature?.id : activeSession?.id
            guard activeID == id else { return }
            consume(side)
        }
    }
}
