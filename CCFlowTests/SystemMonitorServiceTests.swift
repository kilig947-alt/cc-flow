import XCTest
@testable import CC_FLOW

final class SystemMonitorServiceTests: XCTestCase {
    func testDiskPercentClampsAndHandlesEmptyCapacity() {
        XCTAssertEqual(SystemMonitorSnapshot(diskUsed: 50, diskTotal: 100).diskPercent, 50)
        XCTAssertEqual(SystemMonitorSnapshot(diskUsed: 200, diskTotal: 100).diskPercent, 100)
        XCTAssertEqual(SystemMonitorSnapshot(diskUsed: 20, diskTotal: 0).diskPercent, 0)
    }

    func testHomeVolumeCapacityIsInternallyConsistent() {
        let capacity = SystemMonitorService.diskCapacity()

        XCTAssertGreaterThan(capacity.total, 0)
        XCTAssertGreaterThanOrEqual(capacity.used, 0)
        XCTAssertLessThanOrEqual(capacity.used, capacity.total)
    }
}
