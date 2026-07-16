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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("系统监控", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("每 2 秒更新")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                metricCard(title: "CPU", value: percent(service.snapshot.cpuPercent),
                           detail: "\(service.snapshot.processorCount) 核", color: .green)
                metricCard(title: "内存", value: percent(service.snapshot.memoryPercent),
                           detail: "\(bytes(service.snapshot.memoryUsed)) / \(bytes(service.snapshot.memoryTotal))",
                           color: .cyan)
                metricCard(title: "磁盘", value: percent(service.snapshot.diskPercent),
                           detail: "\(bytes(UInt64(max(0, service.snapshot.diskUsed)))) / \(bytes(UInt64(max(0, service.snapshot.diskTotal))))",
                           color: .yellow)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack { Label("网络", systemImage: "network"); Spacer()
                    Text("↓ \(rate(service.snapshot.networkDownloadBytesPerSecond))   ↑ \(rate(service.snapshot.networkUploadBytesPerSecond))")
                        .monospacedDigit() }
                    .font(.system(size: 11, weight: .semibold))
                Text("系统负载")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    loadValue("1 分钟", service.snapshot.loadOne)
                    loadValue("5 分钟", service.snapshot.loadFive)
                    loadValue("15 分钟", service.snapshot.loadFifteen)
                }
            }
            .padding(12)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

            if !usage.today.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今日应用使用（从启用后累计）").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(usage.today.prefix(4)) { item in
                        HStack { Text(item.name).lineLimit(1); Spacer(); Text(duration(item.seconds)).monospacedDigit().foregroundStyle(.secondary) }
                            .font(.system(size: 10))
                    }
                }.padding(12).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func compactMetric(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).foregroundStyle(.secondary)
            Text(percent(value)).monospacedDigit().foregroundStyle(.primary)
        }
        .font(.system(size: 10, weight: .semibold))
    }

    private func metricCard(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(color).frame(width: proxy.size.width * progress(value))
                }
            }
            .frame(height: 5)
            Text(detail).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func loadValue(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.2f", value)).font(.system(size: 16, weight: .bold, design: .monospaced))
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func progress(_ formattedPercent: String) -> Double {
        min(max(Double(formattedPercent.dropLast()) ?? 0, 0), 100) / 100
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
}
