import EventKit
import SwiftUI

struct CalendarFeatureView: View {
    let compact: Bool
    @ObservedObject private var service = CalendarService.shared
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDate = Date()

    var body: some View {
        Group {
            if service.authorization == .fullAccess || service.authorization == .authorized {
                compact ? AnyView(compactContent) : AnyView(expandedContent)
            } else {
                permissionContent
            }
        }
        .onAppear { service.refresh(referenceDate: displayedMonth) }
    }

    private var compactContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
            if !service.actionableReminders.isEmpty {
                Text("\(service.actionableReminders.count) 项待办到期").fontWeight(.semibold)
            } else if let event = service.nextEvent {
                Text(event.title).lineLimit(1)
                Text(event.isAllDay ? "全天" : event.start.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary).monospacedDigit()
            } else { Text("近期无日程").foregroundStyle(.secondary) }
        }.font(.system(size: 10, weight: .semibold))
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("日历", systemImage: "calendar").font(.headline)
                Spacer()
                Button("今天") {
                    let today = Date()
                    selectedDate = today
                    displayedMonth = Calendar.current.dateInterval(of: .month, for: today)?.start ?? today
                    service.refresh(referenceDate: today)
                }
                Button { service.refresh(referenceDate: displayedMonth) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).frame(width: 44, height: 44)
            }
            HStack(alignment: .top, spacing: 12) {
                monthPanel.frame(maxWidth: .infinity, maxHeight: .infinity)
                agendaPanel.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(16).onAppear { service.startReminderMonitoring() }
    }

    private var monthPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year())).font(.title3.bold())
                Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
            }.buttonStyle(.plain)
            HStack { ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(monthDates, id: \.self) { date in
                    if let date {
                        dayButton(date)
                    } else { Color.clear.frame(height: 34) }
                }
            }
            Spacer(minLength: 0)
        }.padding(14).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private var agendaPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day())).font(.title3.bold())
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(eventsForSelectedDate) { event in
                        HStack { Circle().fill(.green).frame(width: 8, height: 8)
                            VStack(alignment: .leading) { Text(event.title).fontWeight(.semibold)
                                Text(event.isAllDay ? "全天 · \(event.calendarName)" : event.start.formatted(date: .omitted, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }; Spacer()
                        }.padding(9).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    }
                    Divider().padding(.vertical, 4)
                    HStack { Label("提醒事项", systemImage: "checklist").fontWeight(.semibold); Spacer()
                        if service.reminderAuthorization != .fullAccess && service.reminderAuthorization != .authorized {
                            Button("授权") { service.requestReminderAccess() }
                        }
                    }
                    if service.actionableReminders.isEmpty {
                        Text("今天没有到期的待办").foregroundStyle(.secondary).font(.caption)
                    }
                    ForEach(service.actionableReminders) { reminder in
                        Button { service.completeReminder(reminder) } label: {
                            HStack { Image(systemName: "circle"); Text(reminder.title).lineLimit(2); Spacer()
                                if let due = reminder.dueDate { Text(due, style: .date).font(.caption2).foregroundStyle(.secondary) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("标记为已完成并同步到 macOS 提醒事项")
                    }
                    if let error = service.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
        }.padding(14).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private var eventsForSelectedDate: [CalendarAgendaItem] {
        let day = Calendar.current.dateInterval(of: .day, for: selectedDate)
        return service.events.filter { event in
            guard let day else { return false }
            return event.start < day.end && event.end > day.start
        }
    }

    private var monthDates: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else { return [] }
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: first)
        }.map(Optional.some)
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let firstIndex = min(max(calendar.firstWeekday - 1, 0), symbols.count - 1)
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let interval = Calendar.current.dateInterval(of: .day, for: date)
        let hasContent = service.events.contains { event in interval.map { event.start < $0.end && event.end > $0.start } ?? false }
            || service.reminders.contains { $0.dueDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }
        return Button { selectedDate = date } label: {
            VStack(spacing: 2) { Text(date.formatted(.dateTime.day())).fontWeight(selected ? .bold : .regular)
                Circle().fill(hasContent ? Color.green : .clear).frame(width: 4, height: 4)
            }.frame(maxWidth: .infinity, minHeight: 32).background(selected ? Color.green.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }

    private func changeMonth(_ offset: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        let desiredDay = Calendar.current.component(.day, from: selectedDate)
        displayedMonth = next
        let range = Calendar.current.range(of: .day, in: .month, for: next)
        selectedDate = Calendar.current.date(bySetting: .day, value: min(desiredDay, range?.count ?? 1), of: next) ?? next
        service.refresh(referenceDate: next)
    }

    private var permissionContent: some View {
        VStack(spacing: compact ? 4 : 10) {
            Label("需要日历权限", systemImage: "calendar.badge.exclamationmark")
            Button("授权访问") { service.requestAccess() }.buttonStyle(.borderedProminent)
        }
        .font(.system(size: compact ? 10 : 13, weight: .semibold))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
