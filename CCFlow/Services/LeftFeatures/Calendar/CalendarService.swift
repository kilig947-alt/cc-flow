import EventKit
import Combine
import Foundation
import AppKit

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
    @Published private(set) var reminderPromptToken = 0
    @Published private(set) var errorMessage: String?
    private let store = EKEventStore()
    private var eventReferenceDate = Date()
    private var reminderTimer: AnyCancellable?
    private var lifecycleCancellables: Set<AnyCancellable> = []
    private var consumedReminderPromptToken = 0
    private let lastPromptKey = "productivity.calendar.lastReminderPromptAt"
    private var lastReminderPromptAt: Date? {
        get { UserDefaults.standard.object(forKey: lastPromptKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastPromptKey) }
    }

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
        eventReferenceDate = referenceDate
        authorization = EKEventStore.authorizationStatus(for: .event)
        guard authorization == .fullAccess || authorization == .authorized else { return }
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: referenceDate)?.start ?? calendar.startOfDay(for: referenceDate)
        guard let end = calendar.date(byAdding: .day, value: 42, to: start) else { return }
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

    func startReminderMonitoring() {
        guard reminderTimer == nil else { return }
        reminderTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.refreshReminders()
        }
        NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)
            .merge(with: NotificationCenter.default.publisher(for: .NSCalendarDayChanged))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refresh(referenceDate: self.eventReferenceDate)
            }
            .store(in: &lifecycleCancellables)
        refreshReminders()
    }

    func stopReminderMonitoring() {
        reminderTimer?.cancel()
        reminderTimer = nil
        lifecycleCancellables.removeAll()
    }

    func refreshReminders() {
        reminderAuthorization = EKEventStore.authorizationStatus(for: .reminder)
        guard reminderAuthorization == .fullAccess || reminderAuthorization == .authorized else { return }
        store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { [weak self] values in
            Task { @MainActor in
                self?.reminders = (values ?? []).map {
                    ReminderAgendaItem(id: $0.calendarItemIdentifier, title: $0.title, dueDate: $0.dueDateComponents?.date, priority: $0.priority)
                }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                self?.evaluateReminderPrompt()
            }
        }
    }

    var actionableReminders: [ReminderAgendaItem] {
        Self.actionableReminders(reminders, now: Date())
    }

    nonisolated static func actionableReminders(_ reminders: [ReminderAgendaItem], now: Date, calendar: Calendar = .current) -> [ReminderAgendaItem] {
        let endOfToday = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: now)) ?? now
        return reminders.filter { reminder in
            guard let dueDate = reminder.dueDate else { return false }
            return dueDate <= endOfToday
        }
    }

    func completeReminder(_ item: ReminderAgendaItem) {
        guard reminderAuthorization == .fullAccess || reminderAuthorization == .authorized,
              let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        do {
            reminder.isCompleted = true
            reminder.completionDate = Date()
            try store.save(reminder, commit: true)
            reminders.removeAll { $0.id == item.id }
            evaluateReminderPrompt()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func consumeReminderPrompt(_ token: Int) -> Bool {
        guard token > consumedReminderPromptToken else { return false }
        consumedReminderPromptToken = token
        return true
    }

    private func evaluateReminderPrompt(now: Date = Date()) {
        guard !Self.actionableReminders(reminders, now: now).isEmpty else { return }
        guard lastReminderPromptAt.map({ now.timeIntervalSince($0) >= 30 * 60 }) ?? true else { return }
        lastReminderPromptAt = now
        reminderPromptToken &+= 1
    }

    var nextEvent: CalendarAgendaItem? { events.first { $0.end >= Date() } }
}
