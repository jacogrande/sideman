import Foundation

actor DefaultCreditsProvider: CreditsProvider {
    private let resolver: TrackResolver
    private let client: MusicBrainzClient
    private let cache: CreditsCache

    init(
        resolver: TrackResolver,
        client: MusicBrainzClient,
        cache: CreditsCache
    ) {
        self.resolver = resolver
        self.client = client
        self.cache = cache
    }

    func lookupCredits(for track: NowPlayingTrack) async -> (CreditsLookupState, CreditsBundle?) {
        let key = Self.cacheKey(for: track)

        if let cached = await cache.get(for: key) {
            return (cached.state, cached.bundle)
        }

        let resolution = await resolver.resolve(track)
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
        case .success(let result):
            do {
                let bundle = try await loadCreditsBundle(track: track, resolution: result)

                if bundle.isEmpty {
                    let state: CreditsLookupState = .notFound
                    await cacheNegativeState(state, key: key)
                    return (state, nil)
                }

                let state: CreditsLookupState = .loaded
                await cacheSuccess(state: state, bundle: bundle, key: key)
                return (state, bundle)
            } catch let clientError as MusicBrainzClientError {
                switch clientError {
                case .notFound:
                    let state: CreditsLookupState = .notFound
                    await cacheNegativeState(state, key: key)
                    return (state, nil)
                case .rateLimited:
                    return (.rateLimited, nil)
                case .httpStatus, .decoding, .network:
                    return (.error(String(describing: clientError)), nil)
                }
            } catch {
                return (.error(error.localizedDescription), nil)
            }
        }
    }

    private func loadCreditsBundle(track: NowPlayingTrack, resolution: ResolutionResult) async throws -> CreditsBundle {
        let recording = try await client.getRecording(id: resolution.recordingMBID)

        var allEntries = CreditsMapper.mapRelations(recording.relations, sourceLevel: .recording)

        let discoveredWorkIDs = CreditsMapper.extractWorkIDs(from: recording)
        let allWorkIDs = Set(discoveredWorkIDs + resolution.workMBIDs)

        for workID in allWorkIDs {
            do {
                let work = try await client.getWork(id: workID)
                let workEntries = CreditsMapper.mapRelations(work.relations, sourceLevel: .work)
                allEntries.append(contentsOf: workEntries)
            } catch {
                continue
            }
        }

        let requiresReleaseFallback = needsReleaseFallback(entries: allEntries)
        let fallbackReleaseID = resolution.releaseMBID ?? recording.releases.first?.id

        if requiresReleaseFallback, let releaseID = fallbackReleaseID {
            if let release = try? await client.getRelease(id: releaseID) {
                let releaseEntries = CreditsMapper.mapRelations(release.relations, sourceLevel: .release)
                allEntries.append(contentsOf: releaseEntries)
            }
        }

        let merged = CreditsMapper.mergeWithPrecedence(allEntries)
        let grouped = CreditsMapper.group(merged)

        let provenance = Set(merged.map(\.sourceLevel)).sorted { lhs, rhs in
            lhs.sortRank < rhs.sortRank
        }

        return CreditsBundle(
            entriesByGroup: grouped,
            provenance: provenance,
            resolvedRecordingMBID: resolution.recordingMBID
        )
    }

    private func needsReleaseFallback(entries: [CreditEntry]) -> Bool {
        let grouped = CreditsMapper.group(entries)
        let productionMissing = (grouped[.production] ?? []).isEmpty
        let engineeringMissing = (grouped[.engineering] ?? []).isEmpty
        return productionMissing || engineeringMissing
    }

    private func cacheSuccess(state: CreditsLookupState, bundle: CreditsBundle, key: String) async {
        let entry = CachedCredits(
            key: key,
            state: state,
            bundle: bundle,
            expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60)
        )
        await cache.set(entry, for: key)
    }

    private func cacheNegativeState(_ state: CreditsLookupState, key: String) async {
        let entry = CachedCredits(
            key: key,
            state: state,
            bundle: nil,
            expiresAt: Date().addingTimeInterval(24 * 60 * 60)
        )
        await cache.set(entry, for: key)
    }

    static func cacheKey(for track: NowPlayingTrack) -> String {
        if !track.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "spotify:\(track.id.lowercased())"
        }

        let components = [track.title, track.artist, track.album]
            .map(normalize)
            .joined(separator: "|")

        return "meta:\(components)"
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .joined(separator: " ")
    }
}
