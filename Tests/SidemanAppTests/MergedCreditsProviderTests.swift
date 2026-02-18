import XCTest
@testable import SidemanApp

final class MergedCreditsProviderTests: XCTestCase {
    private let sampleTrack = NowPlayingTrack(
        id: "spotify:track:test1",
        title: "Song",
        artist: "Artist",
        album: "Album"
    )

    func testBothSourcesLoadedReturnsMergedBundle() async {
        let wikiBundle = CreditsBundle(
            entriesByGroup: [.musicians: [
                CreditEntry(
                    personName: "Alice",
                    roleRaw: "vocals",
                    roleGroup: .musicians,
                    sourceLevel: .release,
                    source: .wikipedia,
                    scope: .albumWide
                )
            ]],
            provenance: [.release],
            resolvedRecordingMBID: "wikipedia:100",
            sourceID: "wikipedia:100",
            sourceName: "Wikipedia",
            sourcePageTitle: "Album Page",
            sourcePageURL: "https://en.wikipedia.org/wiki/Album_Page",
            sourceAttribution: "Wikipedia",
            matchedTrackNumber: 3
        )

        let mbBundle = CreditsBundle(
            entriesByGroup: [.writing: [
                CreditEntry(
                    personName: "Bob",
                    personMBID: "mb-bob",
                    roleRaw: "composer",
                    roleGroup: .writing,
                    sourceLevel: .work,
                    source: .musicBrainz
                )
            ]],
            provenance: [.recording, .work],
            resolvedRecordingMBID: "rec-123",
            sourceName: "MusicBrainz",
            sourceAttribution: "MusicBrainz"
        )

        let provider = MergedCreditsProvider(
            wikipedia: StubMergedProvider(state: .loaded, bundle: wikiBundle),
            musicBrainz: StubMergedProvider(state: .loaded, bundle: mbBundle)
        )

        let (state, bundle) = await provider.lookupCredits(for: sampleTrack)

        XCTAssertEqual(state, .loaded)
        XCTAssertNotNil(bundle)
        XCTAssertEqual(bundle?.entries(for: .musicians).count, 1)
        XCTAssertEqual(bundle?.entries(for: .writing).count, 1)
        XCTAssertEqual(bundle?.sourceName, "Wikipedia + MusicBrainz")
        XCTAssertEqual(bundle?.sourcePageTitle, "Album Page")
        XCTAssertEqual(bundle?.sourcePageURL, "https://en.wikipedia.org/wiki/Album_Page")
        XCTAssertEqual(bundle?.resolvedRecordingMBID, "rec-123")
        XCTAssertEqual(bundle?.matchedTrackNumber, 3)
        XCTAssertEqual(bundle?.sourceAttribution, "Wikipedia + MusicBrainz")
        XCTAssertTrue(bundle!.provenance.contains(.release))
        XCTAssertTrue(bundle!.provenance.contains(.recording))
        XCTAssertTrue(bundle!.provenance.contains(.work))
    }

    func testOnlyWikipediaLoadedReturnsWikipediaBundle() async {
        let wikiBundle = CreditsBundle(
            entriesByGroup: [.production: [
                CreditEntry(
                    personName: "Charlie",
                    roleRaw: "producer",
                    roleGroup: .production,
                    source: .wikipedia
                )
            ]],
            provenance: [.release],
            resolvedRecordingMBID: "wikipedia:200",
            sourceName: "Wikipedia"
        )

        let provider = MergedCreditsProvider(
            wikipedia: StubMergedProvider(state: .loaded, bundle: wikiBundle),
            musicBrainz: StubMergedProvider(state: .notFound, bundle: nil)
        )

        let (state, bundle) = await provider.lookupCredits(for: sampleTrack)

        XCTAssertEqual(state, .loaded)
        XCTAssertEqual(bundle?.sourceName, "Wikipedia")
        XCTAssertEqual(bundle?.entries(for: .production).count, 1)
    }

