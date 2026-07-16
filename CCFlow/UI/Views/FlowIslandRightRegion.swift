import SwiftUI

struct FlowIslandProviderSummary {
    let sessions: [SessionState]

    func pendingCount(for provider: SessionProvider) -> Int {
        sessions.lazy.filter { $0.provider == provider && $0.needsAttention }.count
    }

    func pendingCount(for variant: TraeVariant) -> Int {
        sessions.lazy.filter { session in
            session.provider == .trae
                && session.needsAttention
                && TraeVariant.fromBundleIdentifier(session.clientInfo.bundleIdentifier) == variant
        }.count
    }

    func preferredSession(for provider: SessionProvider) -> SessionState? {
        let providerSessions = sessions.filter { $0.provider == provider }
        return providerSessions
            .filter(\.needsAttention)
            .max(by: { $0.lastActivity < $1.lastActivity })
            ?? providerSessions.max(by: { $0.lastActivity < $1.lastActivity })
    }

    var totalPendingCount: Int {
        [SessionProvider.claude, .codex, .trae]
            .map { pendingCount(for: $0) }
            .reduce(0, +)
    }
}

struct FlowIslandRightRegion: View {
    @ObservedObject private var sessionMonitor: SessionMonitor
    @State private var isTraeExpanded = true

    let isExpanded: Bool

    init(isExpanded: Bool, sessionMonitor: SessionMonitor) {
        self.isExpanded = isExpanded
        self.sessionMonitor = sessionMonitor
    }

    private var summary: FlowIslandProviderSummary {
        FlowIslandProviderSummary(sessions: sessionMonitor.instances)
    }

    var body: some View {
        if isExpanded {
            expandedContent
        } else {
            compactContent
        }
    }

    private var compactContent: some View {
        HStack(spacing: 4) {
            Image(systemName: "command")
                .font(.system(size: 11, weight: .semibold))
            if summary.totalPendingCount > 0 {
                Text("\(summary.totalPendingCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .frame(minWidth: 28)
        .accessibilityLabel("CC FLOW 待处理 \(summary.totalPendingCount)")
    }

    private var expandedContent: some View {
        VStack(alignment: .trailing, spacing: 5) {
            providerRow(.claude, icon: "sparkles")
            providerRow(.codex, icon: "terminal.fill")
            traeProviderRow

            if isTraeExpanded {
                ForEach(TraeVariant.allCases) { variant in
                    variantRow(variant)
                        .padding(.trailing, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func providerRow(_ provider: SessionProvider, icon: String) -> some View {
        let count = summary.pendingCount(for: provider)
        let session = summary.preferredSession(for: provider)

        return Button {
            guard let session else { return }
            Task { _ = await SessionLauncher.shared.activate(session) }
        } label: {
            rowLabel(name: provider.displayName, icon: icon, count: count, chevron: "arrow.right")
        }
        .buttonStyle(.plain)
        .disabled(session == nil)
        .opacity(session == nil ? 0.45 : 1)
        .help(session == nil ? "暂无 \(provider.displayName) 会话" : "跳回 \(provider.displayName)")
    }

    private var traeProviderRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isTraeExpanded.toggle()
            }
        } label: {
            rowLabel(
                name: SessionProvider.trae.displayName,
                icon: "rectangle.stack.fill",
                count: summary.pendingCount(for: SessionProvider.trae),
                chevron: isTraeExpanded ? "chevron.up" : "chevron.down"
            )
        }
        .buttonStyle(.plain)
        .help(isTraeExpanded ? "收起 TRAE 变体" : "展开 TRAE 变体")
    }

    private func rowLabel(name: String, icon: String, count: Int, chevron: String) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(count > 0 ? .white : .secondary)
                .frame(minWidth: 16, alignment: .trailing)

            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 12)

            Text(name)
                .font(.system(size: 10))
                .lineLimit(1)
                .frame(minWidth: 64, alignment: .leading)

            Image(systemName: chevron)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 12)
        }
        .foregroundColor(.white.opacity(0.82))
        .contentShape(Rectangle())
    }

    private func variantRow(_ variant: TraeVariant) -> some View {
        let count = summary.pendingCount(for: variant)

        return Button {
            TraeSessionLauncher.activate(variant)
        } label: {
            HStack(spacing: 5) {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 14, alignment: .trailing)
                Image(systemName: variant.iconSymbolName)
                    .font(.system(size: 9))
                    .frame(width: 11)
                Text(variant.displayName)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .frame(minWidth: 68, alignment: .leading)
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 10))
            }
            .foregroundColor(.white.opacity(count > 0 ? 0.76 : 0.42))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("跳回 \(variant.displayName)")
    }
}
