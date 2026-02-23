import XCTest
@testable import SidemanApp

final class TrackMatchingServiceTests: XCTestCase {
    func testResolveToSpotifyDetailedTriesMultipleArtistCredits() async throws {
        let recording = ArtistRecordingRel(
            recordingMBID: "rec-1",
            recordingTitle: "Beautiful",
            relationshipType: "main",
            attributes: [],
            artistCredits: ["Wrong Alias", "Pharrell Williams"],
            isrcs: []
        )

        let spotifyClient = StubSpotifyWebAPI(
            searchTracksResponses: [
                "Beautiful||Wrong Alias": [],
                "Beautiful||Pharrell Williams": [
                    spotifyTrack(
                        id: "good-1",
                        name: "Beautiful",
                        uri: "spotify:track:good-1",
                        artists: ["Snoop Dogg", "Pharrell Williams"],
                        popularity: 79
                    )
                ]
            ]
        )
        let mbClient = StubMusicBrainzClient()
        let service = TrackMatchingService(musicBrainzClient: mbClient, spotifyClient: spotifyClient, maxConcurrency: 1)

        let summary = try await service.resolveToSpotifyDetailed(recordings: [recording]) { _, _ in }

        XCTAssertEqual(summary.resolved.count, 1)
        XCTAssertEqual(summary.resolved.first?.spotifyURI, "spotify:track:good-1")
        XCTAssertTrue(summary.unresolved.isEmpty)

        let queries = await spotifyClient.recordedTextQueries()
        XCTAssertTrue(queries.contains("Beautiful||Wrong Alias"))
        XCTAssertTrue(queries.contains("Beautiful||Pharrell Williams"))
    }

    func testResolveToSpotifyDetailedUsesScoreInsteadOfFirstResult() async throws {
        let recording = ArtistRecordingRel(
            recordingMBID: "rec-2",
            recordingTitle: "Beautiful",
            relationshipType: "main",
            attributes: [],
            artistCredits: ["Snoop Dogg", "Pharrell Williams"],
            isrcs: []
        )

        let spotifyClient = StubSpotifyWebAPI(
            searchTracksResponses: [
                "Beautiful||Snoop Dogg": [
                    spotifyTrack(
                        id: "wrong-first",
                        name: "Beautiful People",
                        uri: "spotify:track:wrong-first",
                        artists: ["Ed Sheeran"],
                        popularity: 95
                    ),
                    spotifyTrack(
                        id: "correct-second",
                        name: "Beautiful",
                        uri: "spotify:track:correct-second",
                        artists: ["Snoop Dogg", "Pharrell Williams"],
                        popularity: 80
                    )
                ]
            ]
        )
        let mbClient = StubMusicBrainzClient()
        let service = TrackMatchingService(musicBrainzClient: mbClient, spotifyClient: spotifyClient, maxConcurrency: 1)

        let summary = try await service.resolveToSpotifyDetailed(recordings: [recording]) { _, _ in }

        XCTAssertEqual(summary.resolved.count, 1)
        XCTAssertEqual(summary.resolved.first?.spotifyURI, "spotify:track:correct-second")
    }

    func testResolveToSpotifyDetailedUsesRelaxedTitleFallback() async throws {
        let recording = ArtistRecordingRel(
            recordingMBID: "rec-3",
            recordingTitle: "Beautiful (Album Version)",
            relationshipType: "main",
            attributes: [],
            artistCredits: ["Snoop Dogg"],
            isrcs: []
        )

        let spotifyClient = StubSpotifyWebAPI(
            searchTracksResponses: [
                "Beautiful (Album Version)||Snoop Dogg": [],
                "Beautiful||Snoop Dogg": [
                    spotifyTrack(
                        id: "relaxed-hit",
                        name: "Beautiful",
                        uri: "spotify:track:relaxed-hit",
                        artists: ["Snoop Dogg", "Pharrell Williams"],
                        popularity: 82
                    )
                ]
            ]
        )
        let mbClient = StubMusicBrainzClient()
        let service = TrackMatchingService(musicBrainzClient: mbClient, spotifyClient: spotifyClient, maxConcurrency: 1)

        let summary = try await service.resolveToSpotifyDetailed(recordings: [recording]) { _, _ in }

        XCTAssertEqual(summary.resolved.count, 1)
        XCTAssertEqual(summary.resolved.first?.spotifyURI, "spotify:track:relaxed-hit")
    }

