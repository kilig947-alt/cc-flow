import Foundation

struct SessionPendingDeliveryState: Equatable {
    private var acknowledgedIDs = Set<String>()

    mutating func undelivered(currentIDs: Set<String>) -> Set<String> {
        acknowledgedIDs.formIntersection(currentIDs)
        return currentIDs.subtracting(acknowledgedIDs)
    }

    mutating func acknowledge(_ ids: Set<String>) {
        acknowledgedIDs.formUnion(ids)
    }

    mutating func discard(_ ids: Set<String>) {
        acknowledge(ids)
    }
}
