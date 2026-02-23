import Foundation

enum CreditsBackend: String {
    case wikipedia
    case musicBrainz = "musicbrainz"
    case wikipediaThenMusicBrainz = "wikipedia_then_musicbrainz"

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> CreditsBackend {
        guard let raw = environment["SIDEMAN_CREDITS_BACKEND"]?.lowercased() else {
            return .wikipediaThenMusicBrainz
        }

        switch raw {
        case "wikipedia":
            return .wikipedia
        case "musicbrainz":
            return .musicBrainz
        case "wikipedia_then_musicbrainz", "hybrid", "merged":
            return .wikipediaThenMusicBrainz
        default:
            return .wikipediaThenMusicBrainz
        }
    }
}

enum CreditsProviderFactory {
    static func makePlaylistBuilder(spotifyClient: SpotifyWebAPI) -> PlaylistBuilder {
        let musicBrainzClient = MusicBrainzHTTPClient()
        let discogsClient = makeDiscogsClient()
        let discographyCache = DiscographyCache()
        let discographyService = ArtistDiscographyService(
            musicBrainzClient: musicBrainzClient,
            cache: discographyCache
        )
        let listenBrainzClient = ListenBrainzClient()
        let trackMatchingService = TrackMatchingService(
            musicBrainzClient: musicBrainzClient,
            spotifyClient: spotifyClient,
            discogsClient: discogsClient
        )
        return PlaylistBuilder(
            discographyService: discographyService,
            listenBrainzClient: listenBrainzClient,
            trackMatchingService: trackMatchingService,
            spotifyClient: spotifyClient
        )
    }

    private static func makeDiscogsClient(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DiscogsClient? {
        let token = (environment["SIDEMAN_DISCOGS_TOKEN"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            DebugLogger.log(.app, "Discogs integration disabled (SIDEMAN_DISCOGS_TOKEN not set)")
            return nil
        }

        DebugLogger.log(.app, "Discogs integration enabled")
        return DiscogsHTTPClient(token: token)
    }

    static func makeProvider(backend: CreditsBackend, cache: CreditsCache) -> CreditsProvider {
        let wikipediaClient = WikipediaAPIClientImpl()
        let wikipediaResolver = DefaultWikipediaPageResolver(client: wikipediaClient)
        let wikipediaProvider = WikipediaCreditsProvider(
            resolver: wikipediaResolver,
            client: wikipediaClient,
            cache: cache
        )

        let musicBrainzClient = MusicBrainzHTTPClient()
        let musicBrainzResolver = DefaultTrackResolver(client: musicBrainzClient)
        let musicBrainzProvider = DefaultCreditsProvider(
            resolver: musicBrainzResolver,
            client: musicBrainzClient,
            cache: cache
        )

        switch backend {
        case .wikipedia:
            return wikipediaProvider
        case .musicBrainz:
            return musicBrainzProvider
        case .wikipediaThenMusicBrainz:
            return MergedCreditsProvider(wikipedia: wikipediaProvider, musicBrainz: musicBrainzProvider)
        }
    }
}

actor MergedCreditsProvider: CreditsProvider {
    private let wikipedia: CreditsProvider
    private let musicBrainz: CreditsProvider

    init(wikipedia: CreditsProvider, musicBrainz: CreditsProvider) {
        self.wikipedia = wikipedia
        self.musicBrainz = musicBrainz
    }

    func lookupCredits(for track: NowPlayingTrack) async -> (CreditsLookupState, CreditsBundle?) {
        async let wikiResult = wikipedia.lookupCredits(for: track)
        async let mbResult = musicBrainz.lookupCredits(for: track)

        let (wikiState, wikiBundle) = await wikiResult
        let (mbState, mbBundle) = await mbResult

        let wikiLoaded = wikiState == .loaded && wikiBundle != nil
        let mbLoaded = mbState == .loaded && mbBundle != nil

        if wikiLoaded && mbLoaded {
            let merged = mergedBundle(wiki: wikiBundle!, mb: mbBundle!)
            DebugLogger.log(.provider, "merged provider: combined Wikipedia (\(wikiBundle!.entriesByGroup.values.flatMap { $0 }.count) entries) + MusicBrainz (\(mbBundle!.entriesByGroup.values.flatMap { $0 }.count) entries)")
            return (.loaded, merged)
        }

        if wikiLoaded {
            return (wikiState, wikiBundle)
        }

        if mbLoaded {
            return (mbState, mbBundle)
        }

        return (.notFound, nil)
    }

    func cacheLookupKey(for track: NowPlayingTrack) async -> String {
        await wikipedia.cacheLookupKey(for: track)
    }

    func invalidateCachedCredits(for track: NowPlayingTrack) async {
        await wikipedia.invalidateCachedCredits(for: track)
        await musicBrainz.invalidateCachedCredits(for: track)
    }

    private func mergedBundle(wiki: CreditsBundle, mb: CreditsBundle) -> CreditsBundle {
        let allWikiEntries = wiki.entriesByGroup.values.flatMap { $0 }
        let allMBEntries = mb.entriesByGroup.values.flatMap { $0 }
        let merged = CreditsMapper.mergeCrossSources(allWikiEntries + allMBEntries)
        let grouped = CreditsMapper.group(merged)

        let combinedProvenance = Array(Set(wiki.provenance + mb.provenance)).sorted { $0.sortRank < $1.sortRank }

        let wikiAttribution = wiki.sourceAttribution ?? "Wikipedia"
        let mbAttribution = mb.sourceAttribution ?? "MusicBrainz"

        return CreditsBundle(
            entriesByGroup: grouped,
            provenance: combinedProvenance,
            resolvedRecordingMBID: mb.resolvedRecordingMBID,
            sourceID: wiki.sourceID ?? mb.sourceID,
            sourceName: "Wikipedia + MusicBrainz",
            sourcePageTitle: wiki.sourcePageTitle,
            sourcePageURL: wiki.sourcePageURL,
            sourceAttribution: "\(wikiAttribution) + \(mbAttribution)",
            matchedTrackNumber: wiki.matchedTrackNumber
        )
    }
}
