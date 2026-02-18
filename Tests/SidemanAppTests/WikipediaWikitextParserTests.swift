import XCTest
@testable import SidemanApp

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

    func testParseHandlesWikitablePersonnelFormat() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 10,
            title: "Brown Sugar (D'Angelo album)",
            fullURL: "https://en.wikipedia.org/wiki/Brown_Sugar_(D%27Angelo_album)",
            wikitext: wikitablePersonnelWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:wikitable",
            title: "Brown Sugar",
            artist: "D'Angelo",
            album: "Brown Sugar",
            trackNumber: 1
        )

        let parsed = parser.parse(page: page, for: track)

        // Track 1: "Guitar by Bob Power" → name=Bob Power, role=Guitar
        let bobGuitar = parsed.entries.first(where: { $0.personName == "Bob Power" && $0.roleRaw == "Guitar" })
        XCTAssertNotNil(bobGuitar)
        XCTAssertEqual(bobGuitar?.scope, .trackSpecific([1]))

        // Track 1: "Drums by Questlove" → name=Questlove, role=Drums
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Questlove" && $0.roleRaw == "Drums" }))

        // Track 2: "Bass: Pino Palladino" → track 2 only, should NOT appear for track 1
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Pino Palladino" }))

        // Album-wide header row: "Mixed by Bob Power" → scope=albumWide, matches all tracks
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Bob Power" && $0.roleRaw == "Mixed" }))
        let mixedBob = parsed.entries.first(where: { $0.personName == "Bob Power" && $0.roleRaw == "Mixed" })
        XCTAssertEqual(mixedBob?.scope, .albumWide)

        // Comma-separated names: "Violins: Gerald Tarack, Marilyn Wright" in track 1
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Gerald Tarack" && $0.roleRaw == "Violins" }))
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Marilyn Wright" && $0.roleRaw == "Violins" }))

        // Business credits should be filtered: "A&R: Michael Harris"
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Michael Harris" }))

        // "Photography: Carol Friedman" should be filtered
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Carol Friedman" }))

        // Engineering credits should be kept: "Recorded by Russell Elevado"
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Russell Elevado" && $0.roleRaw == "Recorded" }))

        // "Assistant engineer: G-Spot" should be kept
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "G-Spot" && $0.roleRaw == "Assistant engineer" }))

        // Role groups: Guitar → musicians, Mixed → engineering
        XCTAssertEqual(bobGuitar?.roleGroup, .musicians)
        XCTAssertEqual(mixedBob?.roleGroup, .engineering)
    }

    func testParseWikitableTrack2CreditsAppearWhenRequested() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 10,
            title: "Brown Sugar (D'Angelo album)",
            fullURL: "https://en.wikipedia.org/wiki/Brown_Sugar_(D%27Angelo_album)",
            wikitext: wikitablePersonnelWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:wikitable-t2",
            title: "Alright",
            artist: "D'Angelo",
            album: "Brown Sugar",
            trackNumber: 2
        )

        let parsed = parser.parse(page: page, for: track)

        // Track 2: "Bass: Pino Palladino" should appear
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Pino Palladino" && $0.roleRaw == "Bass" }))
        let pino = parsed.entries.first(where: { $0.personName == "Pino Palladino" })
        XCTAssertEqual(pino?.scope, .trackSpecific([2]))

        // "Keyboards by Charlie Hunter and D'Angelo" → two entries
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Charlie Hunter" && $0.roleRaw == "Keyboards" }))
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "D'Angelo" && $0.roleRaw == "Keyboards" }))

        // Track 1 credits should NOT appear
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Questlove" }))

        // Album-wide "Mixed by Bob Power" should still appear
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Bob Power" && $0.roleRaw == "Mixed" }))
    }

    func testParseWikitableMultiLineCellFormat() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 11,
            title: "Multi-Line Table Album",
            fullURL: "https://en.wikipedia.org/wiki/Multi_Line_Table",
            wikitext: wikitableMultiLineCellWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:multiline-table",
            title: "First Song",
            artist: "Test Artist",
            album: "Multi-Line Table Album",
            trackNumber: 1
        )

        let parsed = parser.parse(page: page, for: track)

        // Track 1 credits from newline-delimited cell format
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Jane Doe" && $0.roleRaw == "Guitar" }))
        let jane = parsed.entries.first(where: { $0.personName == "Jane Doe" })
        XCTAssertEqual(jane?.scope, .trackSpecific([1]))

        // Track 2 should NOT appear for track 1
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "John Smith" }))
    }

    func testParseWikitableOxfordCommaNames() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 12,
            title: "Oxford Comma Album",
            fullURL: "https://en.wikipedia.org/wiki/Oxford_Comma_Album",
            wikitext: wikitableOxfordCommaWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:oxford",
            title: "Track One",
            artist: "Test Artist",
            album: "Oxford Comma Album",
            trackNumber: 1
        )

        let parsed = parser.parse(page: page, for: track)

        // "Strings: Alice, Bob, and Charlie" → three separate entries
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Alice" && $0.roleRaw == "Strings" }))
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Bob" && $0.roleRaw == "Strings" }))
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Charlie" && $0.roleRaw == "Strings" }))
    }

    func testParseWikitableRealisticBrownSugarCredits() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 13,
            title: "Brown Sugar (D'Angelo album)",
            fullURL: "https://en.wikipedia.org/wiki/Brown_Sugar_(D%27Angelo_album)",
            wikitext: wikitableRealisticBrownSugarWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:brown-sugar-realistic",
            title: "Brown Sugar",
            artist: "D'Angelo",
            album: "Brown Sugar",
            trackNumber: 1
        )

        let parsed = parser.parse(page: page, for: track)

        // D'Angelo should have writing, production, and musician credits
        let dangelo = parsed.entries.filter { $0.personName == "D'Angelo" }
        XCTAssertTrue(dangelo.contains(where: { $0.roleRaw == "Written" && $0.roleGroup == .writing }))
        XCTAssertTrue(dangelo.contains(where: { $0.roleRaw == "Produced" && $0.roleGroup == .production }))
        XCTAssertTrue(dangelo.contains(where: { $0.roleRaw == "Vocal arrangements" && $0.roleGroup == .writing }))
        XCTAssertTrue(dangelo.contains(where: { $0.roleRaw == "Musical arrangements" && $0.roleGroup == .writing }))
        XCTAssertTrue(dangelo.contains(where: { $0.roleRaw == "All vocals" && $0.roleGroup == .musicians }))
        XCTAssertTrue(dangelo.contains(where: { $0.roleRaw == "All instruments" && $0.roleGroup == .musicians }))

        // Ali Shaheed Muhammad should have producer + drum programming
        // (The "Written by" line uses a different spelling — "Muhammed" — which is a real
        // Wikipedia inconsistency, so it produces a separate entry under that variant name.)
        let ali = parsed.entries.filter { $0.personName == "Ali Shaheed Muhammad" }
        XCTAssertTrue(ali.contains(where: { $0.roleRaw == "Produced" }))
        XCTAssertTrue(ali.contains(where: { $0.roleRaw == "Drum programming" }))
        // The "Written by" credit uses the "Muhammed" spelling
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Ali Shaheed Muhammed" && $0.roleRaw == "Written" }))

        // "Mixed by Bob Power at Battery Studios, NYC" → name=Bob Power (location stripped)
        let bobMixed = parsed.entries.first(where: { $0.personName == "Bob Power" && $0.roleRaw == "Mixed" })
        XCTAssertNotNil(bobMixed)
        XCTAssertEqual(bobMixed?.roleGroup, .engineering)

        // "Additional engineering by Tim Latham at Soundtrack, NYC" → name=Tim Latham
        let tim = parsed.entries.first(where: { $0.personName == "Tim Latham" })
        XCTAssertNotNil(tim)
        XCTAssertEqual(tim?.roleRaw, "Additional engineering")
        XCTAssertEqual(tim?.roleGroup, .engineering)

        // "Recorded at Battery Studios, NYC" → location-only line, no person → skipped
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Battery Studios" }))
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "NYC" }))

        // "Assistant engineer: G-Spot" → colon format works
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "G-Spot" && $0.roleRaw == "Assistant engineer" }))

        // Album-wide credits: "Mastered by Herb Powers Jr." should appear (location stripped)
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Herb Powers Jr." && $0.roleRaw == "Mastered" }))
        // "Additional assistant engineers: Suz Dweyer, Julio Peralta, Martin Czember"
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Julio Peralta" && $0.scope == .albumWide }))

        // Non-musical album-wide credits should be filtered
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Henry Marquez" }))
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Per Gustafson" }))

        // All track 1 D'Angelo entries should be track-scoped
        XCTAssertTrue(dangelo.allSatisfy { $0.scope == .trackSpecific([1]) })
    }

    func testParseSurvivesSelfClosingRefBeforePersonnelSection() {
        // Self-closing <ref name="X"/> before the Personnel section should not
        // cause the sanitizer to eat the heading. Regression test for a bug where
        // the paired-ref regex matched self-closing refs as opening tags.
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 8,
            title: "Continuum",
            fullURL: "https://en.wikipedia.org/wiki/Continuum_(John_Mayer_album)",
            wikitext: selfClosingRefWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:self-closing-ref",
            title: "Slow Dancing in a Burning Room",
            artist: "John Mayer",
            album: "Continuum",
            trackNumber: 7
        )

        let parsed = parser.parse(page: page, for: track)

        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "John Mayer" }))
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "James Valentine" }))
        // Pino's bass is "all tracks", should match track 7
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Pino Palladino" }))
        // James Valentine's inline "on tracks 7 and 11" should be parsed as a scope
        let jv = parsed.entries.filter { $0.personName == "James Valentine" }
        XCTAssertEqual(jv.count, 1)
        XCTAssertEqual(jv.first?.roleRaw, "guitar")
        XCTAssertTrue(jv.first?.scope.applies(to: 7) == true)
    }

    func testParseHandlesInlineTrackScopes() {
        // Wikipedia personnel entries that use "on track(s) N" instead of "(tracks N)".
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 9,
            title: "Continuum (John Mayer album)",
            fullURL: "https://en.wikipedia.org/wiki/Continuum_(John_Mayer_album)",
            wikitext: inlineTrackScopeWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:inline-scope",
            title: "Slow Dancing in a Burning Room",
            artist: "John Mayer",
            album: "Continuum",
            trackNumber: 8
        )

        let parsed = parser.parse(page: page, for: track)

        // John Mayer has "all tracks" → album-wide, matches track 8
        let jm = parsed.entries.filter { $0.personName == "John Mayer" }
        XCTAssertTrue(jm.contains(where: { $0.roleRaw == "vocals" }))

        // Steve Jordan: "drums on all tracks except 5" → trackUnknown, matches all
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Steve Jordan" && $0.roleRaw == "drums" }))

        // Steve Jordan: "percussion on tracks 1, 2, 5, 8, and 10" → includes track 8
        let sjPerc = parsed.entries.filter { $0.personName == "Steve Jordan" && $0.roleRaw == "percussion" }
        XCTAssertEqual(sjPerc.count, 1)
        XCTAssertTrue(sjPerc.first?.scope.applies(to: 8) == true)

        // Steve Jordan: "backing vocals on track 1" → does NOT include track 8
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Steve Jordan" && $0.roleRaw == "backing vocals" }))

        // Roy Hargrove: "horns on tracks 1 and 2" → does NOT include track 8
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Roy Hargrove" }))

        // James Valentine: "guitar on tracks 7 and 11" → does NOT include track 8
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "James Valentine" }))

        // Pino: "bass guitar (all tracks)" → parenthetical, matches track 8
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Pino Palladino" }))

        // Manny Marroquin: "mixing on tracks 1, 2, 4, 8 and 12" → includes track 8
        let mm = parsed.entries.filter { $0.personName == "Manny Marroquin" }
        XCTAssertEqual(mm.count, 1)
        XCTAssertTrue(mm.first?.scope.applies(to: 8) == true)

        // Michael Brauer: "mixing on tracks 3, 5, 6, 7, 9, 10 and 11" → does NOT include track 8
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Michael Brauer" }))
    }

    func testParseBulletListWithDivColAndRefTags() {
        let parser = DefaultWikipediaWikitextParser()
        let page = WikipediaPageContent(
            pageID: 45600219,
            title: "To Pimp a Butterfly",
            fullURL: "https://en.wikipedia.org/wiki/To_Pimp_a_Butterfly",
            wikitext: tpabWikitext
        )
        let track = NowPlayingTrack(
            id: "spotify:track:momma",
            title: "Momma",
            artist: "Kendrick Lamar",
            album: "To Pimp a Butterfly",
            trackNumber: 9
        )

        let parsed = parser.parse(page: page, for: track)

        XCTAssertEqual(parsed.matchedTrackNumber, 9)
        XCTAssertFalse(parsed.entries.isEmpty, "Should parse entries from {{Div col}} bullet-list format")

        // Kendrick Lamar has album-wide "vocals" → applies to track 9
        let kendrick = parsed.entries.filter { $0.personName == "Kendrick Lamar" }
        XCTAssertTrue(kendrick.contains(where: { $0.roleRaw == "vocals" }))

        // Terrace Martin: alto saxophone (tracks 1, 2, 6–9, ...) → includes track 9
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Terrace Martin" && $0.roleRaw == "alto saxophone" }))
        // Terrace Martin: keyboards (tracks 5, 6, 8–12) → includes track 9
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Terrace Martin" && $0.roleRaw == "keyboards" }))
        // Terrace Martin: vocoder (tracks 9, 14) → includes track 9
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Terrace Martin" && $0.roleRaw == "vocoder" }))

        // Knxwledge: producer (track 9) → includes track 9
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Knxwledge" && $0.roleRaw == "producer" }))

        // Bilal: backing vocals (6, 8–10) → includes track 9
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Bilal" && $0.roleRaw == "backing vocals" }))

        // Lalah Hathaway: background vocals (tracks 9, 12, 13) → includes track 9
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Lalah Hathaway" && $0.roleRaw == "background vocals" }))

        // Taz Arnold aka Tisa: background vocals (tracks 4, 8, 9, 15) → includes track 9
        XCTAssertTrue(parsed.entries.contains(where: { $0.personName == "Taz Arnold aka Tisa" }))

        // George Clinton: vocals (track 1) → does NOT apply to track 9
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "George Clinton" }))

        // Flying Lotus: producer (track 1) → does NOT apply to track 9
        XCTAssertFalse(parsed.entries.contains(where: { $0.personName == "Flying Lotus" }))
    }
}

