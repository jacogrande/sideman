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

    func testParseFindsPersonnelWhenSectionUsesNestedSubheadings() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 3,
            title: "Ants from Up There",
            fullURL: "https://en.wikipedia.org/wiki/Ants_from_Up_There",
            wikitext: nestedPersonnelWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:nested",
            title: "Concorde",
            artist: "Black Country, New Road",
            album: "Ants from Up There"
        )

        let parsed = parser.parse(page: page, for: track)

        XCTAssertEqual(parsed.matchedTrackNumber, 2)
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Charlie Wayne" }))
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Tony Fagg" }))
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Mark Paton" }))
    }

    func testParseUsesSpotifyTrackNumberWhenAvailable() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 4,
            title: "Ants from Up There",
            fullURL: "https://en.wikipedia.org/wiki/Ants_from_Up_There",
            wikitext: nestedPersonnelWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:direct-track-number",
            title: "Unknown Title",
            artist: "Black Country, New Road",
            album: "Ants from Up There",
            trackNumber: 2
        )

        let parsed = parser.parse(page: page, for: track)

        XCTAssertEqual(parsed.matchedTrackNumber, 2)
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Tony Fagg" }))
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Mark Paton" }))
    }
    func testParseHandlesNameOnlyLinesWithNumericTrackScopes() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 5,
            title: "Test Album",
            fullURL: "https://en.wikipedia.org/wiki/Test_Album",
            wikitext: nameOnlyPersonnelWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:name-only",
            title: "First Song",
            artist: "Test Band",
            album: "Test Album",
            trackNumber: 1
        )

        let parsed = parser.parse(page: page, for: track)

        // Name-only with numeric scope: track 1 matches
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Michael D'Addario" }))
        let michael = parsed.entries.filter { $0.personName == "Michael D'Addario" }
        XCTAssertEqual(michael.first?.roleRaw, "performer")
        XCTAssertEqual(michael.first?.scope, .trackSpecific([1, 3, 7]))

        // Range scope: tracks 1–4 includes track 1
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Richard Dodd" }))

        // Track 4 and 8 — does NOT include track 1
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Kenny Gilmore" }))

        // Delimiter line with numeric scope: arranger (1 and 10) includes track 1
        let brian = parsed.entries.filter { $0.personName == "Brian D'Addario" }
        XCTAssertEqual(brian.count, 1)
        XCTAssertEqual(brian.first?.roleRaw, "arranger")
        XCTAssertEqual(brian.first?.scope, .trackSpecific([1, 10]))
    }

    func testParseHandlesPerRoleNumericScopes() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 6,
            title: "Dragon New Warm Mountain I Believe in You",
            fullURL: "https://en.wikipedia.org/wiki/Dragon_New_Warm_Mountain",
            wikitext: perRoleScopeWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:per-role",
            title: "Certainty",
            artist: "Big Thief",
            album: "Dragon New Warm Mountain I Believe in You",
            trackNumber: 1
        )

        let parsed = parser.parse(page: page, for: track)

        // Adrianne has "vocals (all tracks)" → album-wide, so matches track 1
        let adrianneVocals = parsed.entries.filter { $0.personName == "Adrianne Lenker" && $0.roleRaw == "vocals" }
        XCTAssertEqual(adrianneVocals.count, 1)
        XCTAssertEqual(adrianneVocals.first?.scope, .albumWide)

        // Adrianne has "acoustic guitar (1, 3–7)" → includes track 1
        let adrianneAcoustic = parsed.entries.filter { $0.personName == "Adrianne Lenker" && $0.roleRaw == "acoustic guitar" }
        XCTAssertEqual(adrianneAcoustic.count, 1)
        XCTAssertTrue(adrianneAcoustic.first?.scope.applies(to: 1) == true)

        // Adrianne has "nylon guitar (8)" → does NOT include track 1
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Adrianne Lenker" && $0.roleRaw == "nylon guitar" }))

        // Hannah Cohen has "vocals (4)" → does NOT include track 1
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Hannah Cohen" }))

        // Shawn Everett: "engineering" inherits group scope from "additional production (2, 7, 10)"
        // Neither applies to track 1
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Shawn Everett" && $0.roleRaw == "engineering" }))
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Shawn Everett" && $0.roleRaw == "additional production" }))

        // Amy Dragon has no scope → album-wide, matches track 1
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Amy Dragon" }))

        // Mat Davidson: "pedal steel" inherits group scope from "recorder (5)" — does NOT apply to track 1
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Mat Davidson" && $0.roleRaw == "pedal steel" }))
        // Mat Davidson: "vocals (3, 5)" includes track 3 but NOT track 1
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Mat Davidson" && $0.roleRaw == "vocals" }))
    }

    func testParseGroupScopeInheritanceForSemicolonGroups() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 7,
            title: "Dragon New Warm Mountain I Believe in You",
            fullURL: "https://en.wikipedia.org/wiki/Dragon_New_Warm_Mountain",
            wikitext: perRoleScopeWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:group-scope",
            title: "Spud Infinity",
            artist: "Big Thief",
            album: "Dragon New Warm Mountain I Believe in You",
            trackNumber: 3
        )

        let parsed = parser.parse(page: page, for: track)

        // Mat Davidson: "vocals (3, 5)" → includes track 3
        let matVocals = parsed.entries.filter { $0.personName == "Mat Davidson" && $0.roleRaw == "vocals" }
        XCTAssertEqual(matVocals.count, 1)
        XCTAssertTrue(matVocals.first?.scope.applies(to: 3) == true)

        // Mat Davidson: "fiddle (3, 5)" → includes track 3
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Mat Davidson" && $0.roleRaw == "fiddle" }))

        // Mat Davidson: "pedal steel" inherits from "recorder (5)" → does NOT include track 3
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Mat Davidson" && $0.roleRaw == "pedal steel" }))

        // Mat Davidson: "accordion (14)" → does NOT include track 3
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Mat Davidson" && $0.roleRaw == "accordion" }))
    }
}

