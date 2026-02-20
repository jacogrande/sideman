import XCTest
@testable import SidemanApp

final class DefaultCreditsProviderTests: XCTestCase {
    func testLookupCreditsUsesCacheWhenAvailable() async {
        let cachedBundle = CreditsBundle(
            entriesByGroup: [.musicians: [
                CreditEntry(
                    personName: "Cached Musician",
                    personMBID: "cached-1",
                    roleRaw: "instrument (guitar)",
                    roleGroup: .musicians,
                    sourceLevel: .recording,
                    instrument: "guitar"
                )
            ]],
            provenance: [.recording],
            resolvedRecordingMBID: "rec-cached"
        )

        let cache = StubCreditsCache()
        let keyTrack = NowPlayingTrack(id: "spotify:track:1", title: "Song", artist: "Artist", album: "Album")
        let key = DefaultCreditsProvider.cacheKey(for: keyTrack)
        await cache.set(
            CachedCredits(key: key, state: .loaded, bundle: cachedBundle, expiresAt: Date().addingTimeInterval(300)),
            for: key
        )

        let provider = DefaultCreditsProvider(
            resolver: StubResolver(result: .failure(.notFound)),
            client: StubClient(),
            cache: cache
        )

        let (state, bundle) = await provider.lookupCredits(for: keyTrack)

        XCTAssertEqual(state, .loaded)
        XCTAssertEqual(bundle?.resolvedRecordingMBID, "rec-cached")
    }

    func testLookupCreditsReturnsLoadedAndMergesFallbackReleaseCredits() async {
        let resolver = StubResolver(result: .success(
            ResolutionResult(recordingMBID: "rec-1", releaseMBID: "rel-1", workMBIDs: ["work-1"], confidence: 0.95)
        ))

        let recording = MBRecordingDetail(
            id: "rec-1",
            title: "Track",
            relations: [
                MBRelationship(type: "instrument", targetType: "artist", attributes: ["guitar"], artist: MBArtist(id: "p1", name: "Player"), work: nil)
            ],
            releases: [MBReleaseSummary(id: "rel-1", title: "Album")]
        )

        let work = MBWorkDetail(
            id: "work-1",
            title: "Work",
            relations: [
                MBRelationship(type: "composer", targetType: "artist", attributes: [], artist: MBArtist(id: "p2", name: "Writer"), work: nil)
            ]
        )

        let release = MBReleaseDetail(
            id: "rel-1",
            title: "Album",
            relations: [
                MBRelationship(type: "producer", targetType: "artist", attributes: [], artist: MBArtist(id: "p3", name: "Producer"), work: nil)
            ]
        )

        let client = StubClient(
            recordingByID: ["rec-1": recording],
            workByID: ["work-1": work],
            releaseByID: ["rel-1": release]
        )

        let cache = StubCreditsCache()
        let provider = DefaultCreditsProvider(resolver: resolver, client: client, cache: cache)

        let track = NowPlayingTrack(id: "spotify:track:xyz", title: "Track", artist: "Artist", album: "Album")
        let (state, bundle) = await provider.lookupCredits(for: track)

        XCTAssertEqual(state, .loaded)
        XCTAssertNotNil(bundle)
        XCTAssertEqual(bundle?.entries(for: .musicians).count, 1)
        XCTAssertEqual(bundle?.entries(for: .writing).count, 1)
        XCTAssertEqual(bundle?.entries(for: .production).count, 1)
    }

    func testLookupCreditsCachesNotFoundFromResolver() async {
        let cache = StubCreditsCache()
        let provider = DefaultCreditsProvider(
            resolver: StubResolver(result: .failure(.notFound)),
            client: StubClient(),
            cache: cache
        )

        let track = NowPlayingTrack(id: "spotify:track:404", title: "Unknown", artist: "Unknown", album: "")
        let key = DefaultCreditsProvider.cacheKey(for: track)

        let (state, bundle) = await provider.lookupCredits(for: track)

        XCTAssertEqual(state, .notFound)
        XCTAssertNil(bundle)

        let cached = await cache.get(for: key)
        XCTAssertEqual(cached?.state, .notFound)
    }
}

private actor StubResolver: TrackResolver {
    let result: Result<ResolutionResult, ResolverError>

    init(result: Result<ResolutionResult, ResolverError>) {
        self.result = result
    }

    func resolve(_ track: NowPlayingTrack) async -> Result<ResolutionResult, ResolverError> {
        result
    }
}

private actor StubClient: MusicBrainzClient {
    let recordingByID: [String: MBRecordingDetail]
    let workByID: [String: MBWorkDetail]
    let releaseByID: [String: MBReleaseDetail]

    init(
        recordingByID: [String: MBRecordingDetail] = [:],
        workByID: [String: MBWorkDetail] = [:],
        releaseByID: [String: MBReleaseDetail] = [:]
    ) {
        self.recordingByID = recordingByID
        self.workByID = workByID
        self.releaseByID = releaseByID
    }

    func searchRecordings(query: RecordingQuery) async throws -> [RecordingCandidate] {
        []
    }

    func getRecording(id: String) async throws -> MBRecordingDetail {
        if let value = recordingByID[id] {
            return value
        }
        throw MusicBrainzClientError.notFound
    }

    func getWork(id: String) async throws -> MBWorkDetail {
        if let value = workByID[id] {
            return value
        }
        throw MusicBrainzClientError.notFound
    }

    func getRelease(id: String) async throws -> MBReleaseDetail {
        if let value = releaseByID[id] {
            return value
        }
        throw MusicBrainzClientError.notFound
    }

    func getArtistRecordingRels(id: String) async throws -> [ArtistRecordingRel] { [] }
    func getArtistWorkRels(id: String) async throws -> [ArtistWorkRel] { [] }
    func getWorkRecordings(id: String) async throws -> [WorkRecordingRel] { [] }
    func browseRecordings(artistID: String, offset: Int, limit: Int, includeISRCs: Bool) async throws -> MBBrowseRecordingsPage {
        MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: 0)
    }
    func getRecordingISRCs(id: String) async throws -> [String] { [] }
    func searchArtists(name: String) async throws -> [MBArtistSearchResult] { [] }
}

private actor StubCreditsCache: CreditsCache {
    var values: [String: CachedCredits] = [:]

    func get(for key: String) async -> CachedCredits? {
        values[key]
    }

    func set(_ value: CachedCredits, for key: String) async {
        values[key] = value
    }

    func remove(for key: String) async {
        values.removeValue(forKey: key)
    }
}
