import Combine
import Darwin
import Foundation
import IOKit
import IOKit.ps

nonisolated enum SystemHealthLevel: Equatable {
    case normal
    case attention
    case critical
}

nonisolated struct BatterySnapshot: Equatable {
    var percent: Double = 0
    var isCharging = false
    var isOnExternalPower = false
    var isPresent = false
    var timeRemainingMinutes: Int?
}

nonisolated struct SystemMonitorSnapshot: Equatable {
    var cpuPercent: Double = 0
    var cpuCorePercentages: [Double] = []
    var gpuPercent: Double?
    var memoryPercent: Double = 0
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var loadOne: Double = 0
    var loadFive: Double = 0
    var loadFifteen: Double = 0
    var processorCount: Int = 0
    var diskUsed: Int64 = 0
    var diskTotal: Int64 = 0
    var networkDownloadBytesPerSecond: Double = 0
    var networkUploadBytesPerSecond: Double = 0
    var diskReadBytesPerSecond: Double = 0
    var diskWriteBytesPerSecond: Double = 0
    var battery = BatterySnapshot()
    var chipName: String = SystemMonitorService.chipName()
    var thermalState: Foundation.ProcessInfo.ThermalState = .nominal
    var uptime: TimeInterval = 0

    var diskPercent: Double {
        guard diskTotal > 0 else { return 0 }
        return min(max(Double(diskUsed) / Double(diskTotal) * 100, 0), 100)
    }

    var diskAvailable: Int64 { max(0, diskTotal - diskUsed) }

    var healthLevel: SystemHealthLevel {
        if diskPercent >= 95 || memoryPercent >= 95 || thermalState == .critical {
            return .critical
        }
        if diskPercent >= 85 || memoryPercent >= 85 || cpuPercent >= 85 || thermalState == .serious {
            return .attention
        }
        return .normal
    }
}

struct NetworkInterfaceCounter: Equatable {
    let received: UInt32
    let sent: UInt32
}

nonisolated struct DiskIOCounter: Equatable {
    let read: UInt64
    let written: UInt64
}

nonisolated struct CPUCoreTicks: Equatable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    var total: UInt64 { user + system + idle + nice }
    var used: UInt64 { user + system + nice }
}

@MainActor
final class SystemMonitorService: ObservableObject {
    static let shared = SystemMonitorService()

