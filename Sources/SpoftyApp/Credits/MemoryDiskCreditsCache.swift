import Foundation

actor MemoryDiskCreditsCache: CreditsCache {
    private var entries: [String: CachedCredits] = [:]
    private var loadedFromDisk = false

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultCacheURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func get(for key: String) async -> CachedCredits? {
        await loadFromDiskIfNeeded()
        purgeExpiredIfNeeded()
        if let value = entries[key] {
            DebugLogger.log(.cache, "cache get hit key=\(key) state=\(value.state)")
            return value
        }

        DebugLogger.log(.cache, "cache get miss key=\(key)")
        return nil
    }

    func set(_ value: CachedCredits, for key: String) async {
        await loadFromDiskIfNeeded()
        entries[key] = value
        DebugLogger.log(.cache, "cache set key=\(key) state=\(value.state)")
        persist()
    }

    func remove(for key: String) async {
        await loadFromDiskIfNeeded()
        guard entries.removeValue(forKey: key) != nil else {
            return
        }

        DebugLogger.log(.cache, "cache remove key=\(key)")
        persist()
    }

    private func loadFromDiskIfNeeded() async {
        guard !loadedFromDisk else {
            return
        }

        defer { loadedFromDisk = true }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let payload = try decoder.decode(CachePayload.self, from: data)
            entries = payload.entries
            DebugLogger.log(.cache, "cache disk load entries=\(entries.count)")
        } catch {
            entries = [:]
            DebugLogger.log(.cache, "cache disk load failed; starting empty")
        }
    }

    private func purgeExpiredIfNeeded() {
        let now = Date()
        let originalCount = entries.count
        entries = entries.filter { $0.value.expiresAt > now }

        if entries.count != originalCount {
            DebugLogger.log(.cache, "cache purged expired entries removed=\(originalCount - entries.count)")
            persist()
        }
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let payload = CachePayload(entries: entries)
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: .atomic)
            DebugLogger.log(.cache, "cache persisted entries=\(entries.count)")
        } catch {
            // Ignore cache persistence failures.
            DebugLogger.log(.cache, "cache persist failed")
        }
    }

    private static func defaultCacheURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return baseDirectory
            .appendingPathComponent("spofty", isDirectory: true)
            .appendingPathComponent("credits-cache.json")
    }
}

private struct CachePayload: Codable {
    let entries: [String: CachedCredits]
}