private let selfClosingRefWikitext = """
Some intro text.<ref name="Qmag"/>

More text with a proper ref.<ref name="Rolling">Rolling Stone review</ref>

== Track listing ==
# "Waiting on the World to Change"
# "I Don't Trust Myself (With Loving You)"
# "Belief"
# "Gravity"
# "The Heart of Life"
# "Vultures"
# "Slow Dancing in a Burning Room"

== Personnel ==

=== Musicians ===
*John Mayer – vocals, guitars (all tracks); production
*Pino Palladino – bass guitar (all tracks)
*James Valentine – guitar on tracks 7 and 11

== Charts ==
* placeholder
"""

private let inlineTrackScopeWikitext = """
== Track listing ==
# "Waiting on the World to Change"
# "I Don't Trust Myself (With Loving You)"
# "Belief"
# "Gravity"
# "The Heart of Life"
# "Vultures"
# "Stop This Train"
# "Slow Dancing in a Burning Room"
# "Bold as Love"
# "Dreaming with a Broken Heart"
# "In Repair"
# "I'm Gonna Find Another You"

== Personnel ==

=== Musicians ===
*John Mayer – vocals, guitars (all tracks); production
*Pino Palladino – bass guitar (all tracks); backing vocals on track 1
*Steve Jordan – drums on all tracks except 5; percussion on tracks 1, 2, 5, 8, and 10; backing vocals on track 1; production
*Roy Hargrove – horns on tracks 1 and 2
*James Valentine – guitar on tracks 7 and 11
*Jamie Muhoberac – keyboards on tracks 7 and 11

=== Production ===
*Manny Marroquin – mixing on tracks 1, 2, 4, 8 and 12
*Michael Brauer – mixing on tracks 3, 5, 6, 7, 9, 10 and 11

== Charts ==
* placeholder
"""

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