    func testOnlyMusicBrainzLoadedReturnsMusicBrainzBundle() async {
        let mbBundle = CreditsBundle(
            entriesByGroup: [.writing: [
                CreditEntry(
                    personName: "Dave",
                    personMBID: "mb-dave",
                    roleRaw: "lyricist",
                    roleGroup: .writing,
                    source: .musicBrainz
                )
            ]],
            provenance: [.work],
            resolvedRecordingMBID: "rec-456",
            sourceName: "MusicBrainz"
        )

        let provider = MergedCreditsProvider(
            wikipedia: StubMergedProvider(state: .notFound, bundle: nil),
            musicBrainz: StubMergedProvider(state: .loaded, bundle: mbBundle)
        )

        let (state, bundle) = await provider.lookupCredits(for: sampleTrack)

        XCTAssertEqual(state, .loaded)
        XCTAssertEqual(bundle?.sourceName, "MusicBrainz")
        XCTAssertEqual(bundle?.entries(for: .writing).count, 1)
    }

    func testNeitherLoadedReturnsNotFound() async {
        let provider = MergedCreditsProvider(
            wikipedia: StubMergedProvider(state: .notFound, bundle: nil),
            musicBrainz: StubMergedProvider(state: .notFound, bundle: nil)
        )

        let (state, bundle) = await provider.lookupCredits(for: sampleTrack)

        XCTAssertEqual(state, .notFound)
        XCTAssertNil(bundle)
    }

    func testCrossSourceDeduplicationPrefersMBID() async {
        let wikiBundle = CreditsBundle(
            entriesByGroup: [.musicians: [
                CreditEntry(
                    personName: "Eve",
                    roleRaw: "vocals",
                    roleGroup: .musicians,
                    sourceLevel: .release,
                    source: .wikipedia,
                    scope: .albumWide
                )
            ]],
            provenance: [.release],
            resolvedRecordingMBID: "wikipedia:300",
            sourceID: "wikipedia:300",
            sourceName: "Wikipedia",
            sourcePageTitle: "Page",
            sourcePageURL: "https://en.wikipedia.org/wiki/Page",
            sourceAttribution: "Wikipedia"
        )

        let mbBundle = CreditsBundle(
            entriesByGroup: [.musicians: [
                CreditEntry(
                    personName: "Eve",
                    personMBID: "mb-eve",
                    roleRaw: "vocals",
                    roleGroup: .musicians,
                    sourceLevel: .recording,
                    source: .musicBrainz,
                    scope: .albumWide
                )
            ]],
            provenance: [.recording],
            resolvedRecordingMBID: "rec-789",
            sourceName: "MusicBrainz",
            sourceAttribution: "MusicBrainz"
        )

        let provider = MergedCreditsProvider(
            wikipedia: StubMergedProvider(state: .loaded, bundle: wikiBundle),
            musicBrainz: StubMergedProvider(state: .loaded, bundle: mbBundle)
        )

        let (state, bundle) = await provider.lookupCredits(for: sampleTrack)

        XCTAssertEqual(state, .loaded)
        let musicians = bundle?.entries(for: .musicians) ?? []
        XCTAssertEqual(musicians.count, 1, "Duplicate entry should be deduplicated")
        XCTAssertEqual(musicians.first?.personMBID, "mb-eve", "Should prefer entry with MBID")
    }

