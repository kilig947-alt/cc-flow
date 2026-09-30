import Combine
import Foundation

enum ProductivityProactiveEventKind: String, Equatable, Sendable {
    case calendarReminderDue
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

    @Published private(set) var pendingEvents: [ProductivityProactiveEvent] = []
    let queueDidChange = PassthroughSubject<Void, Never>()

    var latestEvent: ProductivityProactiveEvent? { pendingEvents.last }
    var nextEvent: ProductivityProactiveEvent? { pendingEvents.first }

    private let shouldAcceptEvent: (String) -> Bool
    private var nextSequence = 0
    private var consumedSequences: Set<Int> = []

    init(shouldAcceptEvent: ((String) -> Bool)? = nil) {
        self.shouldAcceptEvent = shouldAcceptEvent ?? { featureID in
            !AppSettings.areReminderNotificationsSuppressed
                && LeftFeatureStore.shared.features.contains { $0.id == featureID && $0.isEnabled }
        }
    }

    func publish(targetFeatureID: String, kind: ProductivityProactiveEventKind, summary: String, count: Int = 1) {
        guard shouldAcceptEvent(targetFeatureID) else { return }
        nextSequence &+= 1
        pendingEvents.append(ProductivityProactiveEvent(
            sequence: nextSequence,
            targetFeatureID: targetFeatureID,
            kind: kind,
            summary: summary,
            count: max(1, count),
            createdAt: Date()
        ))
        trimOverflowIfNeeded()
        queueDidChange.send()
    }

    func consume(_ sequence: Int) -> Bool {
        guard !consumedSequences.contains(sequence),
              pendingEvents.contains(where: { $0.sequence == sequence }) else { return false }
        consumedSequences.insert(sequence)
        pendingEvents.removeAll { $0.sequence == sequence }
        queueDidChange.send()
        return true
    }

    private func trimOverflowIfNeeded() {
        if pendingEvents.count > 100 {
            let overflowCount = pendingEvents.count - 100
            let removed = Array(pendingEvents.prefix(overflowCount))
            pendingEvents.removeFirst(overflowCount)
            consumedSequences.formUnion(removed.map(\.sequence))
        }
    }

}