private let wikitablePersonnelWikitext = """
== Track listing ==
# "Brown Sugar"
# "Alright"

== Personnel ==
{| class="wikitable"
|-
! Track !! Title !! Notes
|-
|  || || <small>Mixed by [[Bob Power]]<br />Recorded by Russell Elevado<br />A&R: Michael Harris<br />Photography: Carol Friedman<br />Assistant engineer: G-Spot</small>
|-
| 1 || "Brown Sugar" || <small>Guitar by [[Bob Power]]<br />Drums by [[Questlove]]<br />Violins: Gerald Tarack, Marilyn Wright</small>
|-
| 2 || "Alright" || <small>Bass: Pino Palladino<br />Keyboards by Charlie Hunter and D'Angelo</small>
|}

== Charts ==
* placeholder
"""

private let wikitableRealisticBrownSugarWikitext = """
== Track listing ==
# "Brown Sugar"
# "Alright"

== Personnel ==
Credits are adapted from the album's liner notes.

{| class="wikitable"
|-
!#
!Title
!Notes
|-
|
|''Brown Sugar''
|
<small>Executive producer: Kedar Massenburg for Kedar Entertainment, Inc. <br />A&R direction: Gary Harris and Kedar Massenburg <br />Management: Kedar Entertainment, Inc. <br />Art direction: Henry Marquez <br />Photography: Per Gustafson <br />Mastered by Herb Powers Jr. at Hit Factory Mastering, NYC <br />Additional assistant engineers: Suz Dweyer, Julio Peralta, Martin Czember</small>
|-
|1
|"Brown Sugar"
|
<small>Written by [[D'Angelo]] and Ali Shaheed Muhammed <br />Produced by [[D'Angelo]] and Ali Shaheed Muhammad <br />Vocal arrangements by [[D'Angelo]] <br />All vocals by [[D'Angelo]] <br />Musical arrangements by [[D'Angelo]] <br />All instruments by [[D'Angelo]] <br />Drum programming by Ali Shaheed Muhammad <br />Recorded at Battery Studios, NYC <br />Additional engineering by Tim Latham at Soundtrack, NYC <br />Mixed by [[Bob Power]] at Battery Studios, NYC <br />Assistant engineer: G-Spot</small>
|-
|2
|"Alright"
|
<small>Written by [[D'Angelo]] <br />Produced by [[D'Angelo]]</small>
|}

== Charts ==
* placeholder
"""

