import Foundation

struct ResourceSnapshot: Equatable {
    let capturedAt: Date
    let residentBytes: UInt64
    let virtualBytes: UInt64
    let cpuUserTime: TimeInterval
    let cpuSystemTime: TimeInterval
    let cacheFileSizeBytes: Int64
    let cacheEntryCount: Int
    let cacheFileExists: Bool

    var residentMB: Double {
        Double(residentBytes) / (1024 * 1024)
    }

    var virtualMB: Double {
        Double(virtualBytes) / (1024 * 1024)
    }

    var cacheFileSizeKB: Double {
        Double(cacheFileSizeBytes) / 1024
    }

    var totalCPUTime: TimeInterval {
        cpuUserTime + cpuSystemTime
    }
}
