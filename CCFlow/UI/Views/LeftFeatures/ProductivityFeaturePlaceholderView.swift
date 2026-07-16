import SwiftUI

/// Temporary milestone-one surface used until each productivity service is connected.
/// Keeping the routing native from the first migration makes enable/disable and ordering testable.
struct ProductivityFeaturePlaceholderView: View {
    let feature: LeftFeature
    let compact: Bool

    var body: some View {
        if compact {
            HStack(spacing: 6) {
                Image(systemName: feature.systemImage)
                Text(feature.displayName)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 10) {
                Image(systemName: feature.systemImage)
                    .font(.system(size: 28, weight: .medium))
                Text(feature.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Text("功能尚未配置")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}
