import XCTest
@testable import SidemanApp

final class DefaultTrackResolverTests: XCTestCase {
    func testResolveReturnsSuccessForStrongSingleCandidate() async {
        let candidate = RecordingCandidate(
            recordingMBID: "rec-1",
            title: "Take Five",
            artistNames: ["The Dave Brubeck Quartet"],
            releaseTitles: ["Time Out"],
            releaseIDs: ["rel-1"],
            musicBrainzScore: 100
        )

        let client = StubMusicBrainzClient(searchResults: [candidate])
        let resolver = DefaultTrackResolver(client: client)

        let track = NowPlayingTrack(
            id: "spotify:track:123",
            title: "Take Five",
            artist: "The Dave Brubeck Quartet",
            album: "Time Out"
        )

        let result = await resolver.resolve(track)

        switch result {
        case .success(let resolution):
            XCTAssertEqual(resolution.recordingMBID, "rec-1")
            XCTAssertEqual(resolution.releaseMBID, "rel-1")
            XCTAssertGreaterThanOrEqual(resolution.confidence, 0.78)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testResolveReturnsAmbiguousWhenMarginTooSmall() async {
        let candidateA = RecordingCandidate(
            recordingMBID: "rec-a",
            title: "Midnight City",
            artistNames: ["M83"],
            releaseTitles: ["Hurry Up, We're Dreaming"],
            releaseIDs: ["rel-a"],
            musicBrainzScore: 90
        )

        let candidateB = RecordingCandidate(
            recordingMBID: "rec-b",
            title: "Midnight City",
            artistNames: ["M83"],
            releaseTitles: ["Hurry Up, We're Dreaming"],
            releaseIDs: ["rel-b"],
            musicBrainzScore: 88
        )

        let client = StubMusicBrainzClient(searchResults: [candidateA, candidateB])
        let resolver = DefaultTrackResolver(client: client)

        let track = NowPlayingTrack(
            id: "spotify:track:456",
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming"
        )

        let result = await resolver.resolve(track)

        switch result {
        case .success:
            XCTFail("Expected ambiguous resolution")
        case .failure(let error):
            XCTAssertEqual(error, .ambiguous)
        }
    }

    func testResolveMapsRateLimitedError() async {
        let client = StubMusicBrainzClient(searchResults: [], searchError: .rateLimited)
        let resolver = DefaultTrackResolver(client: client)

        let track = NowPlayingTrack(id: "", title: "Song", artist: "Artist", album: "Album")
        let result = await resolver.resolve(track)

        switch result {
        case .success:
            XCTFail("Expected rate limited")
        case .failure(let error):
            XCTAssertEqual(error, .rateLimited)
        }
    }

    func testResolveReturnsNotFoundWhenNoCandidates() async {
        let client = StubMusicBrainzClient(searchResults: [])
        let resolver = DefaultTrackResolver(client: client)

        let track = NowPlayingTrack(id: "", title: "Unknown Song", artist: "Unknown Artist", album: "")
        let result = await resolver.resolve(track)

        switch result {
        case .success:
            XCTFail("Expected not found")
        case .failure(let error):
            XCTAssertEqual(error, .notFound)
        }
    }
}

private actor StubMusicBrainzClient: MusicBrainzClient {
    let searchResults: [RecordingCandidate]
    let searchError: MusicBrainzClientError?

    init(searchResults: [RecordingCandidate], searchError: MusicBrainzClientError? = nil) {
        self.searchResults = searchResults
        self.searchError = searchError
    }

    func searchRecordings(query: RecordingQuery) async throws -> [RecordingCandidate] {
        if let searchError {
            throw searchError
        }
        return searchResults
    }

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
        MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: 0)
    }
    func getRecordingISRCs(id: String) async throws -> [String] { [] }
    func searchArtists(name: String) async throws -> [MBArtistSearchResult] { [] }
}
