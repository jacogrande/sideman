import XCTest
@testable import SidemanApp

final class WikipediaCreditsProviderTests: XCTestCase {
    func testCacheKeyUsesWikipediaNamespace() {
        let withSpotifyID = NowPlayingTrack(
            id: "spotify:track:ABC123",
            title: "Song",
            artist: "Artist",
            album: "Album"
        )
        let withoutSpotifyID = NowPlayingTrack(
            id: "",
            title: "Song",
            artist: "Artist",
            album: "Album"
        )

        XCTAssertEqual(
            WikipediaCreditsProvider.cacheKey(for: withSpotifyID),
            "wikipedia:spotify:spotify:track:abc123"
        )
        XCTAssertEqual(
            WikipediaCreditsProvider.cacheKey(for: withoutSpotifyID),
            "wikipedia:meta:song|artist|album"
        )
    }

    func testLookupCreditsUsesCachedEntryWhenPresent() async {
        let cache = StubWikipediaCreditsCache()
        let track = NowPlayingTrack(id: "spotify:track:1", title: "Song", artist: "Artist", album: "Album")
        let key = WikipediaCreditsProvider.cacheKey(for: track)

        let cachedBundle = CreditsBundle(
            entriesByGroup: [.production: [
                CreditEntry(
                    personName: "Cached Producer",
                    roleRaw: "producer",
                    roleGroup: .production,
                    source: .wikipedia
                )
            ]],
            provenance: [.recording],
            resolvedRecordingMBID: "wikipedia:100"
        )
        await cache.set(
            CachedCredits(
                key: key,
                state: .loaded,
                bundle: cachedBundle,
                expiresAt: Date().addingTimeInterval(60)
            ),
            for: key
        )

        let provider = WikipediaCreditsProvider(
            resolver: StubWikipediaResolver(result: .failure(.notFound)),
            client: StubWikipediaAPIClient(),
            parser: StubWikipediaParser(parsed: WikipediaParsedCredits(entries: [], matchedTrackNumber: nil)),
            cache: cache
        )

        let (state, bundle) = await provider.lookupCredits(for: track)

        XCTAssertEqual(state, .loaded)
        XCTAssertEqual(bundle?.resolvedRecordingMBID, "wikipedia:100")
    }

    func testLookupCreditsCachesNotFoundWhenResolverFails() async {
        let cache = StubWikipediaCreditsCache()
        let provider = WikipediaCreditsProvider(
            resolver: StubWikipediaResolver(result: .failure(.notFound)),
            client: StubWikipediaAPIClient(),
            parser: StubWikipediaParser(parsed: WikipediaParsedCredits(entries: [], matchedTrackNumber: nil)),
            cache: cache
        )

        let track = NowPlayingTrack(id: "spotify:track:404", title: "Unknown", artist: "Unknown", album: "")
        let key = WikipediaCreditsProvider.cacheKey(for: track)

        let (state, bundle) = await provider.lookupCredits(for: track)

        XCTAssertEqual(state, .notFound)
        XCTAssertNil(bundle)

        let cached = await cache.get(for: key)
        XCTAssertEqual(cached?.state, .notFound)
    }

    func testLookupCreditsBuildsBundleFromParsedEntries() async {
        let page = WikipediaPageContent(
            pageID: 200,
            title: "Album Page",
            fullURL: "https://en.wikipedia.org/wiki/Album_Page",
            wikitext: "== Personnel =="
        )
        let parsed = WikipediaParsedCredits(
            entries: [
                CreditEntry(
                    personName: "Isaac Wood",
                    roleRaw: "vocals",
                    roleGroup: .musicians,
                    sourceLevel: .release,
                    source: .wikipedia,
                    scope: .albumWide
                ),
                CreditEntry(
                    personName: "Sergio Maschetzko",
                    roleRaw: "mixing",
                    roleGroup: .engineering,
                    sourceLevel: .recording,
                    source: .wikipedia,
                    scope: .trackSpecific([2])
                )
            ],
            matchedTrackNumber: 2
        )

        let provider = WikipediaCreditsProvider(
            resolver: StubWikipediaResolver(result: .success(
                WikipediaPageResolution(pageID: 200, title: "Album Page", confidence: 0.92)
            )),
            client: StubWikipediaAPIClient(pageByID: [200: page]),
            parser: StubWikipediaParser(parsed: parsed),
            cache: StubWikipediaCreditsCache()
        )

        let track = NowPlayingTrack(id: "spotify:track:2", title: "Concorde", artist: "Artist", album: "Album")
        let (state, bundle) = await provider.lookupCredits(for: track)

        XCTAssertEqual(state, .loaded)
        XCTAssertEqual(bundle?.sourceName, "Wikipedia")
        XCTAssertEqual(bundle?.sourcePageTitle, "Album Page")
        XCTAssertEqual(bundle?.sourcePageURL, "https://en.wikipedia.org/wiki/Album_Page")
        XCTAssertEqual(bundle?.matchedTrackNumber, 2)
        XCTAssertEqual(bundle?.resolvedSourceID, "wikipedia:200")
        XCTAssertEqual(bundle?.provenance, [.recording, .release])
        XCTAssertEqual(bundle?.entries(for: .musicians).count, 1)
        XCTAssertEqual(bundle?.entries(for: .engineering).count, 1)
    }

    func testInvalidateCachedCreditsRemovesStoredEntry() async {
        let cache = StubWikipediaCreditsCache()
        let provider = WikipediaCreditsProvider(
            resolver: StubWikipediaResolver(result: .failure(.notFound)),
            client: StubWikipediaAPIClient(),
            parser: StubWikipediaParser(parsed: WikipediaParsedCredits(entries: [], matchedTrackNumber: nil)),
            cache: cache
        )

        let track = NowPlayingTrack(id: "spotify:track:clear", title: "Song", artist: "Artist", album: "Album")
        let key = WikipediaCreditsProvider.cacheKey(for: track)

        await cache.set(
            CachedCredits(
                key: key,
                state: .notFound,
                bundle: nil,
                expiresAt: Date().addingTimeInterval(60)
            ),
            for: key
        )

        await provider.invalidateCachedCredits(for: track)

        let cached = await cache.get(for: key)
        XCTAssertNil(cached)
    }
}

private actor StubWikipediaResolver: WikipediaPageResolver {
    let result: Result<WikipediaPageResolution, ResolverError>

    init(result: Result<WikipediaPageResolution, ResolverError>) {
        self.result = result
    }

    func resolvePage(for track: NowPlayingTrack) async -> Result<WikipediaPageResolution, ResolverError> {
        result
    }
}

private actor StubWikipediaAPIClient: WikipediaAPIClient {
    let pageByID: [Int: WikipediaPageContent]

    init(pageByID: [Int: WikipediaPageContent] = [:]) {
        self.pageByID = pageByID
    }

    func searchPages(query: String, limit: Int) async throws -> [WikipediaSearchResult] {
        []
    }

    func fetchPage(pageID: Int) async throws -> WikipediaPageContent {
        if let page = pageByID[pageID] {
            return page
        }
        throw WikipediaClientError.notFound
    }
}

private struct StubWikipediaParser: WikipediaWikitextParser {
    let parsed: WikipediaParsedCredits

    func parse(page: WikipediaPageContent, for track: NowPlayingTrack) -> WikipediaParsedCredits {
        parsed
    }
}

private actor StubWikipediaCreditsCache: CreditsCache {
    private var values: [String: CachedCredits] = [:]

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