    func testResolveToSpotifyDetailedReturnsMissingArtistCreditsReason() async throws {
        let recording = ArtistRecordingRel(
            recordingMBID: "rec-4",
            recordingTitle: "Untitled",
            relationshipType: "main",
            attributes: [],
            artistCredits: [],
            isrcs: []
        )

        let spotifyClient = StubSpotifyWebAPI(searchTracksResponses: [:])
        let mbClient = StubMusicBrainzClient()
        let service = TrackMatchingService(musicBrainzClient: mbClient, spotifyClient: spotifyClient, maxConcurrency: 1)

        let summary = try await service.resolveToSpotifyDetailed(recordings: [recording]) { _, _ in }

        XCTAssertTrue(summary.resolved.isEmpty)
        XCTAssertEqual(summary.unresolved.count, 1)
        XCTAssertEqual(summary.unresolved.first?.reason, .missingArtistCredits)
    }

    func testResolveToSpotifyDetailedUsesFallbackArtistsWhenCreditsMissing() async throws {
        let recording = ArtistRecordingRel(
            recordingMBID: "rec-5",
            recordingTitle: "From tha Chuuuch to da Palace",
            relationshipType: "producer",
            attributes: [],
            artistCredits: [],
            isrcs: []
        )

        let spotifyClient = StubSpotifyWebAPI(
            searchTracksResponses: [
                "From tha Chuuuch to da Palace||Snoop Dogg": [
                    spotifyTrack(
                        id: "sp-5",
                        name: "From tha Chuuuch to da Palace",
                        uri: "spotify:track:5",
                        artists: ["Snoop Dogg", "Pharrell Williams"],
                        popularity: 70
                    )
                ]
            ]
        )
        let mbClient = StubMusicBrainzClient()
        let service = TrackMatchingService(musicBrainzClient: mbClient, spotifyClient: spotifyClient, maxConcurrency: 1)

        let summary = try await service.resolveToSpotifyDetailed(
            recordings: [recording],
            fallbackArtistQueries: ["Snoop Dogg", "Pharrell Williams"]
        ) { _, _ in }

        XCTAssertEqual(summary.resolved.count, 1)
        XCTAssertTrue(summary.unresolved.isEmpty)

        let queries = await spotifyClient.recordedTextQueries()
        XCTAssertTrue(queries.contains("From tha Chuuuch to da Palace||Snoop Dogg"))
    }

    func testResolveToSpotifyDetailedUsesDiscogsHintsWhenNoArtistQueriesAvailable() async throws {
        let recording = ArtistRecordingRel(
            recordingMBID: "rec-6",
            recordingTitle: "I’m Lovin’ It",
            relationshipType: "producer",
            attributes: [],
            artistCredits: [],
            isrcs: []
        )

        let spotifyClient = StubSpotifyWebAPI(
            searchTracksResponses: [
                "I’m Lovin’ It||Pharrell Williams": [
                    spotifyTrack(
                        id: "sp-6",
                        name: "I'm Lovin' It",
                        uri: "spotify:track:6",
                        artists: ["Justin Timberlake", "Pharrell Williams"],
                        popularity: 65
                    )
                ]
            ]
        )
        let mbClient = StubMusicBrainzClient()
        let discogsClient = StubDiscogsClient(
            hintsByTitle: [
                "I’m Lovin’ It": ["Pharrell Williams"]
            ]
        )

        let service = TrackMatchingService(
            musicBrainzClient: mbClient,
            spotifyClient: spotifyClient,
            discogsClient: discogsClient,
            maxConcurrency: 1
        )

        let summary = try await service.resolveToSpotifyDetailed(
            recordings: [recording],
            fallbackArtistQueries: []
        ) { _, _ in }

        XCTAssertEqual(summary.resolved.count, 1)
        XCTAssertTrue(summary.unresolved.isEmpty)

        let discogsQueries = await discogsClient.recordedQueries()
        XCTAssertEqual(discogsQueries, ["I’m Lovin’ It"])
    }

