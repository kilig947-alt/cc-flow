import Foundation
import IslandShared

protocol AgentProviderAdapter: Sendable {
    func installHooks() async throws
    func repairHooksIfNeeded() async
    func startMonitoring() async
    func submitInterventionResponse(_ response: InterventionDecision, request: InterventionRequest) async throws
}

struct TraeProviderAdapter: AgentProviderAdapter {
    let installer: HookInstaller

    func installHooks() async throws {
        try installer.installDefaultHookAssets()
    }

    func repairHooksIfNeeded() async {
        try? installer.installDefaultHookAssets()
    }

    func startMonitoring() async {}

    func submitInterventionResponse(_ response: InterventionDecision, request: InterventionRequest) async throws {}
}
