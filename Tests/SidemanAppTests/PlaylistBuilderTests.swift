import XCTest
@testable import SidemanApp

final class PlaylistBuilderTests: XCTestCase {
    func testPlaylistBuildRequestDefaultValues() {
        let request = PlaylistBuildRequest(
            artistMBID: "abc-123",
            artistName: "Test Artist"
        )

        XCTAssertEqual(request.artistMBID, "abc-123")
        XCTAssertEqual(request.artistName, "Test Artist")
        XCTAssertNil(request.roleFilter)
        XCTAssertFalse(request.isPublic)
        XCTAssertEqual(request.maxTracks, 50)
    }

    func testPlaylistBuildRequestCustomValues() {
        let request = PlaylistBuildRequest(
            artistMBID: "xyz",
            artistName: "Player",
            roleFilter: .musicians,
            isPublic: true,
            maxTracks: 25
        )

        XCTAssertEqual(request.roleFilter, .musicians)
        XCTAssertTrue(request.isPublic)
        XCTAssertEqual(request.maxTracks, 25)
    }

    func testPlaylistBuildResultEquatable() {
        let result1 = PlaylistBuildResult(
            playlistName: "Test",
            playlistURI: "spotify:playlist:1",
            trackCount: 10,
            skippedCount: 2
        )
        let result2 = PlaylistBuildResult(
            playlistName: "Test",
            playlistURI: "spotify:playlist:1",
            trackCount: 10,
            skippedCount: 2
        )
        let result3 = PlaylistBuildResult(
            playlistName: "Other",
            playlistURI: "spotify:playlist:2",
            trackCount: 5,
            skippedCount: 0
        )

        XCTAssertEqual(result1, result2)
        XCTAssertNotEqual(result1, result3)
    }

    func testPlaylistBuildStageEquatable() {
        XCTAssertEqual(PlaylistBuildStage.fetchingDiscography, PlaylistBuildStage.fetchingDiscography)
        XCTAssertEqual(
            PlaylistBuildStage.resolvingTracks(resolved: 5, total: 10),
            PlaylistBuildStage.resolvingTracks(resolved: 5, total: 10)
        )
        XCTAssertNotEqual(
            PlaylistBuildStage.resolvingTracks(resolved: 5, total: 10),
            PlaylistBuildStage.resolvingTracks(resolved: 6, total: 10)
        )
        XCTAssertNotEqual(PlaylistBuildStage.fetchingDiscography, PlaylistBuildStage.creatingPlaylist(trackCount: 5))
    }

    func testPlaylistFlowPhaseEquatable() {
        let context = PersonContext(personName: "Test", personMBID: "abc", roles: ["bass"], roleGroup: .musicians)
        XCTAssertEqual(PlaylistFlowPhase.idle, PlaylistFlowPhase.idle)
        XCTAssertEqual(PlaylistFlowPhase.confirming(context), PlaylistFlowPhase.confirming(context))
        XCTAssertNotEqual(PlaylistFlowPhase.idle, PlaylistFlowPhase.authenticating)
        XCTAssertEqual(PlaylistFlowPhase.failed("error"), PlaylistFlowPhase.failed("error"))
        XCTAssertNotEqual(PlaylistFlowPhase.failed("a"), PlaylistFlowPhase.failed("b"))
    }

    func testTrackMatchStrategyRawValues() {
        XCTAssertEqual(TrackMatchStrategy.isrc.rawValue, "isrc")
        XCTAssertEqual(TrackMatchStrategy.textSearch.rawValue, "textSearch")
    }

    func testSpotifyTokensExpiration() {
        let expired = SpotifyTokens(
            accessToken: "tok",
            refreshToken: "ref",
            expiresAt: Date().addingTimeInterval(-10)
        )
        XCTAssertTrue(expired.isExpired)
        XCTAssertTrue(expired.isExpiringSoon)

        let valid = SpotifyTokens(
            accessToken: "tok",
            refreshToken: "ref",
            expiresAt: Date().addingTimeInterval(3600)
        )
        XCTAssertFalse(valid.isExpired)
        XCTAssertFalse(valid.isExpiringSoon)

        let expiringSoon = SpotifyTokens(
            accessToken: "tok",
            refreshToken: "ref",
            expiresAt: Date().addingTimeInterval(200)
        )
        XCTAssertFalse(expiringSoon.isExpired)
        XCTAssertTrue(expiringSoon.isExpiringSoon)
    }

    func testSpotifyClientErrorEquatable() {
        XCTAssertEqual(SpotifyClientError.notAuthenticated, SpotifyClientError.notAuthenticated)
        XCTAssertEqual(SpotifyClientError.rateLimited, SpotifyClientError.rateLimited)
        XCTAssertEqual(SpotifyClientError.httpStatus(403), SpotifyClientError.httpStatus(403))
        XCTAssertNotEqual(SpotifyClientError.httpStatus(403), SpotifyClientError.httpStatus(500))
    }

    func testPlaylistBuilderErrorEquatable() {
        XCTAssertEqual(PlaylistBuilderError.noRecordingsFound, PlaylistBuilderError.noRecordingsFound)
        XCTAssertEqual(PlaylistBuilderError.noTracksResolved, PlaylistBuilderError.noTracksResolved)
        XCTAssertNotEqual(PlaylistBuilderError.noRecordingsFound, PlaylistBuilderError.noTracksResolved)
    }

    func testResolvedTrackEquatable() {
        let track1 = ResolvedTrack(
            recordingMBID: "rec-1",
            recordingTitle: "Title",
            spotifyURI: "spotify:track:1",
            spotifyPopularity: 80,
            matchStrategy: .isrc
        )
        let track2 = ResolvedTrack(
            recordingMBID: "rec-1",
            recordingTitle: "Title",
            spotifyURI: "spotify:track:1",
            spotifyPopularity: 80,
            matchStrategy: .isrc
        )
        XCTAssertEqual(track1, track2)
    }

    func testDiscographyResultCodable() throws {
        let result = DiscographyResult(
            artistMBID: "abc",
            artistName: "Test Artist",
            recordings: [
                ArtistRecordingRel(
                    recordingMBID: "rec-1",
                    recordingTitle: "Track",
                    relationshipType: "instrument",
                    attributes: ["guitar"],
                    artistCredits: ["Artist"]
                )
            ],
            fetchedAt: Date(timeIntervalSince1970: 1000)
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(DiscographyResult.self, from: data)

        XCTAssertEqual(decoded.artistMBID, result.artistMBID)
        XCTAssertEqual(decoded.artistName, result.artistName)
        XCTAssertEqual(decoded.recordings.count, 1)
        XCTAssertEqual(decoded.recordings.first?.recordingMBID, "rec-1")
    }
}
