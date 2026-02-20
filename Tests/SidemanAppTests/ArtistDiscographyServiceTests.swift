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
        XCTAssertEqual(firstCalls.workRelCalls, secondCalls.workRelCalls)
        XCTAssertEqual(firstCalls.workRecordingCalls, secondCalls.workRecordingCalls)
    }

    func testFetchCoCreditDiscographyFallsBackToTitleAndArtistCreditOverlap() async throws {
        let client = StubMBClient(
            artistRecordingRelsByID: [
                "artist-a": [
                    ArtistRecordingRel(
                        recordingMBID: "rec-a-beautiful",
                        recordingTitle: "Beautiful (Album Version)",
                        relationshipType: "main",
                        attributes: [],
                        artistCredits: ["Snoop Dogg", "Pharrell Williams"],
                        isrcs: []
                    )
                ],
                "artist-b": [
                    ArtistRecordingRel(
                        recordingMBID: "rec-b-beautiful",
                        recordingTitle: "Beautiful",
                        relationshipType: "producer",
                        attributes: [],
                        artistCredits: ["Snoop Dogg", "Pharrell Williams"],
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

        let result = try await service.fetchCoCreditDiscography(
            artistA: CoCreditArtist(name: "Snoop Dogg", mbid: "artist-a"),
            artistB: CoCreditArtist(name: "Pharrell Williams", mbid: "artist-b"),
            matchMode: .anyInvolvement
        )

        XCTAssertEqual(result.recordings.count, 1)
        XCTAssertEqual(result.recordings.first?.recordingTitle, "Beautiful (Album Version)")
        XCTAssertEqual(
            Set(result.recordings.first?.artistCredits ?? []),
            Set(["Snoop Dogg", "Pharrell Williams"])
        )
    }

    func testFetchCoCreditDiscographyFallsBackToSharedISRCWhenArtistCreditsDiffer() async throws {
        let client = StubMBClient(
            artistRecordingRelsByID: [
                "artist-a": [
                    ArtistRecordingRel(
                        recordingMBID: "rec-a",
                        recordingTitle: "Beautiful - Radio Edit",
                        relationshipType: "main",
                        attributes: [],
                        artistCredits: ["Snoop Dogg"],
                        isrcs: ["US1234567890"]
                    )
                ],
                "artist-b": [
                    ArtistRecordingRel(
                        recordingMBID: "rec-b",
                        recordingTitle: "Beautiful",
                        relationshipType: "producer",
                        attributes: [],
                        artistCredits: ["Pharrell Williams"],
                        isrcs: ["us1234567890"]
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

        let result = try await service.fetchCoCreditDiscography(
            artistA: CoCreditArtist(name: "Snoop Dogg", mbid: "artist-a"),
            artistB: CoCreditArtist(name: "Pharrell Williams", mbid: "artist-b"),
            matchMode: .anyInvolvement
        )

        XCTAssertEqual(result.recordings.count, 1)
        XCTAssertEqual(result.recordings.first?.recordingMBID, "rec-a")
        XCTAssertEqual(result.recordings.first?.isrcs, ["US1234567890"])
    }

    func testFetchCoCreditDiscographyIncludesWorkLevelOverlap() async throws {
        let client = StubMBClient(
            artistRecordingRelsByID: [
                "artist-a": [],
                "artist-b": [
                    ArtistRecordingRel(
                        recordingMBID: "rec-shared-work",
                        recordingTitle: "Shared Work Track",
                        relationshipType: "main",
                        attributes: [],
                        artistCredits: ["Artist B", "Artist A"],
                        isrcs: ["USWORK000001"]
                    )
                ]
            ],
            browsePagesByArtist: [
                "artist-a": [MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: 0)],
                "artist-b": [MBBrowseRecordingsPage(recordings: [], totalCount: 0, offset: 0)]
            ],
            artistWorkRelsByID: [
                "artist-a": [
                    ArtistWorkRel(
                        workMBID: "work-1",
                        workTitle: "Shared Work",
                        relationshipType: "writer",
                        attributes: ["lyrics"]
                    )
                ]
            ],
            workRecordingsByWorkID: [
                "work-1": [
                    WorkRecordingRel(
                        recordingMBID: "rec-work-artist-a",
                        recordingTitle: "Shared Work Track",
                        artistCredits: ["Artist B", "Artist A"],
                        isrcs: ["USWORK000001"]
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

        XCTAssertEqual(result.recordings.count, 1)
        XCTAssertEqual(result.recordings.first?.recordingTitle, "Shared Work Track")
        XCTAssertEqual(
            Set(result.recordings.first?.evidence.map(\.source) ?? []),
            Set([.workRel, .recordingRel])
        )
    }

    func testFetchCoCreditDiscographyCanonicalizesVariantsByISRC() async throws {
        let client = StubMBClient(
            artistRecordingRelsByID: [
                "artist-a": [
                    ArtistRecordingRel(
                        recordingMBID: "rec-a-v1",
                        recordingTitle: "Beautiful (Album Version)",
                        relationshipType: "main",
                        attributes: [],
                        artistCredits: ["Snoop Dogg", "Pharrell Williams"],
                        isrcs: ["US1234567890"]
                    ),
                    ArtistRecordingRel(
                        recordingMBID: "rec-a-v2",
                        recordingTitle: "Beautiful - Radio Edit",
                        relationshipType: "main",
                        attributes: [],
                        artistCredits: ["Snoop Dogg", "Pharrell Williams"],
                        isrcs: ["US1234567890"]
                    )
                ],
                "artist-b": [
                    ArtistRecordingRel(
                        recordingMBID: "rec-b-v1",
                        recordingTitle: "Beautiful",
                        relationshipType: "producer",
                        attributes: [],
                        artistCredits: ["Snoop Dogg", "Pharrell Williams"],
                        isrcs: ["us1234567890"]
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

        let result = try await service.fetchCoCreditDiscography(
            artistA: CoCreditArtist(name: "Snoop Dogg", mbid: "artist-a"),
            artistB: CoCreditArtist(name: "Pharrell Williams", mbid: "artist-b"),
            matchMode: .anyInvolvement
        )

        XCTAssertEqual(result.recordings.count, 1)
        XCTAssertEqual(result.recordings.first?.isrcs, ["US1234567890"])
    }
}

private actor StubMBClient: MusicBrainzClient {
    let artistRecordingRelsByID: [String: [ArtistRecordingRel]]
    let browsePagesByArtist: [String: [MBBrowseRecordingsPage]]
    let artistWorkRelsByID: [String: [ArtistWorkRel]]
    let workRecordingsByWorkID: [String: [WorkRecordingRel]]
    private var browseCallIndexByArtist: [String: Int] = [:]
    private var relCalls: Int = 0
    private var browseCalls: Int = 0
    private var workRelCalls: Int = 0
    private var workRecordingCalls: Int = 0

    init(artistRecordingRels: [ArtistRecordingRel], browsePages: [MBBrowseRecordingsPage]) {
        self.artistRecordingRelsByID = ["*": artistRecordingRels]
        self.browsePagesByArtist = ["*": browsePages]
        self.artistWorkRelsByID = [:]
        self.workRecordingsByWorkID = [:]
    }

    init(
        artistRecordingRelsByID: [String: [ArtistRecordingRel]],
        browsePagesByArtist: [String: [MBBrowseRecordingsPage]],
        artistWorkRelsByID: [String: [ArtistWorkRel]] = [:],
        workRecordingsByWorkID: [String: [WorkRecordingRel]] = [:]
    ) {
        self.artistRecordingRelsByID = artistRecordingRelsByID
        self.browsePagesByArtist = browsePagesByArtist
        self.artistWorkRelsByID = artistWorkRelsByID
        self.workRecordingsByWorkID = workRecordingsByWorkID
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
    func getArtistWorkRels(id: String) async throws -> [ArtistWorkRel] {
        workRelCalls += 1
        return artistWorkRelsByID[id] ?? artistWorkRelsByID["*"] ?? []
    }
    func getWorkRecordings(id: String) async throws -> [WorkRecordingRel] {
        workRecordingCalls += 1
        return workRecordingsByWorkID[id] ?? workRecordingsByWorkID["*"] ?? []
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

    func callCounts() -> (relCalls: Int, browseCalls: Int, workRelCalls: Int, workRecordingCalls: Int) {
        (relCalls, browseCalls, workRelCalls, workRecordingCalls)
    }
}