    @Published private(set) var snapshot = SystemMonitorSnapshot()
    private var timer: AnyCancellable?
    private var consumers = 0
    private var previousNetwork: (counters: [String: NetworkInterfaceCounter], date: Date)?
    private var previousDiskIO: (counter: DiskIOCounter, date: Date)?
    private var previousCPUCoreTicks: [CPUCoreTicks]?

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
        let swap = Self.swapUsage()
        let now = Date()
        let network = Self.networkCounters()
        let diskIO = Self.diskIOTotals()
        let cpuCoreTicks = Self.cpuCoreTicks()
        let cpuCorePercentages = previousCPUCoreTicks.map {
            Self.cpuCorePercentages(previous: $0, current: cpuCoreTicks)
        } ?? []
        previousCPUCoreTicks = cpuCoreTicks
        var downloadRate = 0.0, uploadRate = 0.0
        if let previousNetwork {
            let elapsed = max(now.timeIntervalSince(previousNetwork.date), 0.001)
            for (name, current) in network {
                guard let previous = previousNetwork.counters[name] else { continue }
                downloadRate += Double(Self.wrappedDelta(current.received, previous.received)) / elapsed
                uploadRate += Double(Self.wrappedDelta(current.sent, previous.sent)) / elapsed
            }
        }
        previousNetwork = (network, now)
        var diskReadRate = 0.0, diskWriteRate = 0.0
        if let previousDiskIO {
            let elapsed = max(now.timeIntervalSince(previousDiskIO.date), 0.001)
            diskReadRate = Double(Self.counterDelta(diskIO.read, previousDiskIO.counter.read)) / elapsed
            diskWriteRate = Double(Self.counterDelta(diskIO.written, previousDiskIO.counter.written)) / elapsed
        }
        previousDiskIO = (diskIO, now)
        snapshot = SystemMonitorSnapshot(
            cpuPercent: metrics.cpu,
            cpuCorePercentages: cpuCorePercentages,
            gpuPercent: Self.gpuUsagePercent(),
            memoryPercent: metrics.memoryPercent,
            memoryUsed: metrics.memoryUsed,
            memoryTotal: metrics.memoryTotal,
            swapUsed: swap.used,
            swapTotal: swap.total,
            loadOne: metrics.loadOne,
            loadFive: metrics.loadFive,
            loadFifteen: metrics.loadFifteen,
            processorCount: metrics.cores,
            diskUsed: disk.used,
            diskTotal: disk.total,
            networkDownloadBytesPerSecond: downloadRate,
            networkUploadBytesPerSecond: uploadRate,
            diskReadBytesPerSecond: diskReadRate,
            diskWriteBytesPerSecond: diskWriteRate,
            battery: Self.batteryStatus(),
            chipName: Self.chipName(),
            thermalState: Foundation.ProcessInfo.processInfo.thermalState,
            uptime: Foundation.ProcessInfo.processInfo.systemUptime
        )
    }

    nonisolated static func chipName() -> String {
        sysctlString("machdep.cpu.brand_string") ?? sysctlString("hw.model") ?? "Mac"
    }

    nonisolated static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    nonisolated static func batteryStatus() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatterySnapshot()
        }

        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  (values[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            let current = values[kIOPSCurrentCapacityKey] as? Double ?? 0
            let maximum = values[kIOPSMaxCapacityKey] as? Double ?? 0
            let percent = maximum > 0 ? current / maximum * 100 : current
            let state = values[kIOPSPowerSourceStateKey] as? String
            let charging = (values[kIOPSIsChargingKey] as? Bool) == true
            let minutesKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let rawMinutes = values[minutesKey] as? Int
            let minutes = rawMinutes.flatMap { $0 >= 0 ? $0 : nil }

            return BatterySnapshot(
                percent: min(max(percent, 0), 100),
                isCharging: charging,
                isOnExternalPower: state == kIOPSACPowerValue,
                isPresent: true,
                timeRemainingMinutes: minutes
            )
        }
        return BatterySnapshot()
    }

    nonisolated static func diskIOTotals() -> DiskIOCounter {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else {
            return DiskIOCounter(read: 0, written: 0)
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return DiskIOCounter(read: 0, written: 0)
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            guard let property = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else { continue }
            read += (property["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written += (property["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return DiskIOCounter(read: read, written: written)
    }

    nonisolated static func cpuCoreTicks() -> [CPUCoreTicks] {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        guard host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        ) == KERN_SUCCESS, let processorInfo else { return [] }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: processorInfo)),
                vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        return (0..<Int(processorCount)).map { index in
            let offset = index * Int(CPU_STATE_MAX)
            return CPUCoreTicks(
                user: UInt64(processorInfo[offset + Int(CPU_STATE_USER)]),
                system: UInt64(processorInfo[offset + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(processorInfo[offset + Int(CPU_STATE_IDLE)]),
                nice: UInt64(processorInfo[offset + Int(CPU_STATE_NICE)])
            )
        }
    }

    nonisolated static func cpuCorePercentages(
        previous: [CPUCoreTicks],
        current: [CPUCoreTicks]
    ) -> [Double] {
        guard previous.count == current.count else { return [] }
        return zip(previous, current).map { previous, current in
            let totalDelta = counterDelta(current.total, previous.total)
            let usedDelta = counterDelta(current.used, previous.used)
            guard totalDelta > 0 else { return 0 }
            return min(max(Double(usedDelta) / Double(totalDelta) * 100, 0), 100)
        }
    }

    nonisolated static func gpuUsagePercent() -> Double? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var values: [Double] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any],
                  let value = property["Device Utilization %"] as? NSNumber else { continue }
            values.append(value.doubleValue)
        }
        return values.max().map { min(max($0, 0), 100) }
    }

    nonisolated static func counterDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private nonisolated static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
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
        networkCounters().values.reduce(into: (received: UInt64(0), sent: UInt64(0))) {
            $0.received += UInt64($1.received); $0.sent += UInt64($1.sent)
        }
    }

    nonisolated static func wrappedDelta(_ current: UInt32, _ previous: UInt32) -> UInt64 {
        if current >= previous { return UInt64(current - previous) }
        return UInt64(UInt32.max - previous) + UInt64(current) + 1
    }

    nonisolated static func networkCounters() -> [String: NetworkInterfaceCounter] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [:] }
        defer { freeifaddrs(pointer) }
        var result: [String: NetworkInterfaceCounter] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            let value = interface.pointee
            if value.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               value.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
               let data = value.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                let name = String(cString: value.ifa_name)
                result[name] = NetworkInterfaceCounter(received: data.ifi_ibytes, sent: data.ifi_obytes)
            }
            current = value.ifa_next
        }
        return result
    }
}
