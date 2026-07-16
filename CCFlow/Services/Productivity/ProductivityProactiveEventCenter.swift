import Combine
import Foundation

enum ProductivityProactiveEventKind: String, Equatable, Sendable {
    case downloadStarted
    case downloadCompleted
    case browserResourceSaved
    case mailReceived
}

struct ProductivityProactiveEvent: Equatable, Identifiable, Sendable {
    let sequence: Int
    let targetFeatureID: String
    let kind: ProductivityProactiveEventKind
    let summary: String
    let count: Int
    let createdAt: Date
    var id: Int { sequence }
}

@MainActor
final class ProductivityProactiveEventCenter: ObservableObject {
    static let shared = ProductivityProactiveEventCenter()

    @Published private(set) var latestEvent: ProductivityProactiveEvent?

    private struct PendingEvent {
        var kind: ProductivityProactiveEventKind
        var summary: String
        var count: Int
    }

    private let aggregationInterval: TimeInterval
    private var pendingByFeature: [String: PendingEvent] = [:]
    private var emissionTasks: [String: Task<Void, Never>] = [:]
    private var nextSequence = 0
    private var consumedSequences: Set<Int> = []

    init(aggregationInterval: TimeInterval = 5) {
        self.aggregationInterval = aggregationInterval
    }

    func publish(targetFeatureID: String, kind: ProductivityProactiveEventKind, summary: String, count: Int = 1) {
        if var pending = pendingByFeature[targetFeatureID] {
            pending.kind = kind
            pending.summary = summary
            pending.count += max(1, count)
            pendingByFeature[targetFeatureID] = pending
            return
        }
        pendingByFeature[targetFeatureID] = PendingEvent(kind: kind, summary: summary, count: max(1, count))
        emissionTasks[targetFeatureID] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(aggregationInterval))
            guard !Task.isCancelled else { return }
            emit(targetFeatureID: targetFeatureID)
        }
    }

    func consume(_ sequence: Int) -> Bool {
        guard !consumedSequences.contains(sequence) else { return false }
        consumedSequences.insert(sequence)
        return true
    }

    private func emit(targetFeatureID: String) {
        guard let pending = pendingByFeature.removeValue(forKey: targetFeatureID) else { return }
        emissionTasks[targetFeatureID] = nil
        nextSequence &+= 1
        latestEvent = ProductivityProactiveEvent(
            sequence: nextSequence,
            targetFeatureID: targetFeatureID,
            kind: pending.kind,
            summary: pending.summary,
            count: pending.count,
            createdAt: Date()
        )
    }

    nonisolated static func downloadTransitions(previousState: String?, newState: String) -> [ProductivityProactiveEventKind] {
        var result: [ProductivityProactiveEventKind] = []
        let previous = previousState?.lowercased()
        let current = newState.lowercased()
        if previous == nil { result.append(.downloadStarted) }
        if previous != "complete", current == "complete" {
            result.append(.downloadCompleted)
        }
        return result
    }

    nonisolated static func newMailCount(previousIDs: Set<String>, currentIDs: Set<String>, hasBaseline: Bool) -> Int {
        guard hasBaseline else { return 0 }
        return currentIDs.subtracting(previousIDs).count
    }
}
