import AppKit
import Combine
import Foundation

struct AppUsageEntry: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let seconds: TimeInterval
    var id: String { bundleID }
}

@MainActor
final class AppUsageTracker: ObservableObject {
    static let shared = AppUsageTracker()
    @Published private(set) var today: [AppUsageEntry] = []
    private var activeBundleID: String?
    private var activeName: String?
    private var activeSince: Date?
    private var isPaused = false
    private var observers: [NSObjectProtocol] = []
    private var durations: [String: TimeInterval] = [:]
    private var names: [String: String] = [:]
    private let defaults = UserDefaults.standard
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true; loadToday(); activate(NSWorkspace.shared.frontmostApplication, at: Date())
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activate(app, at: Date()) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.pause(at: Date()) } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.resume(at: Date()) } })
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.pause(at: Date()) } })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.resume(at: Date()) } })
    }

    func stop() {
        guard started else { return }
        commit(until: Date()); started = false
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll(); activeSince = nil; activeBundleID = nil
    }

    private func activate(_ app: NSRunningApplication?, at date: Date) {
        commit(until: date)
        activeBundleID = app?.bundleIdentifier ?? "pid:\(app?.processIdentifier ?? 0)"
        activeName = app?.localizedName ?? "未知应用"
        activeSince = isPaused ? nil : date
    }

    private func pause(at date: Date) { guard !isPaused else { return }; commit(until: date); isPaused = true; activeSince = nil }
    private func resume(at date: Date) { guard isPaused else { return }; isPaused = false; activate(NSWorkspace.shared.frontmostApplication, at: date) }

    private func commit(until date: Date) {
        guard let bundleID = activeBundleID, let since = activeSince, date > since else { return }
        let seconds = min(date.timeIntervalSince(since), 60 * 60 * 8)
        durations[bundleID, default: 0] += seconds; names[bundleID] = activeName
        activeSince = date; publish(); persist()
    }

    private func publish() {
        today = durations.map { AppUsageEntry(bundleID: $0.key, name: names[$0.key] ?? $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    private var dayKey: String { Date().formatted(.iso8601.year().month().day()) }
    private func persist() { defaults.set(durations, forKey: "productivity.appUsage.\(dayKey)"); defaults.set(names, forKey: "productivity.appUsageNames.\(dayKey)") }
    private func loadToday() {
        durations = defaults.dictionary(forKey: "productivity.appUsage.\(dayKey)") as? [String: TimeInterval] ?? [:]
        names = defaults.dictionary(forKey: "productivity.appUsageNames.\(dayKey)") as? [String: String] ?? [:]
        publish()
    }
}
