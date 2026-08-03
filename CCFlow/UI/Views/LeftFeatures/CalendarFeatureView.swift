import EventKit
import SwiftUI

struct CalendarFeatureView: View {
    let compact: Bool
    @ObservedObject private var service = CalendarService.shared
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDate = Date()
    @State private var expandedReminderID: String?

    var body: some View {
        Group {
            if service.authorization == .fullAccess || service.authorization == .authorized {
                compact ? AnyView(compactContent) : AnyView(expandedContent)
            } else {
                permissionContent
            }
        }
        .onAppear { service.refresh() }
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
                    selectedDate = Date()
                    displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
                }
                Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }
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
            let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
            HStack { ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
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
                        reminderRow(reminder)
                    }
                    if let error = service.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
        }.padding(14).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func reminderRow(_ reminder: ReminderAgendaItem) -> some View {
        let isExpanded = expandedReminderID == reminder.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Button {
                    service.completeReminder(reminder)
                    if isExpanded { expandedReminderID = nil }
                } label: {
                    Image(systemName: "circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("标记为已完成")
                .accessibilityLabel("完成：\(reminder.title)")
                .accessibilityHint("标记为已完成并同步到 macOS 提醒事项")

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        expandedReminderID = isExpanded ? nil : reminder.id
                    }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reminder.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(isExpanded ? nil : 2)
                            HStack(spacing: 5) {
                                if let due = reminder.dueDate {
                                    Text(due.formatted(date: .abbreviated, time: .shortened))
                                }
                                if reminder.calendarName != "提醒事项" {
                                    Text("· \(reminder.calendarName)")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(reminderDueColor(reminder))
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "收起待办详情" : "查看待办详情")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)

            if isExpanded {
                reminderDetails(reminder)
                    .padding(.leading, 31)
                    .padding(.trailing, 10)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            (isExpanded ? Color.green.opacity(0.10) : Color.white.opacity(0.035)),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }

    private func reminderDetails(_ reminder: ReminderAgendaItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let due = reminder.dueDate {
                Label(due.formatted(date: .complete, time: .shortened), systemImage: "clock")
            }
            Label(reminder.calendarName, systemImage: "list.bullet")
            if let priority = reminderPriorityText(reminder.priority) {
                Label(priority, systemImage: "flag")
            }
            if let notes = reminder.notes {
                VStack(alignment: .leading, spacing: 4) {
                    Label("备注", systemImage: "note.text")
                    Text(notes)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if let url = reminder.url {
                Link(destination: url) {
                    Label(url.host ?? url.absoluteString, systemImage: "link")
                        .lineLimit(1)
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reminderDueColor(_ reminder: ReminderAgendaItem) -> Color {
        guard let due = reminder.dueDate else { return .secondary }
        return due < Calendar.current.startOfDay(for: Date()) ? .orange : .secondary
    }

    private func reminderPriorityText(_ priority: Int) -> String? {
        switch priority {
        case 1...4: "高优先级"
        case 5: "中优先级"
        case 6...9: "低优先级"
        default: nil
        }
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
