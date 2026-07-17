import Foundation

nonisolated struct UsageCompactBrandPresentation: Equatable, Sendable {
    let provider: UsageProviderID
    let remainingPercentage: Int
}

nonisolated enum UsageCompactBrandPresentationResolver {
    static func resolve(snapshot: UsageSnapshot?) -> [UsageCompactBrandPresentation] {
        UsageProviderID.allCases.compactMap { provider in
            guard let providerSnapshot = snapshot?.providers.first(where: { $0.provider == provider }) else {
                return nil
            }
            let validWindows = providerSnapshot.windows.filter { $0.usedPercentage.isFinite }
            guard let remaining = validWindows.map(\.remainingPercentage).min() else {
                return nil
            }

            return UsageCompactBrandPresentation(
                provider: provider,
                remainingPercentage: Int(max(0, min(100, remaining)).rounded())
            )
        }
    }
}
