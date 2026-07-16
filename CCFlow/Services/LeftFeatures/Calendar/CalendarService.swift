import EventKit
import Combine
import Foundation

struct CalendarAgendaItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarName: String
}

struct ReminderAgendaItem: Identifiable, Equatable {
    let id: String
    let title: String
    let dueDate: Date?
    let priority: Int
}

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    @Published private(set) var events: [CalendarAgendaItem] = []
    @Published private(set) var authorization = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var reminderAuthorization = EKEventStore.authorizationStatus(for: .reminder)
    @Published private(set) var reminders: [ReminderAgendaItem] = []
    @Published private(set) var errorMessage: String?
    private let store = EKEventStore()

    private init() {}

    func requestAccess() {
        Task {
            do {
                if #available(macOS 14, *) { _ = try await store.requestFullAccessToEvents() }
                authorization = EKEventStore.authorizationStatus(for: .event)
                refresh()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func requestReminderAccess() {
        Task {
            do {
                if #available(macOS 14, *) { _ = try await store.requestFullAccessToReminders() }
                reminderAuthorization = EKEventStore.authorizationStatus(for: .reminder)
                refreshReminders()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func refresh(referenceDate: Date = Date()) {
        authorization = EKEventStore.authorizationStatus(for: .event)
        guard authorization == .fullAccess || authorization == .authorized else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        guard let end = calendar.date(byAdding: .day, value: 31, to: start) else { return }
        events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .map {
                CalendarAgendaItem(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "无标题",
                                   start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay,
                                   calendarName: $0.calendar.title)
            }
            .sorted { $0.start < $1.start }
        errorMessage = nil
        refreshReminders()
    }

    private func refreshReminders() {
        reminderAuthorization = EKEventStore.authorizationStatus(for: .reminder)
        guard reminderAuthorization == .fullAccess || reminderAuthorization == .authorized else { return }
        store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { [weak self] values in
            Task { @MainActor in
                self?.reminders = (values ?? []).map {
                    ReminderAgendaItem(id: $0.calendarItemIdentifier, title: $0.title, dueDate: $0.dueDateComponents?.date, priority: $0.priority)
                }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            }
        }
    }

    var nextEvent: CalendarAgendaItem? { events.first { $0.end >= Date() } }
}
