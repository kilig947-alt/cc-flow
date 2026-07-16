import Combine
import Darwin
import Foundation

struct SystemMonitorSnapshot: Equatable {
    var cpuPercent: Double = 0
    var memoryPercent: Double = 0
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var loadOne: Double = 0
    var loadFive: Double = 0
    var loadFifteen: Double = 0
    var processorCount: Int = 0
    var diskUsed: Int64 = 0
    var diskTotal: Int64 = 0
    var networkDownloadBytesPerSecond: Double = 0
    var networkUploadBytesPerSecond: Double = 0

    var diskPercent: Double {
        guard diskTotal > 0 else { return 0 }
        return min(max(Double(diskUsed) / Double(diskTotal) * 100, 0), 100)
    }
}

@MainActor
final class SystemMonitorService: ObservableObject {
    static let shared = SystemMonitorService()

    @Published private(set) var snapshot = SystemMonitorSnapshot()
    private var timer: AnyCancellable?
    private var consumers = 0
    private var previousNetwork: (received: UInt64, sent: UInt64, date: Date)?

    private init() {}

    func start() {
        consumers += 1
        guard timer == nil else { return }
        refresh()
        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func stop() {
        consumers = max(0, consumers - 1)
        guard consumers == 0 else { return }
        timer?.cancel()
        timer = nil
    }

    private func refresh() {
        let metrics = SystemMetricsProvider.shared.sample()
        let disk = Self.diskCapacity()
        let now = Date()
        let network = Self.networkTotals()
        var downloadRate = 0.0, uploadRate = 0.0
        if let previousNetwork {
            let elapsed = max(now.timeIntervalSince(previousNetwork.date), 0.001)
            if network.received >= previousNetwork.received { downloadRate = Double(network.received - previousNetwork.received) / elapsed }
            if network.sent >= previousNetwork.sent { uploadRate = Double(network.sent - previousNetwork.sent) / elapsed }
        }
        previousNetwork = (network.received, network.sent, now)
        snapshot = SystemMonitorSnapshot(
            cpuPercent: metrics.cpu,
            memoryPercent: metrics.memoryPercent,
            memoryUsed: metrics.memoryUsed,
            memoryTotal: metrics.memoryTotal,
            loadOne: metrics.loadOne,
            loadFive: metrics.loadFive,
            loadFifteen: metrics.loadFifteen,
            processorCount: metrics.cores,
            diskUsed: disk.used,
            diskTotal: disk.total,
            networkDownloadBytesPerSecond: downloadRate,
            networkUploadBytesPerSecond: uploadRate
        )
    }

    nonisolated static func diskCapacity(
        for url: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) -> (used: Int64, total: Int64) {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return (0, 0)
        }
        let total64 = Int64(total)
        return (max(0, total64 - available), total64)
    }

    nonisolated static func networkTotals() -> (received: UInt64, sent: UInt64) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }
        var received: UInt64 = 0, sent: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            let value = interface.pointee
            if value.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               value.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
               let data = value.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                received += UInt64(data.ifi_ibytes); sent += UInt64(data.ifi_obytes)
            }
            current = value.ifa_next
        }
        return (received, sent)
    }
}