    func testResolveToSpotifyDetailedUsesDiscogsHintsAfterBaseQueriesFail() async throws {
        let recording = ArtistRecordingRel(
            recordingMBID: "rec-7",
            recordingTitle: "From tha Chuuuch to da Palace",
            relationshipType: "producer",
            attributes: [],
            artistCredits: ["Wrong Alias"],
            isrcs: []
        )

        let spotifyClient = StubSpotifyWebAPI(
            searchTracksResponses: [
                "From tha Chuuuch to da Palace||Wrong Alias": [],
                "From tha Chuuuch to da Palace||Pharrell Williams": [
                    spotifyTrack(
                        id: "sp-7",
                        name: "From tha Chuuuch to da Palace",
                        uri: "spotify:track:7",
                        artists: ["Snoop Dogg", "Pharrell Williams"],
                        popularity: 68
                    )
                ]
            ]
        )
        let mbClient = StubMusicBrainzClient()
        let discogsClient = StubDiscogsClient(
            hintsByTitle: [
                "From tha Chuuuch to da Palace": ["Pharrell Williams"]
            ]
        )

        let service = TrackMatchingService(
            musicBrainzClient: mbClient,
            spotifyClient: spotifyClient,
            discogsClient: discogsClient,
            maxConcurrency: 1
        )

        let summary = try await service.resolveToSpotifyDetailed(
            recordings: [recording],
            fallbackArtistQueries: []
        ) { _, _ in }

        XCTAssertEqual(summary.resolved.count, 1)
        XCTAssertTrue(summary.unresolved.isEmpty)

        let queries = await spotifyClient.recordedTextQueries()
        XCTAssertTrue(queries.contains("From tha Chuuuch to da Palace||Wrong Alias"))
        XCTAssertTrue(queries.contains("From tha Chuuuch to da Palace||Pharrell Williams"))

        let discogsQueries = await discogsClient.recordedQueries()
        XCTAssertEqual(discogsQueries, ["From tha Chuuuch to da Palace"])
    }

    func testResolveToSpotifyDetailedSkipsDuplicateDiscogsHintsAlreadyQueried() async throws {
        let recording = ArtistRecordingRel(
            recordingMBID: "rec-8",
            recordingTitle: "Beautiful",
            relationshipType: "main",
            attributes: [],
            artistCredits: ["Pharrell Williams"],
            isrcs: []
        )

        let spotifyClient = StubSpotifyWebAPI(
            searchTracksResponses: [
                "Beautiful||Pharrell Williams": [],
                "Beautiful||Snoop Dogg": [
                    spotifyTrack(
                        id: "sp-8",
                        name: "Beautiful",
                        uri: "spotify:track:8",
                        artists: ["Snoop Dogg", "Pharrell Williams"],
                        popularity: 75
                    )
                ]
            ]
        )
        let mbClient = StubMusicBrainzClient()
        let discogsClient = StubDiscogsClient(
            hintsByTitle: [
                "Beautiful": ["Pharrell Williams", "Snoop Dogg"]
            ]
        )

        let service = TrackMatchingService(
            musicBrainzClient: mbClient,
            spotifyClient: spotifyClient,
            discogsClient: discogsClient,
            maxConcurrency: 1
        )

        let summary = try await service.resolveToSpotifyDetailed(
            recordings: [recording],
            fallbackArtistQueries: []
        ) { _, _ in }

        XCTAssertEqual(summary.resolved.count, 1)
        XCTAssertTrue(summary.unresolved.isEmpty)

        let queries = await spotifyClient.recordedTextQueries()
        XCTAssertEqual(queries.filter { $0 == "Beautiful||Pharrell Williams" }.count, 1)
        XCTAssertTrue(queries.contains("Beautiful||Snoop Dogg"))
    }
}

