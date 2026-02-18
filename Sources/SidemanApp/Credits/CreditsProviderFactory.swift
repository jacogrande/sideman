import Foundation

enum CreditsBackend: String {
    case wikipedia
    case musicBrainz = "musicbrainz"
    case wikipediaThenMusicBrainz = "wikipedia_then_musicbrainz"

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> CreditsBackend {
        guard let raw = environment["SIDEMAN_CREDITS_BACKEND"]?.lowercased() else {
            return .wikipedia
        }

        switch raw {
        case "wikipedia":
            return .wikipedia
        case "musicbrainz":
            return .musicBrainz
        case "wikipedia_then_musicbrainz", "hybrid":
            return .wikipediaThenMusicBrainz
        default:
            return .wikipedia
        }
    }
}

enum CreditsProviderFactory {
    static func makePlaylistBuilder(spotifyClient: SpotifyWebAPI) -> PlaylistBuilder {
        let musicBrainzClient = MusicBrainzHTTPClient()
        let discographyCache = DiscographyCache()
        let discographyService = ArtistDiscographyService(
            musicBrainzClient: musicBrainzClient,
            cache: discographyCache
        )
        let listenBrainzClient = ListenBrainzClient()
        let trackMatchingService = TrackMatchingService(
            musicBrainzClient: musicBrainzClient,
            spotifyClient: spotifyClient
        )
        return PlaylistBuilder(
            discographyService: discographyService,
            listenBrainzClient: listenBrainzClient,
            trackMatchingService: trackMatchingService,
            spotifyClient: spotifyClient
        )
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
            return FallbackCreditsProvider(primary: wikipediaProvider, fallback: musicBrainzProvider)
        }
    }
}

actor FallbackCreditsProvider: CreditsProvider {
    private let primary: CreditsProvider
    private let fallback: CreditsProvider

    init(primary: CreditsProvider, fallback: CreditsProvider) {
        self.primary = primary
        self.fallback = fallback
    }

    func lookupCredits(for track: NowPlayingTrack) async -> (CreditsLookupState, CreditsBundle?) {
        let primaryResult = await primary.lookupCredits(for: track)
        let primaryState = primaryResult.0

        if primaryState == .loaded {
            return primaryResult
        }

        switch primaryState {
        case .notFound, .ambiguous, .error, .rateLimited:
            let fallbackResult = await fallback.lookupCredits(for: track)
            if fallbackResult.0 == .loaded {
                DebugLogger.log(.provider, "fallback provider returned loaded credits")
                return fallbackResult
            }
        case .idle, .resolving, .loadingCredits, .loaded:
            break
        }

        return primaryResult
    }

    func cacheLookupKey(for track: NowPlayingTrack) async -> String {
        await primary.cacheLookupKey(for: track)
    }

    func invalidateCachedCredits(for track: NowPlayingTrack) async {
        await primary.invalidateCachedCredits(for: track)
        await fallback.invalidateCachedCredits(for: track)
    }
}
