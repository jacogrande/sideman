import XCTest
@testable import SpoftyApp

final class WikipediaWikitextParserTests: XCTestCase {
    func testParseFiltersTrackSpecificCreditsWhenTrackDoesNotMatch() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 1,
            title: "Ants from Up There",
            fullURL: "https://en.wikipedia.org/wiki/Ants_from_Up_There",
            wikitext: sampleWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:one",
            title: "Chaos Space Marine",
            artist: "Black Country, New Road",
            album: "Ants from Up There"
        )

        let parsed = parser.parse(page: page, for: track)

        XCTAssertEqual(parsed.matchedTrackNumber, 1)
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Isaac Wood" }))
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Tony Fagg" }))
    }

    func testParseIncludesTrackSpecificCreditsWhenTrackMatches() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 1,
            title: "Ants from Up There",
            fullURL: "https://en.wikipedia.org/wiki/Ants_from_Up_There",
            wikitext: sampleWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:two",
            title: "Concorde",
            artist: "Black Country, New Road",
            album: "Ants from Up There"
        )

        let parsed = parser.parse(page: page, for: track)

        XCTAssertEqual(parsed.matchedTrackNumber, 2)
        let tonyEntries = parsed.entries.filter { $0.personName == "Tony Fagg" }
        XCTAssertEqual(tonyEntries.count, 1)
        XCTAssertEqual(tonyEntries.first?.scope, .trackSpecific([2]))
    }

    func testParseResolvesTrackNumberFromTemplateTrackListing() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 2,
            title: "Template Album",
            fullURL: "https://en.wikipedia.org/wiki/Template_Album",
            wikitext: templateTrackListingWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:template",
            title: "Concorde",
            artist: "Black Country, New Road",
            album: "Template Album"
        )

        let parsed = parser.parse(page: page, for: track)

        XCTAssertEqual(parsed.matchedTrackNumber, 2)
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Template Player" }))
    }
}

private let sampleWikitext = """
== Track listing ==
# "Chaos Space Marine"
# "Concorde"

== Personnel ==
* [[Isaac Wood]] – vocals, guitar
* [[Tony Fagg]] – banjo (track 2)
* Sergio Maschetzko – engineering, mixing
"""

private let templateTrackListingWikitext = """
== Track listing ==
{{Track listing
| title1 = Intro
| title2 = Concorde
| title3 = Outro
}}

== Personnel ==
* Template Player – bass (track 2)
"""