private let nameOnlyPersonnelWikitext = """
== Track listing ==
# "First Song"
# "Second Song"
# "Third Song"
# "Fourth Song"
# "Fifth Song"
# "Sixth Song"
# "Seventh Song"
# "Eighth Song"
# "Ninth Song"
# "Tenth Song"

== Personnel ==
* Michael D'Addario (1, 3, 7)
* Richard Dodd (1–4, 6–10)
* Kenny Gilmore (4, and 8)
* Brian D'Addario – arranger (1 and 10)
"""

private let perRoleScopeWikitext = """
== Track listing ==
# "Certainty"
# "Time Escaping"
# "Spud Infinity"
# "Little Things"
# "Sparrow"
# "Heavy Bend"
# "Flower of Blood"
# "Blurred View"

== Personnel ==
* [[Adrianne Lenker]] – vocals (all tracks), acoustic guitar (1, 3–7), nylon guitar (8), electric guitar (9, 10)
* [[Buck Meek]] – electric guitar (1, 3, 6, 7), vocals (1, 4)
* [[James Krivchenia]] – production (all tracks), drums (1–4, 6–8), vocals (1, 6)
* Hannah Cohen – vocals (4)
* Shawn Everett – engineering, additional production (2, 7, 10); mixing (2, 7, 10)
* Mat Davidson – vocals (3, 5), fiddle (3, 5); pedal steel, recorder (5); accordion (14)
* Amy Dragon – vinyl mastering
"""

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

private let nestedPersonnelWikitext = """
== Track listing ==
{{Track listing
| title1 = Intro
| title2 = Concorde
| title3 = Bread Song
}}

== Personnel ==
Adapted from vinyl liner notes.

=== Black Country, New Road ===
* Charlie Wayne – drums, backing vocals
* Isaac Wood – vocals, guitar

=== Additional personnel ===
* Tony Fagg – banjo (track 2)
* Mark Paton – vocals (track 7)

== Charts ==
* placeholder
"""
