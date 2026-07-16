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
    private var systemPaused = false
    private var idlePaused = false
    private var idleTimer: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var durations: [String: TimeInterval] = [:]
    private var names: [String: String] = [:]
    private let defaults = UserDefaults.standard
    private var storageDayKey = ""
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
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.setSystemPaused(true, at: Date()) } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.setSystemPaused(false, at: Date()) } })
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.setSystemPaused(true, at: Date()) } })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.setSystemPaused(false, at: Date()) } })
        idleTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.refreshIdleState(at: Date()) }
    }

    func stop() {
        guard started else { return }
        commit(until: Date()); started = false
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll(); activeSince = nil; activeBundleID = nil
        idleTimer?.cancel(); idleTimer = nil; systemPaused = false; idlePaused = false; isPaused = false
    }

    private func activate(_ app: NSRunningApplication?, at date: Date) {
        commit(until: date)
        activeBundleID = app?.bundleIdentifier ?? "pid:\(app?.processIdentifier ?? 0)"
        activeName = app?.localizedName ?? "未知应用"
        activeSince = isPaused ? nil : date
    }

    private func setSystemPaused(_ paused: Bool, at date: Date) { systemPaused = paused; updatePauseState(at: date) }
    private func refreshIdleState(at date: Date) { idlePaused = SystemUserIdleTimeReader.idleTime() >= 300; updatePauseState(at: date) }
    private func updatePauseState(at date: Date) {
        let shouldPause = systemPaused || idlePaused
        guard shouldPause != isPaused else { return }
        if shouldPause { commit(until: date); isPaused = true; activeSince = nil }
        else { isPaused = false; activate(NSWorkspace.shared.frontmostApplication, at: date) }
    }

    private func commit(until date: Date) {
        guard let bundleID = activeBundleID, let since = activeSince, date > since else { return }
        let boundary = Calendar.current.startOfDay(for: date)
        if since < boundary {
            durations[bundleID, default: 0] += max(0, boundary.timeIntervalSince(since))
            names[bundleID] = activeName; publish(); persist()
            durations.removeAll(); names.removeAll(); storageDayKey = Self.dayKey(for: date)
            activeSince = boundary
        }
        let effectiveSince = activeSince ?? since
        let seconds = min(date.timeIntervalSince(effectiveSince), 60 * 60 * 8)
        durations[bundleID, default: 0] += seconds; names[bundleID] = activeName
        activeSince = date; publish(); persist()
    }

    private func publish() {
        today = durations.map { AppUsageEntry(bundleID: $0.key, name: names[$0.key] ?? $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    nonisolated private static func dayKey(for date: Date) -> String { date.formatted(.iso8601.year().month().day()) }
    private func persist() { defaults.set(durations, forKey: "productivity.appUsage.\(storageDayKey)"); defaults.set(names, forKey: "productivity.appUsageNames.\(storageDayKey)") }
    private func loadToday() {
        storageDayKey = Self.dayKey(for: Date())
        durations = defaults.dictionary(forKey: "productivity.appUsage.\(storageDayKey)") as? [String: TimeInterval] ?? [:]
        names = defaults.dictionary(forKey: "productivity.appUsageNames.\(storageDayKey)") as? [String: String] ?? [:]
        publish()
    }
}
