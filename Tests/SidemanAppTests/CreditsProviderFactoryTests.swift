import XCTest
@testable import SidemanApp

final class CreditsProviderFactoryTests: XCTestCase {
    func testBackendSelectionDefaultsToWikipediaThenMusicBrainz() {
        XCTAssertEqual(CreditsBackend.fromEnvironment([:]), .wikipediaThenMusicBrainz)
        XCTAssertEqual(CreditsBackend.fromEnvironment(["SIDEMAN_CREDITS_BACKEND": "invalid"]), .wikipediaThenMusicBrainz)
    }

    func testBackendSelectionSupportsMusicBrainzAndHybrid() {
        XCTAssertEqual(CreditsBackend.fromEnvironment(["SIDEMAN_CREDITS_BACKEND": "musicbrainz"]), .musicBrainz)
        XCTAssertEqual(CreditsBackend.fromEnvironment(["SIDEMAN_CREDITS_BACKEND": "wikipedia_then_musicbrainz"]), .wikipediaThenMusicBrainz)
        XCTAssertEqual(CreditsBackend.fromEnvironment(["SIDEMAN_CREDITS_BACKEND": "hybrid"]), .wikipediaThenMusicBrainz)
    }
}
