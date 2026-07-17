import Foundation

nonisolated struct UsageCompactBrandPresentation: Equatable, Sendable {
    let provider: UsageProviderID
    let remainingPercentage: Int
}

nonisolated enum UsageCompactBrandPresentationResolver {
    static func resolve(snapshot: UsageSnapshot?) -> [UsageCompactBrandPresentation] {
        UsageProviderID.allCases.compactMap { provider in
            guard let providerSnapshot = snapshot?.providers.first(where: { $0.provider == provider }),
                  let remaining = providerSnapshot.windows.map(\.remainingPercentage).min(),
                  remaining.isFinite else {
                return nil
            }

            return UsageCompactBrandPresentation(
                provider: provider,
                remainingPercentage: Int(max(0, min(100, remaining)).rounded())
            )
        }
    }
}