private actor StubMusicBrainzClient: MusicBrainzClient {
    var isrcsByRecordingID: [String: [String]]

    init(isrcsByRecordingID: [String: [String]] = [:]) {
        self.isrcsByRecordingID = isrcsByRecordingID
    }

    func searchRecordings(query: RecordingQuery) async throws -> [RecordingCandidate] { [] }
    func getRecording(id: String) async throws -> MBRecordingDetail {
        MBRecordingDetail(id: id, title: "", relations: [], releases: [])
    }
    func getWork(id: String) async throws -> MBWorkDetail {
        MBWorkDetail(id: id, title: "", relations: [])
    }
    func getRelease(id: String) async throws -> MBReleaseDetail {
        MBReleaseDetail(id: id, title: "", relations: [])
    }
    func getArtistRecordingRels(id: String) async throws -> [ArtistRecordingRel] { [] }
    func getArtistWorkRels(id: String) async throws -> [ArtistWorkRel] { [] }
    func getWorkRecordings(id: String) async throws -> [WorkRecordingRel] { [] }
    func browseRecordings(artistID: String, offset: Int, limit: Int, includeISRCs: Bool) async throws -> MBBrowseRecordingsPage {
        MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: offset)
    }
    func getRecordingISRCs(id: String) async throws -> [String] {
        isrcsByRecordingID[id] ?? []
    }
    func searchArtists(name: String) async throws -> [MBArtistSearchResult] { [] }
}

private actor StubSpotifyWebAPI: SpotifyWebAPI {
    let searchTrackByISRCResponses: [String: [SpotifyTrack]]
    let searchTracksResponses: [String: [SpotifyTrack]]
    private var textQueries: [String] = []

    init(
        searchTrackByISRCResponses: [String: [SpotifyTrack]] = [:],
        searchTracksResponses: [String: [SpotifyTrack]]
    ) {
        self.searchTrackByISRCResponses = searchTrackByISRCResponses
        self.searchTracksResponses = searchTracksResponses
    }

    var isAuthenticated: Bool { true }

    func searchTrackByISRC(_ isrc: String) async throws -> [SpotifyTrack] {
        searchTrackByISRCResponses[isrc] ?? []
    }

    func searchTracks(title: String, artist: String) async throws -> [SpotifyTrack] {
        let key = "\(title)||\(artist)"
        textQueries.append(key)
        return searchTracksResponses[key] ?? []
    }

    func createPlaylist(name: String, description: String, isPublic: Bool) async throws -> SpotifyPlaylist {
        SpotifyPlaylist(id: "playlist", name: name, url: nil)
    }

    func addTracksToPlaylist(playlistID: String, trackURIs: [String]) async throws {}

    func recordedTextQueries() -> [String] {
        textQueries
    }
}

private actor StubDiscogsClient: DiscogsClient {
    let hintsByTitle: [String: [String]]
    private var queries: [String] = []

    init(hintsByTitle: [String: [String]] = [:]) {
        self.hintsByTitle = hintsByTitle
    }

    func artistHintsForTrack(title: String, artistHints: [String], limit: Int) async throws -> [String] {
        queries.append(title)
        return Array((hintsByTitle[title] ?? []).prefix(max(0, limit)))
    }

    func recordedQueries() -> [String] {
        queries
    }
}

private func spotifyTrack(
    id: String,
    name: String,
    uri: String,
    artists: [String],
    popularity: Int,
    isrc: String? = nil
) -> SpotifyTrack {
    SpotifyTrack(
        id: id,
        name: name,
        uri: uri,
        artistNames: artists,
        albumName: "Album",
        isrc: isrc,
        popularity: popularity
    )
}