    func testUniqueEntriesFromBothSourcesPreserved() async {
        let wikiBundle = CreditsBundle(
            entriesByGroup: [
                .musicians: [
                    CreditEntry(
                        personName: "Frank",
                        roleRaw: "guitar",
                        roleGroup: .musicians,
                        source: .wikipedia
                    )
                ]
            ],
            provenance: [.release],
            resolvedRecordingMBID: "wikipedia:400",
            sourceID: "wikipedia:400",
            sourceName: "Wikipedia",
            sourcePageTitle: "Page",
            sourcePageURL: "https://en.wikipedia.org/wiki/Page",
            sourceAttribution: "Wikipedia"
        )

        let mbBundle = CreditsBundle(
            entriesByGroup: [
                .writing: [
                    CreditEntry(
                        personName: "Grace",
                        personMBID: "mb-grace",
                        roleRaw: "composer",
                        roleGroup: .writing,
                        source: .musicBrainz
                    )
                ]
            ],
            provenance: [.work],
            resolvedRecordingMBID: "rec-abc",
            sourceName: "MusicBrainz",
            sourceAttribution: "MusicBrainz"
        )

        let provider = MergedCreditsProvider(
            wikipedia: StubMergedProvider(state: .loaded, bundle: wikiBundle),
            musicBrainz: StubMergedProvider(state: .loaded, bundle: mbBundle)
        )

        let (_, bundle) = await provider.lookupCredits(for: sampleTrack)

        XCTAssertEqual(bundle?.entries(for: .musicians).count, 1)
        XCTAssertEqual(bundle?.entries(for: .musicians).first?.personName, "Frank")
        XCTAssertEqual(bundle?.entries(for: .writing).count, 1)
        XCTAssertEqual(bundle?.entries(for: .writing).first?.personName, "Grace")
    }

    func testInvalidateCachedCreditsClearsBothProviders() async {
        let wikiProvider = StubMergedProvider(state: .notFound, bundle: nil)
        let mbProvider = StubMergedProvider(state: .notFound, bundle: nil)

        let provider = MergedCreditsProvider(
            wikipedia: wikiProvider,
            musicBrainz: mbProvider
        )

        await provider.invalidateCachedCredits(for: sampleTrack)

        let wikiInvalidated = await wikiProvider.invalidatedTracks
        let mbInvalidated = await mbProvider.invalidatedTracks

        XCTAssertEqual(wikiInvalidated.count, 1)
        XCTAssertEqual(mbInvalidated.count, 1)
        XCTAssertEqual(wikiInvalidated.first?.id, sampleTrack.id)
        XCTAssertEqual(mbInvalidated.first?.id, sampleTrack.id)
    }

    func testCacheLookupKeyDelegatesToWikipedia() async {
        let wikiProvider = StubMergedProvider(state: .notFound, bundle: nil, cacheKey: "wiki-key")
        let mbProvider = StubMergedProvider(state: .notFound, bundle: nil, cacheKey: "mb-key")

        let provider = MergedCreditsProvider(
            wikipedia: wikiProvider,
            musicBrainz: mbProvider
        )

        let key = await provider.cacheLookupKey(for: sampleTrack)
        XCTAssertEqual(key, "wiki-key")
    }

    func testErrorStateTreatedAsNotLoaded() async {
        let mbBundle = CreditsBundle(
            entriesByGroup: [.writing: [
                CreditEntry(
                    personName: "Hank",
                    personMBID: "mb-hank",
                    roleRaw: "composer",
                    roleGroup: .writing,
                    source: .musicBrainz
                )
            ]],
            provenance: [.work],
            resolvedRecordingMBID: "rec-err",
            sourceName: "MusicBrainz"
        )

        let provider = MergedCreditsProvider(
            wikipedia: StubMergedProvider(state: .error("timeout"), bundle: nil),
            musicBrainz: StubMergedProvider(state: .loaded, bundle: mbBundle)
        )

        let (state, bundle) = await provider.lookupCredits(for: sampleTrack)

        XCTAssertEqual(state, .loaded)
        XCTAssertEqual(bundle?.sourceName, "MusicBrainz")
    }
}

// MARK: - Stubs

private actor StubMergedProvider: CreditsProvider {
    let state: CreditsLookupState
    let bundle: CreditsBundle?
    let cacheKey: String
    var invalidatedTracks: [NowPlayingTrack] = []

    init(state: CreditsLookupState, bundle: CreditsBundle?, cacheKey: String = "stub-key") {
        self.state = state
        self.bundle = bundle
        self.cacheKey = cacheKey
    }

    func lookupCredits(for track: NowPlayingTrack) async -> (CreditsLookupState, CreditsBundle?) {
        (state, bundle)
    }

    func cacheLookupKey(for track: NowPlayingTrack) async -> String {
        cacheKey
    }

    func invalidateCachedCredits(for track: NowPlayingTrack) async {
        invalidatedTracks.append(track)
    }
}
