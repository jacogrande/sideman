import XCTest
@testable import SidemanApp

final class WikipediaPageResolverTests: XCTestCase {
    func testResolvePageReturnsBestCandidate() async {
        let track = NowPlayingTrack(
            id: "spotify:track:1",
            title: "Concorde",
            artist: "Black Country, New Road",
            album: "Ants from Up There"
        )

        let client = StubResolverWikipediaClient(resultsByQuery: [
            "Ants from Up There Black Country, New Road album": [
                WikipediaSearchResult(
                    pageID: 10,
                    title: "Ants from Up There",
                    snippet: "Ants from Up There is the second studio album by Black Country, New Road."
                ),
                WikipediaSearchResult(
                    pageID: 11,
                    title: "Concorde",
                    snippet: "Concorde may refer to multiple topics."
                )
            ]
        ])

        let resolver = DefaultWikipediaPageResolver(client: client)
        let result = await resolver.resolvePage(for: track)

        switch result {
        case .success(let page):
            XCTAssertEqual(page.pageID, 10)
            XCTAssertGreaterThan(page.confidence, 0.45)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testResolvePageAcceptsHighConfidenceEvenWhenTied() async {
        // When two candidates both score >= 0.95, the resolver should accept the
        // top one rather than returning ambiguous — high confidence means we trust
        // the match even if there's a close runner-up.
        let track = NowPlayingTrack(
            id: "spotify:track:2",
            title: "Concorde",
            artist: "Black Country, New Road",
            album: "Ants from Up There"
        )

        let client = StubResolverWikipediaClient(resultsByQuery: [
            "Ants from Up There Black Country, New Road album": [
                WikipediaSearchResult(
                    pageID: 20,
                    title: "Ants from Up There (album)",
                    snippet: "Album by Black Country, New Road."
                ),
                WikipediaSearchResult(
                    pageID: 21,
                    title: "Ants from Up There album",
                    snippet: "Ants from Up There is an album by Black Country, New Road."
                )
            ]
        ])

        let resolver = DefaultWikipediaPageResolver(client: client)
        let result = await resolver.resolvePage(for: track)

        switch result {
        case .success(let page):
            XCTAssertEqual(page.pageID, 20)
            XCTAssertGreaterThanOrEqual(page.confidence, 0.95)
        case .failure(let error):
            XCTFail("Expected success for high-confidence match, got \(error)")
        }
    }

    func testResolvePageReturnsAmbiguousWhenMidScoresAreTooClose() async {
        // When two candidates score in the mid range (0.60-0.94) with a small
        // margin, the resolver should return ambiguous. Both titles here contain
        // the album name as a substring (giving ~0.87 via containsMatchScore)
        // but neither reaches the 0.95 high-confidence threshold.
        let track = NowPlayingTrack(
            id: "spotify:track:2b",
            title: "Raindrop",
            artist: "The Echoes",
            album: "Midnight Sessions"
        )

        let client = StubResolverWikipediaClient(resultsByQuery: [
            "Midnight Sessions The Echoes album": [
                WikipediaSearchResult(
                    pageID: 30,
                    title: "Midnight Sessions Live",
                    snippet: "A live recording from 2019."
                ),
                WikipediaSearchResult(
                    pageID: 31,
                    title: "Midnight Sessions Tour",
                    snippet: "A concert tour in 2020."
                )
            ]
        ])

        let resolver = DefaultWikipediaPageResolver(client: client)
        let result = await resolver.resolvePage(for: track)

        switch result {
        case .success(let page):
            XCTFail("Expected ambiguous result, got success \(page)")
        case .failure(let error):
            XCTAssertEqual(error, .ambiguous)
        }
    }

    func testResolvePageReturnsNotFoundWhenNoCandidates() async {
        let track = NowPlayingTrack(
            id: "spotify:track:3",
            title: "Unknown Song",
            artist: "Unknown Artist",
            album: "Unknown Album"
        )

        let client = StubResolverWikipediaClient(resultsByQuery: [:])
        let resolver = DefaultWikipediaPageResolver(client: client)
        let result = await resolver.resolvePage(for: track)

        switch result {
        case .success(let page):
            XCTFail("Expected notFound, got success \(page)")
        case .failure(let error):
            XCTAssertEqual(error, .notFound)
        }
    }
}

private actor StubResolverWikipediaClient: WikipediaAPIClient {
    let resultsByQuery: [String: [WikipediaSearchResult]]

    init(resultsByQuery: [String: [WikipediaSearchResult]]) {
        self.resultsByQuery = resultsByQuery
    }

    func searchPages(query: String, limit: Int) async throws -> [WikipediaSearchResult] {
        resultsByQuery[query] ?? []
    }

    func fetchPage(pageID: Int) async throws -> WikipediaPageContent {
        throw WikipediaClientError.notFound
    }
}
