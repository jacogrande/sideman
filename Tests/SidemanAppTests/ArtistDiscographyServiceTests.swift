import XCTest
@testable import SidemanApp

final class ArtistDiscographyServiceTests: XCTestCase {
    func testFetchDiscographyMergesRelAndBrowseRecordings() async throws {
        let relRecording = ArtistRecordingRel(
            recordingMBID: "rec-rel-1",
            recordingTitle: "Session Track",
            relationshipType: "instrument",
            attributes: ["bass guitar"],
            artistCredits: ["Main Artist"],
            isrcs: []
        )

        let browseRecording = ArtistRecordingRel(
            recordingMBID: "rec-browse-1",
            recordingTitle: "Main Track",
            relationshipType: "main",
            attributes: [],
            artistCredits: ["Test Artist"],
            isrcs: []
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
            artistCredits: ["Artist"],
            isrcs: []
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
                        artistCredits: ["Artist"],
                        isrcs: []
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
            artistCredits: ["Pianist"],
            isrcs: []
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

    func testFetchCoCreditDiscographyIntersectsAcrossRelAndBrowse() async throws {
        let sharedFromRels = ArtistRecordingRel(
            recordingMBID: "rec-shared-rel",
            recordingTitle: "Shared Rel Track",
            relationshipType: "producer",
            attributes: [],
            artistCredits: ["Artist A"],
            isrcs: []
        )
        let sharedFromBrowse = ArtistRecordingRel(
            recordingMBID: "rec-shared-browse",
            recordingTitle: "Shared Browse Track",
            relationshipType: "main",
            attributes: [],
            artistCredits: ["Artist A"],
            isrcs: []
        )

        let client = StubMBClient(
            artistRecordingRelsByID: [
                "artist-a": [sharedFromRels],
                "artist-b": [
                    ArtistRecordingRel(
                        recordingMBID: "rec-shared-browse",
                        recordingTitle: "Shared Browse Track",
                        relationshipType: "writer",
                        attributes: [],
                        artistCredits: ["Artist B"],
                        isrcs: []
                    )
                ]
            ],
            browsePagesByArtist: [
                "artist-a": [
                    MBBrowseRecordingsPage(
                        recordings: [sharedFromBrowse],
                        totalCount: 1,
                        offset: 0
                    )
                ],
                "artist-b": [
                    MBBrowseRecordingsPage(
                        recordings: [
                            ArtistRecordingRel(
                                recordingMBID: "rec-shared-rel",
                                recordingTitle: "Shared Rel Track",
                                relationshipType: "main",
                                attributes: [],
                                artistCredits: ["Artist B"],
                                isrcs: ["ISRC123"]
                            )
                        ],
                        totalCount: 1,
                        offset: 0
                    )
                ]
            ]
        )

        let cache = DiscographyCache(fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-disco-\(UUID().uuidString).json"))
        let service = ArtistDiscographyService(musicBrainzClient: client, cache: cache)

        let result = try await service.fetchCoCreditDiscography(
            artistA: CoCreditArtist(name: "Artist A", mbid: "artist-a"),
            artistB: CoCreditArtist(name: "Artist B", mbid: "artist-b"),
            matchMode: .anyInvolvement
        )

        let ids = Set(result.recordings.map(\.recordingMBID))
        XCTAssertEqual(ids, Set(["rec-shared-rel", "rec-shared-browse"]))
    }

    func testFetchCoCreditDiscographyThrowsWhenNoIntersection() async {
        let client = StubMBClient(
            artistRecordingRelsByID: [
                "artist-a": [
                    ArtistRecordingRel(
                        recordingMBID: "rec-a-only",
                        recordingTitle: "A Only",
                        relationshipType: "producer",
                        attributes: [],
                        artistCredits: ["Artist A"],
                        isrcs: []
                    )
                ],
                "artist-b": [
                    ArtistRecordingRel(
                        recordingMBID: "rec-b-only",
                        recordingTitle: "B Only",
                        relationshipType: "writer",
                        attributes: [],
                        artistCredits: ["Artist B"],
                        isrcs: []
                    )
                ]
            ],
            browsePagesByArtist: [
                "artist-a": [MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: 0)],
                "artist-b": [MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: 0)]
            ]
        )

        let cache = DiscographyCache(fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-disco-\(UUID().uuidString).json"))
        let service = ArtistDiscographyService(musicBrainzClient: client, cache: cache)

        do {
            _ = try await service.fetchCoCreditDiscography(
                artistA: CoCreditArtist(name: "Artist A", mbid: "artist-a"),
                artistB: CoCreditArtist(name: "Artist B", mbid: "artist-b"),
                matchMode: .anyInvolvement
            )
            XCTFail("Expected noIntersectionFound")
        } catch let error as PlaylistBuilderError {
            XCTAssertEqual(error, .noIntersectionFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchCoCreditDiscographyUsesPairCache() async throws {
        let shared = ArtistRecordingRel(
            recordingMBID: "rec-shared",
            recordingTitle: "Shared",
            relationshipType: "producer",
            attributes: [],
            artistCredits: ["Artist A"],
            isrcs: []
        )

        let client = StubMBClient(
            artistRecordingRelsByID: [
                "artist-a": [shared],
                "artist-b": [shared]
            ],
            browsePagesByArtist: [
                "artist-a": [MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: 0)],
                "artist-b": [MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: 0)]
            ]
        )

        let cache = DiscographyCache(fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-disco-\(UUID().uuidString).json"))
        let service = ArtistDiscographyService(musicBrainzClient: client, cache: cache)

        let first = try await service.fetchCoCreditDiscography(
            artistA: CoCreditArtist(name: "Artist A", mbid: "artist-a"),
            artistB: CoCreditArtist(name: "Artist B", mbid: "artist-b"),
            matchMode: .anyInvolvement
        )
        let firstCalls = await client.callCounts()

        let second = try await service.fetchCoCreditDiscography(
            artistA: CoCreditArtist(name: "Artist A", mbid: "artist-a"),
            artistB: CoCreditArtist(name: "Artist B", mbid: "artist-b"),
            matchMode: .anyInvolvement
        )
        let secondCalls = await client.callCounts()

        XCTAssertEqual(first.fetchedAt, second.fetchedAt)
        XCTAssertEqual(firstCalls.relCalls, secondCalls.relCalls)
        XCTAssertEqual(firstCalls.browseCalls, secondCalls.browseCalls)
    }
}

private actor StubMBClient: MusicBrainzClient {
    let artistRecordingRelsByID: [String: [ArtistRecordingRel]]
    let browsePagesByArtist: [String: [MBBrowseRecordingsPage]]
    private var browseCallIndexByArtist: [String: Int] = [:]
    private var relCalls: Int = 0
    private var browseCalls: Int = 0

    init(artistRecordingRels: [ArtistRecordingRel], browsePages: [MBBrowseRecordingsPage]) {
        self.artistRecordingRelsByID = ["*": artistRecordingRels]
        self.browsePagesByArtist = ["*": browsePages]
    }

    init(artistRecordingRelsByID: [String: [ArtistRecordingRel]], browsePagesByArtist: [String: [MBBrowseRecordingsPage]]) {
        self.artistRecordingRelsByID = artistRecordingRelsByID
        self.browsePagesByArtist = browsePagesByArtist
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
        relCalls += 1
        return artistRecordingRelsByID[id] ?? artistRecordingRelsByID["*"] ?? []
    }
    func browseRecordings(artistID: String, offset: Int, limit: Int, includeISRCs: Bool) async throws -> MBBrowseRecordingsPage {
        browseCalls += 1
        let key = browsePagesByArtist[artistID] != nil ? artistID : "*"
        let pages = browsePagesByArtist[key] ?? []
        let currentIndex = browseCallIndexByArtist[key, default: 0]
        guard currentIndex < pages.count else {
            return MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: offset)
        }
        let page = pages[currentIndex]
        browseCallIndexByArtist[key, default: 0] += 1
        return page
    }
    func getRecordingISRCs(id: String) async throws -> [String] { [] }
    func searchArtists(name: String) async throws -> [MBArtistSearchResult] { [] }

    func callCounts() -> (relCalls: Int, browseCalls: Int) {
        (relCalls, browseCalls)
    }
}
