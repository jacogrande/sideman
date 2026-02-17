import XCTest
@testable import SpoftyApp

final class CreditsProviderFactoryTests: XCTestCase {
    func testBackendSelectionDefaultsToWikipedia() {
        XCTAssertEqual(CreditsBackend.fromEnvironment([:]), .wikipedia)
        XCTAssertEqual(CreditsBackend.fromEnvironment(["SPOFTY_CREDITS_BACKEND": "invalid"]), .wikipedia)
    }

    func testBackendSelectionSupportsMusicBrainzAndHybrid() {
        XCTAssertEqual(CreditsBackend.fromEnvironment(["SPOFTY_CREDITS_BACKEND": "musicbrainz"]), .musicBrainz)
        XCTAssertEqual(CreditsBackend.fromEnvironment(["SPOFTY_CREDITS_BACKEND": "wikipedia_then_musicbrainz"]), .wikipediaThenMusicBrainz)
        XCTAssertEqual(CreditsBackend.fromEnvironment(["SPOFTY_CREDITS_BACKEND": "hybrid"]), .wikipediaThenMusicBrainz)
    }
}
