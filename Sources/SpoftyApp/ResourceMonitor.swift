import Foundation
import Darwin

enum ResourceMonitor {
    static func captureSnapshot() -> ResourceSnapshot {
        let (residentBytes, virtualBytes) = memoryUsage()
        let (userTime, systemTime) = cpuTimes()
        let (cacheSize, cacheEntries, cacheExists) = cacheDiskInfo()

        return ResourceSnapshot(
            capturedAt: Date(),
            residentBytes: residentBytes,
            virtualBytes: virtualBytes,
            cpuUserTime: userTime,
            cpuSystemTime: systemTime,
            cacheFileSizeBytes: cacheSize,
            cacheEntryCount: cacheEntries,
            cacheFileExists: cacheExists
        )
    }

    private static func memoryUsage() -> (resident: UInt64, virtual: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), ptr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, 0)
        }

        return (UInt64(info.phys_footprint), UInt64(info.virtual_size))
    }

    private static func cpuTimes() -> (user: TimeInterval, system: TimeInterval) {
        var info = task_thread_times_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), ptr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0, 0)
        }

        let userSeconds = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let systemSeconds = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000

        return (userSeconds, systemSeconds)
    }

    private static func cacheDiskInfo() -> (size: Int64, entryCount: Int, exists: Bool) {
        let cacheURL = cacheFileURL()
        let fm = FileManager.default

        guard fm.fileExists(atPath: cacheURL.path) else {
            return (0, 0, false)
        }

        var fileSize: Int64 = 0
        if let attrs = try? fm.attributesOfItem(atPath: cacheURL.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        }

        let entryCount = autoreleasepool {
            guard let data = try? Data(contentsOf: cacheURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["entries"] as? [String: Any] else {
                return 0
            }
            return entries.count
        }

        return (fileSize, entryCount, true)
    }

    private static func cacheFileURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return baseDirectory
            .appendingPathComponent("spofty", isDirectory: true)
            .appendingPathComponent("credits-cache.json")
    }
}
