import Foundation
import XCTest
@testable import SidemanApp

final class DiscogsHTTPClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockDiscogsURLProtocol.reset()
    }

    override func tearDown() {
        MockDiscogsURLProtocol.reset()
        super.tearDown()
    }

    func testArtistHintsReturnsEmptyForBlankTitleWithoutNetworkCall() async throws {
        let client = makeClient()

        let hints = try await client.artistHintsForTrack(
            title: "   ",
            artistHints: ["Pharrell Williams"],
            limit: 3
        )

        XCTAssertTrue(hints.isEmpty)
        XCTAssertTrue(MockDiscogsURLProtocol.recordedRequests().isEmpty)
    }

    func testArtistHintsUsesAuthorizationHeaderAndArtistHintQuery() async throws {
        let client = makeClient(token: "token-123")

        MockDiscogsURLProtocol.enqueueJSON { request in
            guard let url = request.url else {
                XCTFail("Missing request URL")
                return (401, [:], [:])
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Discogs token=token-123")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))

            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let queryItems: [URLQueryItem] = components?.queryItems ?? []
            let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["type"], "release")
            XCTAssertEqual(query["track"], "Beautiful")
            XCTAssertEqual(query["artist"], "Pharrell Williams")

            return (
                200,
                [
                    "results": [
                        ["id": 101]
                    ]
                ],
                [:]
            )
        }

        MockDiscogsURLProtocol.enqueueJSON { _ in
            (
                200,
                [
                    "artists": [],
                    "tracklist": [
                        [
                            "title": "Beautiful",
                            "artists": [["name": "Pharrell Williams"]]
                        ]
                    ]
                ],
                [:]
            )
        }

        let hints = try await client.artistHintsForTrack(
            title: "Beautiful",
            artistHints: ["  Pharrell Williams  ", "Snoop Dogg"],
            limit: 3
        )

        XCTAssertEqual(hints, ["Pharrell Williams"])
    }

    func testArtistHintsPrefersTrackArtistsAndStripsDiscogsNameSuffix() async throws {
        let client = makeClient()

        MockDiscogsURLProtocol.enqueueJSON { _ in
            (
                200,
                [
                    "results": [
                        ["id": 111]
                    ]
                ],
                [:]
            )
        }
        MockDiscogsURLProtocol.enqueueJSON { _ in
            (
                200,
                [
                    "artists": [["name": "Release Artist"]],
                    "tracklist": [
                        [
                            "title": "Beautiful",
                            "artists": [
                                ["name": "Snoop Dogg (2)"],
                                ["name": "Pharrell Williams"]
                            ]
                        ]
                    ]
                ],
                [:]
            )
        }

        let hints = try await client.artistHintsForTrack(
            title: "Beautiful",
            artistHints: [],
            limit: 5
        )

        XCTAssertEqual(hints, ["Snoop Dogg", "Pharrell Williams"])
    }

    func testArtistHintsFallsBackToReleaseArtistsWhenTrackArtistsMissing() async throws {
        let client = makeClient()

        MockDiscogsURLProtocol.enqueueJSON { _ in
            (
                200,
                [
                    "results": [
                        ["id": 222]
                    ]
                ],
                [:]
            )
        }
        MockDiscogsURLProtocol.enqueueJSON { _ in
            (
                200,
                [
                    "artists": [
                        ["name": "Snoop Dogg"],
                        ["name": "Pharrell Williams"]
                    ],
                    "tracklist": [
                        [
                            "title": "Beautiful"
                        ]
                    ]
                ],
                [:]
            )
        }

        let hints = try await client.artistHintsForTrack(
            title: "Beautiful",
            artistHints: [],
            limit: 3
        )

        XCTAssertEqual(hints, ["Snoop Dogg", "Pharrell Williams"])
    }

    func testArtistHintsRanksArtistsByFrequencyAcrossReleases() async throws {
        let client = makeClient()

        MockDiscogsURLProtocol.enqueueJSON { _ in
            (
                200,
                [
                    "results": [
                        ["id": 301],
                        ["id": 302]
                    ]
                ],
                [:]
            )
        }
        MockDiscogsURLProtocol.enqueueJSON { _ in
            (
                200,
                [
                    "artists": [],
                    "tracklist": [
                        [
                            "title": "Beautiful",
                            "artists": [
                                ["name": "Snoop Dogg"],
                                ["name": "Pharrell Williams"]
                            ]
                        ]
                    ]
                ],
                [:]
            )
        }
        MockDiscogsURLProtocol.enqueueJSON { _ in
            (
                200,
                [
                    "artists": [],
                    "tracklist": [
                        [
                            "title": "Beautiful",
                            "artists": [
                                ["name": "Pharrell Williams"]
                            ]
                        ]
                    ]
                ],
                [:]
            )
        }

        let hints = try await client.artistHintsForTrack(
            title: "Beautiful",
            artistHints: [],
            limit: 2
        )

        XCTAssertEqual(hints, ["Pharrell Williams", "Snoop Dogg"])
    }

    func testArtistHintsThrowsUnauthorizedOn401() async throws {
        let client = makeClient()

        MockDiscogsURLProtocol.enqueueJSON { _ in
            (401, [:], [:])
        }

        do {
            _ = try await client.artistHintsForTrack(
                title: "Beautiful",
                artistHints: [],
                limit: 2
            )
            XCTFail("Expected unauthorized error")
        } catch let error as DiscogsClientError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testArtistHintsRetriesRateLimitThenSucceeds() async throws {
        let client = makeClient()

        MockDiscogsURLProtocol.enqueueJSON { _ in
            (429, [:], ["Retry-After": "0.01"])
        }
        MockDiscogsURLProtocol.enqueueJSON { _ in
            (
                200,
                [
                    "results": [
                        ["id": 401]
                    ]
                ],
                [:]
            )
        }
        MockDiscogsURLProtocol.enqueueJSON { _ in
            (
                200,
                [
                    "artists": [],
                    "tracklist": [
                        [
                            "title": "Beautiful",
                            "artists": [
                                ["name": "Pharrell Williams"]
                            ]
                        ]
                    ]
                ],
                [:]
            )
        }

        let hints = try await client.artistHintsForTrack(
            title: "Beautiful",
            artistHints: [],
            limit: 1
        )

        XCTAssertEqual(hints, ["Pharrell Williams"])
        XCTAssertEqual(MockDiscogsURLProtocol.recordedRequests().count, 3)
    }

    func testArtistHintsThrowsRateLimitedAfterRetryBudgetExhausted() async throws {
        let client = makeClient()

        MockDiscogsURLProtocol.enqueueJSON { _ in
            (429, [:], ["Retry-After": "0.01"])
        }
        MockDiscogsURLProtocol.enqueueJSON { _ in
            (429, [:], ["Retry-After": "0.01"])
        }
        MockDiscogsURLProtocol.enqueueJSON { _ in
            (429, [:], ["Retry-After": "0.01"])
        }

        do {
            _ = try await client.artistHintsForTrack(
                title: "Beautiful",
                artistHints: [],
                limit: 1
            )
            XCTFail("Expected rateLimited error")
        } catch let error as DiscogsClientError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    private func makeClient(
        token: String = "discogs-token",
        minIntervalSeconds: TimeInterval = 0
    ) -> DiscogsHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDiscogsURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return DiscogsHTTPClient(
            token: token,
            session: session,
            minIntervalSeconds: minIntervalSeconds
        )
    }
}

private final class MockDiscogsURLProtocol: URLProtocol {
    typealias ResponseFactory = (URLRequest) throws -> (Int, Any, [String: String])

    private static let lock = NSLock()
    private static var queued: [ResponseFactory] = []
    private static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let factory = Self.queued.isEmpty ? nil : Self.queued.removeFirst()
        Self.lock.unlock()

        guard let factory else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "MockDiscogsURLProtocol",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No queued response"]
                )
            )
            return
        }

        do {
            let (status, json, headers) = try factory(request)
            guard let url = request.url else {
                throw NSError(
                    domain: "MockDiscogsURLProtocol",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Missing request URL"]
                )
            }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func enqueueJSON(_ factory: @escaping ResponseFactory) {
        lock.lock()
        queued.append(factory)
        lock.unlock()
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func reset() {
        lock.lock()
        queued = []
        requests = []
        lock.unlock()
    }
}
