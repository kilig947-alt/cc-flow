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
            item("calendar", "日历", event),
            item("reminders", "提醒事项", reminder),
        ]
    }

    private func item(_ id: String, _ name: String, _ status: EKAuthorizationStatus) -> ProductivityPermissionItem {
        switch status {
        case .fullAccess, .authorized: return ProductivityPermissionItem(id: id, name: name, status: "已授权", isReady: true)
        case .denied, .restricted: return ProductivityPermissionItem(id: id, name: name, status: "已拒绝", isReady: false)
        case .writeOnly: return ProductivityPermissionItem(id: id, name: name, status: "仅写入（需要完整访问）", isReady: false)
        case .notDetermined: return ProductivityPermissionItem(id: id, name: name, status: "尚未请求", isReady: false)
        @unknown default: return ProductivityPermissionItem(id: id, name: name, status: "未知", isReady: false)
        }
    }
}
