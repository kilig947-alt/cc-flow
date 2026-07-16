import EventKit
import SwiftUI

struct CalendarFeatureView: View {
    let compact: Bool
    @ObservedObject private var service = CalendarService.shared

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
            if let event = service.nextEvent {
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
                Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).frame(width: 44, height: 44)
            }
            if service.events.isEmpty {
                ContentUnavailableView("近期无日程", systemImage: "calendar.badge.checkmark")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(service.events) { event in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(spacing: 1) {
                                    Text(event.start.formatted(.dateTime.day())).font(.title3.bold())
                                    Text(event.start.formatted(.dateTime.month(.abbreviated))).font(.caption2)
                                }.frame(width: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title).font(.system(size: 12, weight: .semibold))
                                    Text(event.isAllDay ? "全天 · \(event.calendarName)" :
                                            "\(event.start.formatted(date: .omitted, time: .shortened)) · \(event.calendarName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }.padding(16)
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
