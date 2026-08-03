import SwiftUI

struct SystemMonitorFeatureView: View {
    let compact: Bool

    @ObservedObject private var service = SystemMonitorService.shared
    @ObservedObject private var usage = AppUsageTracker.shared

    var body: some View {
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
            compactMetric(label: "内存", value: service.snapshot.memoryPercent, color: .cyan)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "CPU \(percent(service.snapshot.cpuPercent))，内存 \(percent(service.snapshot.memoryPercent))"
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
                Label(healthTitle, systemImage: "circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(healthColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(uptime(service.snapshot.uptime))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Text("运行时间 · 每 2 秒更新")
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
            monitorRow("整体", value: service.snapshot.cpuPercent, color: .green)
            HStack(spacing: 10) {
                detailValue("核心数量", "\(service.snapshot.processorCount) 核")
                detailValue("系统负载", String(format: "%.2f", service.snapshot.loadOne))
            }
            Text("5 分钟 \(String(format: "%.2f", service.snapshot.loadFive))  ·  15 分钟 \(String(format: "%.2f", service.snapshot.loadFifteen))")
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
            sectionHeader("内存", icon: "memorychip")
            monitorRow("已使用", value: service.snapshot.memoryPercent, color: .yellow)
            HStack {
                detailValue("已用", bytes(service.snapshot.memoryUsed))
                detailValue("总内存", bytes(service.snapshot.memoryTotal))
                detailValue("交换空间", service.snapshot.swapTotal > 0 ? bytes(service.snapshot.swapUsed) : "无")
            }
        }
    }

    private var networkPanel: some View {
        monitorPanel {
            sectionHeader("网络", icon: "wifi")
            HStack {
                detailValue("下载", "↓ \(rate(service.snapshot.networkDownloadBytesPerSecond))", color: .green)
                detailValue("上传", "↑ \(rate(service.snapshot.networkUploadBytesPerSecond))", color: .cyan)
            }
            Divider().opacity(0.4)
            HStack {
                detailValue("磁盘读取", "↓ \(rate(service.snapshot.diskReadBytesPerSecond))", color: .cyan)
                detailValue("磁盘写入", "↑ \(rate(service.snapshot.diskWriteBytesPerSecond))", color: .orange)
            }
        }
    }

    private var batteryPanel: some View {
        monitorPanel {
            sectionHeader("电池", icon: "battery.75percent")
            monitorRow(batteryStateTitle,
                       value: service.snapshot.battery.percent,
                       color: batteryColor)
            HStack {
                detailValue("电量", percent(service.snapshot.battery.percent))
                detailValue("预计剩余", batteryRemaining)
            }
        }
    }

    private var gpuPanel: some View {
        monitorPanel {
            sectionHeader("GPU", icon: "square.3.layers.3d")
            monitorRow("整体", value: service.snapshot.gpuPercent ?? 0, color: .purple)
            Text("Apple Silicon 仅提供 GPU 聚合利用率")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var storagePanel: some View {
        monitorPanel {
            sectionHeader("存储", icon: "internaldrive")
            monitorRow("磁盘已用", value: service.snapshot.diskPercent, color: diskColor)
            HStack {
                detailValue("已用空间", bytes(UInt64(max(0, service.snapshot.diskUsed))))
                detailValue("可用空间", bytes(UInt64(service.snapshot.diskAvailable)))
                detailValue("总容量", bytes(UInt64(max(0, service.snapshot.diskTotal))))
            }
        }
    }

    private var applicationUsagePanel: some View {
        monitorPanel {
            sectionHeader("今日应用使用", icon: "clock")
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
            Text(label).foregroundStyle(.secondary)
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
        Label(title.uppercased(), systemImage: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(1.2)
    }

    private func monitorRow(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 56, alignment: .leading)
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
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced))
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
        return minutes >= 60 ? "\(minutes / 60)小时\(minutes % 60)分" : "\(minutes)分钟"
    }

    private func rate(_ value: Double) -> String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file))/s"
    }

    private func uptime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        return hours >= 24 ? "\(hours / 24)天 \(hours % 24)小时" : "\(hours)小时"
    }

    private var healthTitle: String {
        let snapshot = service.snapshot
        if snapshot.thermalState == .critical { return "系统温度严重过高" }
        if snapshot.diskPercent >= 95 { return "磁盘空间严重不足 · 已用 \(percent(snapshot.diskPercent))" }
        if snapshot.memoryPercent >= 95 { return "内存压力过高 · 已用 \(percent(snapshot.memoryPercent))" }
        if snapshot.thermalState == .serious { return "系统温度需要关注" }
        if snapshot.diskPercent >= 85 { return "磁盘空间需要关注 · 已用 \(percent(snapshot.diskPercent))" }
        if snapshot.memoryPercent >= 85 { return "内存需要关注 · 已用 \(percent(snapshot.memoryPercent))" }
        if snapshot.cpuPercent >= 85 { return "CPU 持续高负载 · \(percent(snapshot.cpuPercent))" }
        return "状态正常"
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
        guard let minutes = service.snapshot.battery.timeRemainingMinutes else { return "计算中" }
        return "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
    }

    private var batteryStateTitle: String {
        if service.snapshot.battery.isCharging { return "正在充电" }
        if service.snapshot.battery.isOnExternalPower { return "已接电源" }
        return "使用电池"
    }
}
