import XCTest
@testable import CC_FLOW

final class SystemMonitorServiceTests: XCTestCase {
    func testDiskPercentClampsAndHandlesEmptyCapacity() {
        XCTAssertEqual(SystemMonitorSnapshot(diskUsed: 50, diskTotal: 100).diskPercent, 50)
        XCTAssertEqual(SystemMonitorSnapshot(diskUsed: 200, diskTotal: 100).diskPercent, 100)
        XCTAssertEqual(SystemMonitorSnapshot(diskUsed: 20, diskTotal: 0).diskPercent, 0)
    }

    func testHealthLevelPrioritizesCriticalDiskAndMemoryPressure() {
        XCTAssertEqual(SystemMonitorSnapshot(diskUsed: 96, diskTotal: 100).healthLevel, .critical)
        XCTAssertEqual(SystemMonitorSnapshot(memoryPercent: 90).healthLevel, .attention)
        XCTAssertEqual(SystemMonitorSnapshot(cpuPercent: 20, memoryPercent: 40).healthLevel, .normal)
    }

    func testDiskAvailableNeverBecomesNegative() {
        XCTAssertEqual(SystemMonitorSnapshot(diskUsed: 120, diskTotal: 100).diskAvailable, 0)
        XCTAssertEqual(SystemMonitorSnapshot(diskUsed: 35, diskTotal: 100).diskAvailable, 65)
    }

    func testNativeOptionalMetricsCanBeSampledSafely() {
        let swap = SystemMonitorService.swapUsage()
        XCTAssertLessThanOrEqual(swap.used, swap.total)
        XCTAssertFalse(SystemMonitorService.chipName().isEmpty)
        XCTAssertGreaterThanOrEqual(SystemMonitorService.batteryStatus().percent, 0)
    }

    func testHomeVolumeCapacityIsInternallyConsistent() {
        let capacity = SystemMonitorService.diskCapacity()

        XCTAssertGreaterThan(capacity.total, 0)
        XCTAssertGreaterThanOrEqual(capacity.used, 0)
        XCTAssertLessThanOrEqual(capacity.used, capacity.total)
    }

    func testNetworkTotalsCanBeSampledWithoutNegativeCounters() {
        let totals = SystemMonitorService.networkTotals()
        XCTAssertGreaterThanOrEqual(totals.received, 0)
        XCTAssertGreaterThanOrEqual(totals.sent, 0)
    }

    func testNetworkCounterDeltaHandlesFourGiBWrap() {
        XCTAssertEqual(SystemMonitorService.wrappedDelta(25, UInt32.max - 10), 36)
        XCTAssertEqual(SystemMonitorService.wrappedDelta(120, 100), 20)
    }

    func testDiskIOTotalsAndResetSafeDelta() {
        let totals = SystemMonitorService.diskIOTotals()
        XCTAssertGreaterThanOrEqual(totals.read, 0)
        XCTAssertGreaterThanOrEqual(totals.written, 0)
        XCTAssertEqual(SystemMonitorService.counterDelta(150, 100), 50)
        XCTAssertEqual(SystemMonitorService.counterDelta(10, 100), 0)
    }

    func testPerCoreCPUPercentagesUseTickDeltas() {
        let previous = [CPUCoreTicks(user: 10, system: 10, idle: 80, nice: 0)]
        let current = [CPUCoreTicks(user: 20, system: 20, idle: 160, nice: 0)]
        XCTAssertEqual(
            SystemMonitorService.cpuCorePercentages(previous: previous, current: current),
            [20]
        )
        XCTAssertEqual(
            SystemMonitorService.cpuCorePercentages(previous: [], current: current),
            []
        )
    }

    func testNativeCPUAndGPUSamplingIsSafe() {
        XCTAssertFalse(SystemMonitorService.cpuCoreTicks().isEmpty)
        if let gpu = SystemMonitorService.gpuUsagePercent() {
            XCTAssertTrue((0...100).contains(gpu))
        }
    }
}
