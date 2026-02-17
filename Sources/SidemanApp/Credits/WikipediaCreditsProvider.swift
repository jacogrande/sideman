import Foundation

actor WikipediaCreditsProvider: CreditsProvider {
    private let resolver: WikipediaPageResolver
    private let client: WikipediaAPIClient
    private let parser: WikipediaWikitextParser
    private let cache: CreditsCache
    private let successCacheTTL: TimeInterval
    private let negativeCacheTTL: TimeInterval

    init(
        resolver: WikipediaPageResolver,
        client: WikipediaAPIClient,
        parser: WikipediaWikitextParser = DefaultWikipediaWikitextParser(),
        cache: CreditsCache,
        successCacheTTL: TimeInterval = 7 * 24 * 60 * 60,
        negativeCacheTTL: TimeInterval = 6 * 60 * 60
    ) {
        self.resolver = resolver
        self.client = client
        self.parser = parser
        self.cache = cache
        self.successCacheTTL = successCacheTTL
        self.negativeCacheTTL = negativeCacheTTL
    }

    func lookupCredits(for track: NowPlayingTrack) async -> (CreditsLookupState, CreditsBundle?) {
        let key = Self.cacheKey(for: track)
        DebugLogger.log(.provider, "wikipedia lookup start key=\(key)")

        if let cached = await cache.get(for: key) {
            DebugLogger.log(.cache, "cache hit key=\(key) state=\(cached.state)")
            return (cached.state, cached.bundle)
        }

        let resolution = await resolver.resolvePage(for: track)
        switch resolution {
        case .failure(.notFound):
            let state: CreditsLookupState = .notFound
            await cacheNegativeState(state, key: key)
            return (state, nil)
        case .failure(.ambiguous):
            let state: CreditsLookupState = .ambiguous
            await cacheNegativeState(state, key: key)
            return (state, nil)
        case .failure(.rateLimited):
            return (.rateLimited, nil)
        case .failure(.network(let message)):
            return (.error(message), nil)
        case .success(let pageResolution):
            DebugLogger.log(.provider, "wikipedia resolution pageID=\(pageResolution.pageID) title='\(pageResolution.title)'")

            do {
                let page = try await client.fetchPage(pageID: pageResolution.pageID)
                let parsed = parser.parse(page: page, for: track)

                if parsed.entries.isEmpty {
                    let state: CreditsLookupState = .notFound
                    await cacheNegativeState(state, key: key)
                    return (state, nil)
                }

                let grouped = CreditsMapper.group(parsed.entries)
                let provenance = Set(parsed.entries.map(\.sourceLevel)).sorted { lhs, rhs in
                    lhs.sortRank < rhs.sortRank
                }
                let bundle = CreditsBundle(
                    entriesByGroup: grouped,
                    provenance: provenance.isEmpty ? [.release] : provenance,
                    resolvedRecordingMBID: "wikipedia:\(page.pageID)",
                    sourceID: "wikipedia:\(page.pageID)",
                    sourceName: "Wikipedia",
                    sourcePageTitle: page.title,
                    sourcePageURL: page.fullURL,
                    sourceAttribution: "Wikipedia contributors (CC BY-SA)",
                    matchedTrackNumber: parsed.matchedTrackNumber
                )

                let state: CreditsLookupState = .loaded
                await cacheSuccess(state: state, bundle: bundle, key: key)
                return (state, bundle)
            } catch let error as WikipediaClientError {
                switch error {
                case .notFound:
                    let state: CreditsLookupState = .notFound
                    await cacheNegativeState(state, key: key)
                    return (state, nil)
                case .rateLimited:
                    return (.rateLimited, nil)
                case .httpStatus, .decoding, .network:
                    return (.error(String(describing: error)), nil)
                }
            } catch {
                return (.error(error.localizedDescription), nil)
            }
        }
    }

    func cacheLookupKey(for track: NowPlayingTrack) async -> String {
        Self.cacheKey(for: track)
    }

    func invalidateCachedCredits(for track: NowPlayingTrack) async {
        let key = Self.cacheKey(for: track)
        await cache.remove(for: key)
    }

    private func cacheSuccess(state: CreditsLookupState, bundle: CreditsBundle, key: String) async {
        let entry = CachedCredits(
            key: key,
            state: state,
            bundle: bundle,
            expiresAt: Date().addingTimeInterval(successCacheTTL)
        )
        await cache.set(entry, for: key)
    }

    private func cacheNegativeState(_ state: CreditsLookupState, key: String) async {
        let entry = CachedCredits(
            key: key,
            state: state,
            bundle: nil,
            expiresAt: Date().addingTimeInterval(negativeCacheTTL)
        )
        await cache.set(entry, for: key)
    }

    static func cacheKey(for track: NowPlayingTrack) -> String {
        if !track.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "wikipedia:spotify:\(track.id.lowercased())"
        }

        let components = [track.title, track.artist, track.album]
            .map { CreditsTextNormalizer.normalize($0) }
            .joined(separator: "|")

        return "wikipedia:meta:\(components)"
    }
}
