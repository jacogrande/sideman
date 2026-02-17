import XCTest
@testable import SpoftyApp

final class MemoryDiskCreditsCacheTests: XCTestCase {
    func testSetAndGetRoundTrip() async {
        let fileURL = temporaryCacheURL()
        let cache = MemoryDiskCreditsCache(fileURL: fileURL)

        let credits = CachedCredits(
            key: "k1",
            state: .loaded,
            bundle: sampleBundle(),
            expiresAt: Date().addingTimeInterval(300)
        )

        await cache.set(credits, for: "k1")
        let loaded = await cache.get(for: "k1")

        XCTAssertEqual(loaded?.state, .loaded)
        XCTAssertEqual(loaded?.bundle?.resolvedRecordingMBID, "rec-1")
    }

    func testExpiredEntriesArePurged() async {
        let fileURL = temporaryCacheURL()
        let cache = MemoryDiskCreditsCache(fileURL: fileURL)

        let credits = CachedCredits(
            key: "k2",
            state: .notFound,
            bundle: nil,
            expiresAt: Date().addingTimeInterval(-1)
        )

        await cache.set(credits, for: "k2")

        let loaded = await cache.get(for: "k2")
        XCTAssertNil(loaded)
    }

    func testPersistsAcrossInstances() async {
        let fileURL = temporaryCacheURL()

        let first = MemoryDiskCreditsCache(fileURL: fileURL)
        await first.set(
            CachedCredits(
                key: "k3",
                state: .ambiguous,
                bundle: nil,
                expiresAt: Date().addingTimeInterval(100)
            ),
            for: "k3"
        )

        let second = MemoryDiskCreditsCache(fileURL: fileURL)
        let loaded = await second.get(for: "k3")

        XCTAssertEqual(loaded?.state, .ambiguous)
    }

    private func sampleBundle() -> CreditsBundle {
        CreditsBundle(
            entriesByGroup: [.musicians: [
                CreditEntry(
                    personName: "Name",
                    personMBID: "mbid",
                    roleRaw: "instrument (guitar)",
                    roleGroup: .musicians,
                    sourceLevel: .recording,
                    instrument: "guitar"
                )
            ]],
            provenance: [.recording],
            resolvedRecordingMBID: "rec-1"
        )
    }

    private func temporaryCacheURL() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return directory.appendingPathComponent("cache.json")
    }
}
