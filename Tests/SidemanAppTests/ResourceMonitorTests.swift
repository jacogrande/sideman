import XCTest
@testable import SidemanApp

final class ResourceMonitorTests: XCTestCase {
    func testCaptureSnapshotReturnsNonZeroResidentMemory() {
        let snapshot = ResourceMonitor.captureSnapshot()

        XCTAssertGreaterThan(snapshot.residentBytes, 0, "Resident memory should be non-zero for a running process")
    }

    func testCaptureSnapshotReturnsNonZeroVirtualMemory() {
        let snapshot = ResourceMonitor.captureSnapshot()

        XCTAssertGreaterThan(snapshot.virtualBytes, 0, "Virtual memory should be non-zero for a running process")
    }

    func testCaptureSnapshotReturnsNonNegativeCPUTimes() {
        let snapshot = ResourceMonitor.captureSnapshot()

        XCTAssertGreaterThanOrEqual(snapshot.cpuUserTime, 0)
        XCTAssertGreaterThanOrEqual(snapshot.cpuSystemTime, 0)
    }

    func testCaptureSnapshotTimestampIsRecent() {
        let before = Date()
        let snapshot = ResourceMonitor.captureSnapshot()
        let after = Date()

        XCTAssertGreaterThanOrEqual(snapshot.capturedAt, before)
        XCTAssertLessThanOrEqual(snapshot.capturedAt, after)
    }

    func testResidentMBComputedProperty() {
        let snapshot = ResourceSnapshot(
            capturedAt: Date(),
            residentBytes: 10 * 1024 * 1024,
            virtualBytes: 0,
            cpuUserTime: 0,
            cpuSystemTime: 0,
            cacheFileSizeBytes: 0,
            cacheEntryCount: 0,
            cacheFileExists: false
        )

        XCTAssertEqual(snapshot.residentMB, 10.0, accuracy: 0.001)
    }

    func testVirtualMBComputedProperty() {
        let snapshot = ResourceSnapshot(
            capturedAt: Date(),
            residentBytes: 0,
            virtualBytes: 256 * 1024 * 1024,
            cpuUserTime: 0,
            cpuSystemTime: 0,
            cacheFileSizeBytes: 0,
            cacheEntryCount: 0,
            cacheFileExists: false
        )

        XCTAssertEqual(snapshot.virtualMB, 256.0, accuracy: 0.001)
    }

    func testCacheFileSizeKBComputedProperty() {
        let snapshot = ResourceSnapshot(
            capturedAt: Date(),
            residentBytes: 0,
            virtualBytes: 0,
            cpuUserTime: 0,
            cpuSystemTime: 0,
            cacheFileSizeBytes: 2048,
            cacheEntryCount: 0,
            cacheFileExists: true
        )

        XCTAssertEqual(snapshot.cacheFileSizeKB, 2.0, accuracy: 0.001)
    }

    func testTotalCPUTimeComputedProperty() {
        let snapshot = ResourceSnapshot(
            capturedAt: Date(),
            residentBytes: 0,
            virtualBytes: 0,
            cpuUserTime: 1.5,
            cpuSystemTime: 0.3,
            cacheFileSizeBytes: 0,
            cacheEntryCount: 0,
            cacheFileExists: false
        )

        XCTAssertEqual(snapshot.totalCPUTime, 1.8, accuracy: 0.001)
    }

    func testEquatable() {
        let date = Date()
        let a = ResourceSnapshot(
            capturedAt: date,
            residentBytes: 100,
            virtualBytes: 200,
            cpuUserTime: 1.0,
            cpuSystemTime: 0.5,
            cacheFileSizeBytes: 300,
            cacheEntryCount: 5,
            cacheFileExists: true
        )
        let b = ResourceSnapshot(
            capturedAt: date,
            residentBytes: 100,
            virtualBytes: 200,
            cpuUserTime: 1.0,
            cpuSystemTime: 0.5,
            cacheFileSizeBytes: 300,
            cacheEntryCount: 5,
            cacheFileExists: true
        )

        XCTAssertEqual(a, b)
    }
}
