import Combine
import EventKit
import Foundation

struct ProductivityPermissionItem: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String
    let isReady: Bool
}

@MainActor
final class ProductivityPermissionCenter: ObservableObject {
    static let shared = ProductivityPermissionCenter()
    @Published private(set) var items: [ProductivityPermissionItem] = []
    private init() { refresh() }

    func refresh() {
        let event = EKEventStore.authorizationStatus(for: .event)
        let reminder = EKEventStore.authorizationStatus(for: .reminder)
        items = [
            item("calendar", AppLocalization.runtimeString("calendar.title"), event),
            item("reminders", AppLocalization.runtimeString("calendar.reminders"), reminder),
        ]
    }

    private func item(_ id: String, _ name: String, _ status: EKAuthorizationStatus) -> ProductivityPermissionItem {
        switch status {
        case .fullAccess, .authorized: return ProductivityPermissionItem(id: id, name: name, status: AppLocalization.runtimeString("common.authorized"), isReady: true)
        case .denied, .restricted: return ProductivityPermissionItem(id: id, name: name, status: AppLocalization.runtimeString("common.denied"), isReady: false)
        case .writeOnly: return ProductivityPermissionItem(id: id, name: name, status: AppLocalization.runtimeString("common.write_only_full_access_required"), isReady: false)
        case .notDetermined: return ProductivityPermissionItem(id: id, name: name, status: AppLocalization.runtimeString("common.not_requested"), isReady: false)
        @unknown default: return ProductivityPermissionItem(id: id, name: name, status: AppLocalization.runtimeString("translation.unknown"), isReady: false)
        }
    }
}
