import SwiftUI

struct SystemMonitorFeatureView: View {
    let compact: Bool

    @ObservedObject private var service = SystemMonitorService.shared
    @ObservedObject private var usage = AppUsageTracker.shared

    @Environment(\.locale) private var localizationLocale

    var body: some View {
        // Recompute formatted strings when the app language changes.
        let _ = localizationLocale
        Group {
            if compact { compactContent } else { expandedContent }
        }
        .onAppear { service.start() }
        .onDisappear { service.stop() }
    }

    private var compactContent: some View {
        HStack(spacing: 9) {
            Text("↓\(rate(service.snapshot.networkDownloadBytesPerSecond)) ↑\(rate(service.snapshot.networkUploadBytesPerSecond))")
                .foregroundStyle(.secondary).monospacedDigit()
            compactMetric(label: "CPU", value: service.snapshot.cpuPercent, color: .green)
            compactMetric(label: AppLocalization.runtimeString("system_monitor.memory"), value: service.snapshot.memoryPercent, color: .cyan)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            AppLocalization.format("system_monitor.cpu_memory", String(describing: percent(service.snapshot.cpuPercent)), String(describing: percent(service.snapshot.memoryPercent)))
        )
    }

    private var expandedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                dashboardHeader

                HStack(alignment: .top, spacing: 10) {
                    processorPanel
                    VStack(spacing: 10) {
                        networkPanel
                        if service.snapshot.gpuPercent != nil { gpuPanel }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                HStack(alignment: .top, spacing: 10) {
                    memoryPanel
                    storagePanel
                }

                if service.snapshot.battery.isPresent { batteryPanel }
                if !usage.today.isEmpty { applicationUsagePanel }
            }
            .padding(16)
        }
    }

    private var dashboardHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(service.snapshot.chipName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Label(LocalizedStringKey(healthTitle), systemImage: "circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(healthColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(uptime(service.snapshot.uptime))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Text("system_monitor.uptime_updates_every_2_seconds")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }

    private var processorPanel: some View {
        monitorPanel {
            sectionHeader("CPU", icon: "cpu")
            monitorRow(AppLocalization.runtimeString("system_monitor.overall"), value: service.snapshot.cpuPercent, color: .green)
            HStack(spacing: 10) {
                detailValue(AppLocalization.runtimeString("system_monitor.core_count"), AppLocalization.format("system_monitor.cores", String(describing: service.snapshot.processorCount)))
                detailValue(AppLocalization.runtimeString("system_monitor.system_load"), String(format: "%.2f", service.snapshot.loadOne))
            }
            Text(AppLocalization.format("system_monitor.duration_5_min_15_min", String(format: "%.2f", service.snapshot.loadFive), String(format: "%.2f", service.snapshot.loadFifteen)))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            if !service.snapshot.cpuCorePercentages.isEmpty {
                Divider().opacity(0.4)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    ForEach(Array(service.snapshot.cpuCorePercentages.enumerated()), id: \.offset) { index, value in
                        coreUsageRow(index: index, value: value)
                    }
                }
            }
        }
    }

    private var memoryPanel: some View {
        monitorPanel {
            sectionHeader(AppLocalization.runtimeString("system_monitor.memory"), icon: "memorychip")
            monitorRow(AppLocalization.runtimeString("system_monitor.used"), value: service.snapshot.memoryPercent, color: .yellow)
            HStack {
                detailValue(AppLocalization.runtimeString("system_monitor.used_2"), bytes(service.snapshot.memoryUsed))
                detailValue(AppLocalization.runtimeString("system_monitor.total_memory"), bytes(service.snapshot.memoryTotal))
                detailValue(AppLocalization.runtimeString("system_monitor.swap"), service.snapshot.swapTotal > 0 ? bytes(service.snapshot.swapUsed) : AppLocalization.runtimeString("system_monitor.none"))
            }
        }
    }

    private var networkPanel: some View {
        monitorPanel {
            sectionHeader(AppLocalization.runtimeString("system_monitor.network"), icon: "wifi")
            HStack {
                detailValue(AppLocalization.runtimeString("system_monitor.download"), "↓ \(rate(service.snapshot.networkDownloadBytesPerSecond))", color: .green)
                detailValue(AppLocalization.runtimeString("system_monitor.upload"), "↑ \(rate(service.snapshot.networkUploadBytesPerSecond))", color: .cyan)
            }
            Divider().opacity(0.4)
            HStack {
                detailValue(AppLocalization.runtimeString("system_monitor.disk_read"), "↓ \(rate(service.snapshot.diskReadBytesPerSecond))", color: .cyan)
                detailValue(AppLocalization.runtimeString("system_monitor.disk_write"), "↑ \(rate(service.snapshot.diskWriteBytesPerSecond))", color: .orange)
            }
        }
    }

    private var batteryPanel: some View {
        monitorPanel {
            sectionHeader(AppLocalization.runtimeString("system_monitor.battery"), icon: "battery.75percent")
            monitorRow(batteryStateTitle,
                       value: service.snapshot.battery.percent,
                       color: batteryColor)
            HStack {
                detailValue(AppLocalization.runtimeString("system_monitor.charge"), percent(service.snapshot.battery.percent))
                detailValue(AppLocalization.runtimeString("system_monitor.time_remaining"), batteryRemaining)
            }
        }
    }

    private var gpuPanel: some View {
        monitorPanel {
            sectionHeader("GPU", icon: "square.3.layers.3d")
            monitorRow(AppLocalization.runtimeString("system_monitor.overall"), value: service.snapshot.gpuPercent ?? 0, color: .purple)
            Text("system_monitor.apple_silicon_only_provides_aggregate_gpu_utilization")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var storagePanel: some View {
        monitorPanel {
            sectionHeader(AppLocalization.runtimeString("system_monitor.storage"), icon: "internaldrive")
            monitorRow(AppLocalization.runtimeString("system_monitor.disk_usage"), value: service.snapshot.diskPercent, color: diskColor)
            HStack {
                detailValue(AppLocalization.runtimeString("system_monitor.used_space"), bytes(UInt64(max(0, service.snapshot.diskUsed))))
                detailValue(AppLocalization.runtimeString("system_monitor.available_space"), bytes(UInt64(service.snapshot.diskAvailable)))
                detailValue(AppLocalization.runtimeString("system_monitor.total_capacity"), bytes(UInt64(max(0, service.snapshot.diskTotal))))
            }
        }
    }

    private var applicationUsagePanel: some View {
        monitorPanel {
            sectionHeader(AppLocalization.runtimeString("system_monitor.app_usage_today"), icon: "clock")
            ForEach(usage.today.prefix(4)) { item in
                HStack {
                    Text(item.name).lineLimit(1)
                    Spacer()
                    Text(duration(item.seconds)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.system(size: 10))
            }
        }
    }

    private func compactMetric(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(appLocalized: label).foregroundStyle(.secondary)
            Text(percent(value)).monospacedDigit().foregroundStyle(.primary)
        }
        .font(.system(size: 10, weight: .semibold))
    }

    private func monitorPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(AppLocalization.string(title).uppercased(), systemImage: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(1.2)
    }

    private func monitorRow(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(appLocalized: label).frame(width: 56, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(color).frame(width: proxy.size.width * min(max(value, 0), 100) / 100)
                }
            }
            .frame(height: 7)
            Text(percent(value)).fontWeight(.bold).monospacedDigit().frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 11))
    }

    private func coreUsageRow(index: Int, value: Double) -> some View {
        HStack(spacing: 7) {
            Text("C\(index)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.cyan)
                .frame(width: 20, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(.cyan).frame(width: proxy.size.width * min(max(value, 0), 100) / 100)
                }
            }
            .frame(height: 5)
            Text(percent(value))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 29, alignment: .trailing)
        }
    }

    private func detailValue(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(appLocalized: label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(appLocalized: value).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? AppLocalization.format("system_monitor.h_m", String(describing: minutes / 60), String(describing: minutes % 60)) : AppLocalization.format("system_monitor.m", String(describing: minutes))
    }

    private func rate(_ value: Double) -> String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file))/s"
    }

    private func uptime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        return hours >= 24 ? AppLocalization.format("system_monitor.d_h", String(describing: hours / 24), String(describing: hours % 24)) : AppLocalization.format("system_monitor.h", String(describing: hours))
    }

    private var healthTitle: String {
        let snapshot = service.snapshot
        if snapshot.thermalState == .critical { return AppLocalization.runtimeString("system_monitor.critical_system_temperature") }
        if snapshot.diskPercent >= 95 { return AppLocalization.format("system_monitor.critically_low_disk_space_used", String(describing: percent(snapshot.diskPercent))) }
        if snapshot.memoryPercent >= 95 { return AppLocalization.format("system_monitor.high_memory_pressure_used", String(describing: percent(snapshot.memoryPercent))) }
        if snapshot.thermalState == .serious { return AppLocalization.runtimeString("system_monitor.elevated_system_temperature") }
        if snapshot.diskPercent >= 85 { return AppLocalization.format("system_monitor.low_disk_space_used", String(describing: percent(snapshot.diskPercent))) }
        if snapshot.memoryPercent >= 85 { return AppLocalization.format("system_monitor.high_memory_usage_used", String(describing: percent(snapshot.memoryPercent))) }
        if snapshot.cpuPercent >= 85 { return AppLocalization.format("system_monitor.sustained_high_cpu_load", String(describing: percent(snapshot.cpuPercent))) }
        return AppLocalization.runtimeString("system_monitor.normal")
    }

    private var healthColor: Color {
        switch service.snapshot.healthLevel {
        case .normal: return .green
        case .attention: return .yellow
        case .critical: return .red
        }
    }

    private var diskColor: Color {
        service.snapshot.diskPercent >= 95 ? .red : service.snapshot.diskPercent >= 85 ? .yellow : .orange
    }

    private var batteryColor: Color {
        let value = service.snapshot.battery.percent
        return value <= 15 ? .red : value <= 30 ? .yellow : .green
    }

    private var batteryRemaining: String {
        guard let minutes = service.snapshot.battery.timeRemainingMinutes else { return AppLocalization.runtimeString("system_monitor.calculating") }
        return "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
    }

    private var batteryStateTitle: String {
        if service.snapshot.battery.isCharging { return AppLocalization.runtimeString("system_monitor.charging") }
        if service.snapshot.battery.isOnExternalPower { return AppLocalization.runtimeString("system_monitor.plugged_in") }
        return AppLocalization.runtimeString("system_monitor.on_battery")
    }
}
