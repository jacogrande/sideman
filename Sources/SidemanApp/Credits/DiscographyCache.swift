import Foundation

actor DiscographyCache {
    private var entries: [String: CachedDiscography] = [:]
    private var loadedFromDisk = false

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultCacheURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func get(for artistMBID: String) async -> DiscographyResult? {
        await loadFromDiskIfNeeded()
        purgeExpiredIfNeeded()
        if let cached = entries[artistMBID], !cached.isExpired {
            DebugLogger.log(.cache, "discography cache hit artist=\(artistMBID)")
            return cached.result
        }
        DebugLogger.log(.cache, "discography cache miss artist=\(artistMBID)")
        return nil
    }

    func set(_ result: DiscographyResult, for artistMBID: String, ttl: TimeInterval = 7 * 24 * 3600) async {
        await loadFromDiskIfNeeded()
        entries[artistMBID] = CachedDiscography(
            artistMBID: artistMBID,
            result: result,
            expiresAt: Date().addingTimeInterval(ttl)
        )
        DebugLogger.log(.cache, "discography cache set artist=\(artistMBID) recordings=\(result.recordings.count)")
        persist()
    }

    func remove(for artistMBID: String) async {
        await loadFromDiskIfNeeded()
        guard entries.removeValue(forKey: artistMBID) != nil else { return }
        DebugLogger.log(.cache, "discography cache remove artist=\(artistMBID)")
        persist()
    }

    private func loadFromDiskIfNeeded() async {
        guard !loadedFromDisk else { return }
        defer { loadedFromDisk = true }

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let payload = try decoder.decode(DiscographyCachePayload.self, from: data)
            entries = payload.entries
            DebugLogger.log(.cache, "discography cache disk load entries=\(entries.count)")
        } catch {
            entries = [:]
            DebugLogger.log(.cache, "discography cache disk load failed; starting empty")
        }
    }

    private func purgeExpiredIfNeeded() {
        let now = Date()
        let originalCount = entries.count
        entries = entries.filter { $0.value.expiresAt > now }
        if entries.count != originalCount {
            DebugLogger.log(.cache, "discography cache purged expired removed=\(originalCount - entries.count)")
            persist()
        }
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let payload = DiscographyCachePayload(entries: entries)
            let data = try encoder.encode(payload)
            try data.write(to: fileURL, options: .atomic)
            DebugLogger.log(.cache, "discography cache persisted entries=\(entries.count)")
        } catch {
            DebugLogger.log(.cache, "discography cache persist failed")
        }
    }

    private static func defaultCacheURL() -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return baseDirectory
            .appendingPathComponent("sideman", isDirectory: true)
            .appendingPathComponent("discography-cache.json")
    }
}

struct CachedDiscography: Equatable, Codable {
    let artistMBID: String
    let result: DiscographyResult
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

private struct DiscographyCachePayload: Codable {
    let entries: [String: CachedDiscography]
}