private let wikitableMultiLineCellWikitext = """
== Track listing ==
# "First Song"
# "Second Song"

== Personnel ==
{| class="wikitable"
|-
! No.
! Title
! Notes
|-
| 1
| "First Song"
| <small>Guitar by Jane Doe<br />Drums by Mike Lee</small>
|-
| 2
| "Second Song"
| <small>Bass by John Smith</small>
|}

== Charts ==
* placeholder
"""

private let wikitableOxfordCommaWikitext = """
== Track listing ==
# "Track One"

== Personnel ==
{| class="wikitable"
|-
! Track !! Title !! Notes
|-
| 1 || "Track One" || <small>Strings: Alice, Bob, and Charlie</small>
|}

== Charts ==
* placeholder
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

private let tpabWikitext = """
== Track listing ==
{{Track listing
| headline      = ''To Pimp a Butterfly'' track listing
| extra_column  = Producer(s)
| total_length  = 78:51

| title1        = Wesley's Theory
| note1         = featuring [[George Clinton (funk musician)|George Clinton]] and [[Thundercat (musician)|Thundercat]]
| length1       = 4:47

| title2        = [[For Free? (Interlude)]]
| length2       = 2:10

| title3        = [[King Kunta]]
| length3       = 3:54

| title4        = Institutionalized
| length4       = 4:31

| title5        = [[These Walls (Kendrick Lamar song)|These Walls]]
| length5       = 5:00

| title6        = U
| length6       = 4:28

| title7        = [[Alright (Kendrick Lamar song)|Alright]]
| length7       = 3:39

| title8        = For Sale? (Interlude)
| length8       = 4:51

| title9        = Momma
| length9       = 4:43

| title10       = Hood Politics
| length10      = 4:52

| title11       = [[How Much a Dollar Cost]]
| length11      = 4:21

| title12       = Complexion (A Zulu Love)
| length12      = 4:23

| title13       = [[The Blacker the Berry (song)|The Blacker the Berry]]
| length13      = 5:28

| title14       = You Ain't Gotta Lie (Momma Said)
| length14      = 4:01

| title15       = [[i (Kendrick Lamar song)|i]]
| length15      = 5:36

| title16       = Mortal Man
| length16      = 12:07
}}

