import XCTest
@testable import SidemanApp

final class ArtistDiscographyServiceTests: XCTestCase {
    func testFetchDiscographyMergesRelAndBrowseRecordings() async throws {
        let relRecording = ArtistRecordingRel(
            recordingMBID: "rec-rel-1",
            recordingTitle: "Session Track",
            relationshipType: "instrument",
            attributes: ["bass guitar"],
            artistCredits: ["Main Artist"]
        )

        let browseRecording = ArtistRecordingRel(
            recordingMBID: "rec-browse-1",
            recordingTitle: "Main Track",
            relationshipType: "main",
            attributes: [],
            artistCredits: ["Test Artist"]
        )

        let client = StubMBClient(
            artistRecordingRels: [relRecording],
            browsePages: [
                MBBrowseRecordingsPage(recordings: [browseRecording], totalCount: 1, offset: 0)
            ]
        )

        let cache = DiscographyCache(fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-disco-\(UUID().uuidString).json"))
        let service = ArtistDiscographyService(musicBrainzClient: client, cache: cache)

        let result = try await service.fetchDiscography(
            artistMBID: "artist-1",
            artistName: "Test Artist",
            roleFilter: nil
        )

        XCTAssertEqual(result.artistMBID, "artist-1")
        XCTAssertEqual(result.recordings.count, 2)
        XCTAssertTrue(result.recordings.contains(where: { $0.recordingMBID == "rec-rel-1" }))
        XCTAssertTrue(result.recordings.contains(where: { $0.recordingMBID == "rec-browse-1" }))
    }

    func testFetchDiscographyDeduplicatesByMBID() async throws {
        let recording = ArtistRecordingRel(
            recordingMBID: "rec-dup",
            recordingTitle: "Duplicate Track",
            relationshipType: "instrument",
            attributes: ["guitar"],
            artistCredits: ["Artist"]
        )

        let client = StubMBClient(
            artistRecordingRels: [recording],
            browsePages: [
                MBBrowseRecordingsPage(recordings: [
                    ArtistRecordingRel(
                        recordingMBID: "rec-dup",
                        recordingTitle: "Duplicate Track",
                        relationshipType: "main",
                        attributes: [],
                        artistCredits: ["Artist"]
                    )
                ], totalCount: 1, offset: 0)
            ]
        )

        let cache = DiscographyCache(fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-disco-\(UUID().uuidString).json"))
        let service = ArtistDiscographyService(musicBrainzClient: client, cache: cache)

        let result = try await service.fetchDiscography(
            artistMBID: "artist-dup",
            artistName: "Artist",
            roleFilter: nil
        )

        XCTAssertEqual(result.recordings.count, 1)
    }

    func testFetchDiscographyThrowsWhenNoRecordings() async {
        let client = StubMBClient(
            artistRecordingRels: [],
            browsePages: [MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: 0)]
        )

        let cache = DiscographyCache(fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-disco-\(UUID().uuidString).json"))
        let service = ArtistDiscographyService(musicBrainzClient: client, cache: cache)

        do {
            _ = try await service.fetchDiscography(
                artistMBID: "artist-empty",
                artistName: "Unknown",
                roleFilter: nil
            )
            XCTFail("Expected noRecordingsFound error")
        } catch let error as PlaylistBuilderError {
            XCTAssertEqual(error, .noRecordingsFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchDiscographyUsesCacheOnSecondCall() async throws {
        let recording = ArtistRecordingRel(
            recordingMBID: "rec-cached",
            recordingTitle: "Cached Track",
            relationshipType: "instrument",
            attributes: ["piano"],
            artistCredits: ["Pianist"]
        )

        let client = StubMBClient(
            artistRecordingRels: [recording],
            browsePages: [MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: 0)]
        )

        let cache = DiscographyCache(fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-disco-\(UUID().uuidString).json"))
        let service = ArtistDiscographyService(musicBrainzClient: client, cache: cache)

        let first = try await service.fetchDiscography(
            artistMBID: "artist-cache",
            artistName: "Pianist",
            roleFilter: nil
        )

        let second = try await service.fetchDiscography(
            artistMBID: "artist-cache",
            artistName: "Pianist",
            roleFilter: nil
        )

        XCTAssertEqual(first.recordings.count, second.recordings.count)
        XCTAssertEqual(first.fetchedAt, second.fetchedAt)
    }
}

private actor StubMBClient: MusicBrainzClient {
    let artistRecordingRels: [ArtistRecordingRel]
    let browsePages: [MBBrowseRecordingsPage]
    private var browseCallIndex = 0

    init(artistRecordingRels: [ArtistRecordingRel], browsePages: [MBBrowseRecordingsPage]) {
        self.artistRecordingRels = artistRecordingRels
        self.browsePages = browsePages
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
    func getArtistRecordingRels(id: String) async throws -> [ArtistRecordingRel] {
        artistRecordingRels
    }
    func browseRecordings(artistID: String, offset: Int, limit: Int, includeISRCs: Bool) async throws -> MBBrowseRecordingsPage {
        guard browseCallIndex < browsePages.count else {
            return MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: offset)
        }
        let page = browsePages[browseCallIndex]
        browseCallIndex += 1
        return page
    }
    func getRecordingISRCs(id: String) async throws -> [String] { [] }
    func searchArtists(name: String) async throws -> [MBArtistSearchResult] { [] }
}
