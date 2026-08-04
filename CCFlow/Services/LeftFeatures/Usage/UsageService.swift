import Combine
import Foundation

@MainActor
final class UsageService: ObservableObject {
    static let shared = UsageService()

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var loaderTask: Task<UsageSnapshot, Never>?
    private var refreshGeneration = 0
    private var cancellables = Set<AnyCancellable>()
    private var wasEnergySuspended = false
    private let cacheURL = BridgeRuntimePaths.runtimeDirectoryURL.appendingPathComponent("usage-snapshot.json")

    private init() {
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(UsageSnapshot.self, from: data) {
            snapshot = cached
        }
        EnergyGovernor.shared.$policy
            .sink { [weak self] policy in
                guard let self else { return }
                let isSuspended = policy.usageRefreshInterval == nil
                if self.wasEnergySuspended && !isSuspended && self.isRunning,
                   self.snapshot.map({ Date().timeIntervalSince($0.capturedAt) >= 600 }) ?? true {
                    Task { await self.refresh(reason: .passive) }
                }
                self.wasEnergySuspended = isSuspended
            }
            .store(in: &cancellables)
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil,
              LeftFeatureStore.shared.features.contains(where: {
                  $0.id == LeftFeature.usageID && $0.isEnabled
              }) else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard EnergyGovernor.shared.policy.usageRefreshInterval != nil else { return }
                await self?.refresh(reason: .passive)
            }
        }
        if snapshot == nil || snapshot.map({ Date().timeIntervalSince($0.capturedAt) > 600 }) == true {
            Task { await refresh(reason: .passive) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        loaderTask?.cancel()
        loaderTask = nil
        CodexAppServerUsageClient.cancelCurrentRequest()
        isRefreshing = false
    }

    func refresh(reason: UsageRefreshReason) async {
        guard LeftFeatureStore.shared.features.contains(where: {
            $0.id == LeftFeature.usageID && $0.isEnabled
        }) else { return }
        if let refreshTask {
            await refreshTask.value
            return
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        let task = Task { [weak self] in
            guard let self else { return }
            let sessions = await SessionStore.shared.allSessions()
            let currentSessions = sessions
                .filter {
                    if case .ended = $0.phase { return false }
                    return $0.provider == .claude
                        || $0.provider == .codex
                        || $0.provider == .antigravity
                }
                .sorted { $0.lastActivity > $1.lastActivity }
            var currentSessionIDs: [UsageProviderID: String] = [:]
            var currentSessionPaths: [UsageProviderID: String] = [:]
            for session in currentSessions {
                let provider: UsageProviderID
                switch session.provider {
                case .claude: provider = .claude
                case .codex: provider = .codex
                case .antigravity: provider = .antigravity
                case .trae, .opencode: continue
                }
                guard currentSessionIDs[provider] == nil else { continue }
                currentSessionIDs[provider] = session.sessionId
                currentSessionPaths[provider] = session.clientInfo.sessionFilePath
            }
            guard !Task.isCancelled, self.refreshGeneration == generation else { return }
            let loader = Task.detached(priority: reason == .passive ? .utility : .userInitiated) {
                UsageDataLoader.load(
                    queryAntigravityAccount: true,
                    currentSessionIDs: currentSessionIDs,
                    currentSessionPaths: currentSessionPaths
                )
            }
            self.loaderTask = loader
            let loaded = await loader.value
            guard !Task.isCancelled,
                  self.refreshGeneration == generation,
                  LeftFeatureStore.shared.features.contains(where: {
                      $0.id == LeftFeature.usageID && $0.isEnabled
                  }) else { return }
            let merged = Self.mergingLastSuccess(new: loaded, previous: self.snapshot)
            self.snapshot = merged
            self.persist(merged)
        }
        refreshTask = task
        await task.value
        if refreshGeneration == generation {
            refreshTask = nil
            loaderTask = nil
            isRefreshing = false
        }
    }

    private func persist(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }

    nonisolated static func mergingLastSuccess(
        new: UsageSnapshot,
        previous: UsageSnapshot?
    ) -> UsageSnapshot {
        guard let previous else { return new }
        let providers = new.providers.map { incoming -> ProviderUsageSnapshot in
            guard let old = previous.providers.first(where: { $0.provider == incoming.provider }) else {
                return incoming
            }
            var merged = incoming
            if incoming.windows.isEmpty, !old.windows.isEmpty {
                merged.windows = old.windows
                merged.capturedAt = old.capturedAt
                merged.accountState = .stale
                if merged.errorMessage == nil {
                    merged.errorMessage = "本次刷新未取得账户限额，显示上次成功数据"
                }
            }
            return merged
        }
        return UsageSnapshot(providers: providers, capturedAt: new.capturedAt)
    }
}
