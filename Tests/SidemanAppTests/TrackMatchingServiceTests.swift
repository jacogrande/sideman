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
