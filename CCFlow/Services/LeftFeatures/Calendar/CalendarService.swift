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

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    @Published private(set) var events: [CalendarAgendaItem] = []
    @Published private(set) var authorization = EKEventStore.authorizationStatus(for: .event)
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
    }

    var nextEvent: CalendarAgendaItem? { events.first { $0.end >= Date() } }
}
