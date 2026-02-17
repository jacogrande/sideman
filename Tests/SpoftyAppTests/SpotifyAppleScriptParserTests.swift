import XCTest
@testable import SpoftyApp

final class SpotifyAppleScriptParserTests: XCTestCase {
    func testParsePlayingPayload() {
        let raw = "PLAYING||spotify:track:abc123||Song Title||Song Artist||Song Album"

        let snapshot = SpotifyAppleScriptParser.parse(raw)

        XCTAssertEqual(snapshot.state, .playing)
        XCTAssertEqual(snapshot.track?.id, "spotify:track:abc123")
        XCTAssertEqual(snapshot.track?.title, "Song Title")
        XCTAssertEqual(snapshot.track?.artist, "Song Artist")
        XCTAssertEqual(snapshot.track?.album, "Song Album")
        XCTAssertNil(snapshot.errorMessage)
    }

    func testParsePausedPayload() {
        let snapshot = SpotifyAppleScriptParser.parse("PAUSED")

        XCTAssertEqual(snapshot.state, .paused)
        XCTAssertNil(snapshot.track)
    }

    func testParseNotRunningPayload() {
        let snapshot = SpotifyAppleScriptParser.parse("NOT_RUNNING")

        XCTAssertEqual(snapshot.state, .notRunning)
        XCTAssertNil(snapshot.track)
    }

    func testParseMalformedPlayingPayload() {
        let snapshot = SpotifyAppleScriptParser.parse("PLAYING||missing-fields")

        XCTAssertEqual(snapshot.state, .unknown)
        XCTAssertEqual(snapshot.errorMessage, "Malformed PLAYING payload")
    }

    func testParseUnexpectedPayload() {
        let snapshot = SpotifyAppleScriptParser.parse("WUT")

        XCTAssertEqual(snapshot.state, .unknown)
        XCTAssertEqual(snapshot.errorMessage, "Unexpected AppleScript output")
    }
}