===Sample credits===
* placeholder

==Personnel==
Credits for ''To Pimp a Butterfly'' adapted from [[AllMusic]] and the album's digital booklet.<ref name="booklet">{{cite AV media notes |title=To Pimp a Butterfly}}</ref><ref name="albumnotes">{{cite AV media notes|title=Digital Booklet}}</ref>

{{Div col}}
* Kendrick Lamar – vocals; art direction
* [[George Clinton (funk musician)|George Clinton]] – vocals (track 1)
* [[Thundercat (musician)|Thundercat]] – vocals (tracks 1, 5); background vocals (tracks 7, 12, 14); bass (tracks 1, 3, 13, 15, 16); additional bass (track 5); producer (tracks 10, 12); additional production (track 1)
* [[Anna Wise]] – vocals (tracks 4, 5); backing vocals (tracks 1, 2, 10)
* [[Bilal (American singer)|Bilal]] – vocals (tracks 4, 5); backing vocals (6, 8\u{2013}10)
* [[Snoop Dogg]] – vocals (track 4)
* [[James Fauntleroy]] – vocals (track 11); background vocals (track 16)
* [[Ronald Isley]] – vocals (track 11); additional vocals (track 15)
* [[Rapsody]] – vocals (track 12)
* [[Flying Lotus]] – producer (track 1)
* Ronald "Flippa" Colson – producer (track 1)
* [[Sounwave]] – producer (tracks 3, 7, 10, 12, 16); additional production (tracks 1, 5, 6, 8, 10); keyboards (track 14); string arrangements
* [[Terrace Martin]] – alto saxophone (tracks 1, 2, 6\u{2013}9, 11, 13, 14, 16); horns (track 1); keyboards (tracks 5, 6, 8\u{2013}12); producer (tracks 2, 5); additional production (tracks 3, 8, 12, 13); vocoder (tracks 9, 14); string arrangements
* [[Rahki]] – producer (tracks 4, 15); percussion (track 15)
* [[Sa-Ra|Taz Arnold]] aka Tisa – background vocals (tracks 4, 8, 9, 15); producer (tracks 6, 8)
* [[Pharrell Williams]] – producer, vocals (track 7)
* [[Knxwledge]] – producer (track 9)
* [[Tae Beast]] – producer (track 10)
* [[Dr. Dre]] – executive producer; background vocals (track 1, 10)
* James Hunt – engineer (tracks 1\u{2013}7, 13\u{2013}16); mix assistant
* [[Derek Ali|Derek "MixedByAli" Ali]] – engineer (tracks 1\u{2013}6, 8\u{2013}16), mixer
* [[Mike Bozzi]] – mastering engineer
* [[Ash Riser]] – background vocals (track 1)
* [[Josef Leimberg]] – trumpet (tracks 1, 5, 8, 11, 12, 14, 16), vocals (track 1)
* Whitney Alford – background vocals (tracks 1, 3)
* [[Robert Glasper]] – piano (track 2); keyboards (tracks 5, 12, 13, 16)
* [[Kamasi Washington]] – tenor saxophone (track 6); string arrangements
* [[SZA (singer)|SZA]] – background vocals (tracks 6, 8)
* [[Lalah Hathaway]] – background vocals (tracks 9, 12, 13)
* [[Pete Rock]] – background vocals/scratches (track 12)
* [[Ambrose Akinmusire]] – trumpet (track 16)
{{div col end}}

==Charts==
* placeholder
"""
