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
        DebugLogger.log(.provider, "lookup start key=\(key)")

        if let cached = await cache.get(for: key) {
            DebugLogger.log(.cache, "cache hit key=\(key) state=\(cached.state)")
            return (cached.state, cached.bundle)
        }
        DebugLogger.log(.cache, "cache miss key=\(key)")

        let resolution = await resolver.resolve(track)
        switch resolution {
        case .failure(.notFound):
            let state: CreditsLookupState = .notFound
            DebugLogger.log(.provider, "resolver result=notFound key=\(key)")
            await cacheNegativeState(state, key: key)
            return (state, nil)
        case .failure(.ambiguous):
            let state: CreditsLookupState = .ambiguous
            DebugLogger.log(.provider, "resolver result=ambiguous key=\(key)")
            await cacheNegativeState(state, key: key)
            return (state, nil)
        case .failure(.rateLimited):
            DebugLogger.log(.provider, "resolver result=rateLimited key=\(key)")
            return (.rateLimited, nil)
        case .failure(.network(let message)):
            DebugLogger.log(.provider, "resolver result=error key=\(key) message=\(message)")
            return (.error(message), nil)
        case .success(let result):
            DebugLogger.log(
                .provider,
                "resolver result=success recording=\(result.recordingMBID) release=\(result.releaseMBID ?? "nil")"
            )
            do {
                let bundle = try await loadCreditsBundle(track: track, resolution: result)

                if bundle.isEmpty {
                    let state: CreditsLookupState = .notFound
                    DebugLogger.log(.provider, "bundle empty key=\(key)")
                    await cacheNegativeState(state, key: key)
                    return (state, nil)
                }

                let state: CreditsLookupState = .loaded
                let summary = CreditRoleGroup.displayOrder
                    .map { "\($0.rawValue)=\(bundle.entries(for: $0).count)" }
                    .joined(separator: ", ")
                DebugLogger.log(.provider, "bundle loaded key=\(key) \(summary)")
                await cacheSuccess(state: state, bundle: bundle, key: key)
                return (state, bundle)
            } catch let clientError as MusicBrainzClientError {
                switch clientError {
                case .notFound:
                    let state: CreditsLookupState = .notFound
                    DebugLogger.log(.provider, "lookup client error=notFound key=\(key)")
                    await cacheNegativeState(state, key: key)
                    return (state, nil)
                case .rateLimited:
                    DebugLogger.log(.provider, "lookup client error=rateLimited key=\(key)")
                    return (.rateLimited, nil)
                case .httpStatus, .decoding, .network:
                    DebugLogger.log(.provider, "lookup client error=\(String(describing: clientError))")
                    return (.error(String(describing: clientError)), nil)
                }
            } catch {
                DebugLogger.log(.provider, "lookup error=\(error.localizedDescription)")
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

    private func loadCreditsBundle(track: NowPlayingTrack, resolution: ResolutionResult) async throws -> CreditsBundle {
        let recording = try await client.getRecording(id: resolution.recordingMBID)

        var allEntries = CreditsMapper.mapRelations(recording.relations, sourceLevel: .recording)

        // Extract work-level credits from embedded relations (via work-level-rels).
        // Always mark embedded works as fetched, even if they have no relations —
        // an empty list is a valid state and doesn't need a separate API call.
        var fetchedWorkIDs = Set<String>()
        for relation in recording.relations {
            guard let work = relation.work else { continue }
            let workEntries = CreditsMapper.mapRelations(work.relations, sourceLevel: .work)
            allEntries.append(contentsOf: workEntries)
            fetchedWorkIDs.insert(work.id)
        }

        let discoveredWorkIDs = CreditsMapper.extractWorkIDs(from: recording)
        let remainingWorkIDs = Set(discoveredWorkIDs + resolution.workMBIDs).subtracting(fetchedWorkIDs)

        for workID in remainingWorkIDs {
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
            resolvedRecordingMBID: resolution.recordingMBID,
            sourceID: resolution.recordingMBID
        )
    }

    private func needsReleaseFallback(entries: [CreditEntry]) -> Bool {
        let grouped = CreditsMapper.group(entries)
        let productionMissing = (grouped[.production] ?? []).isEmpty
        let engineeringMissing = (grouped[.engineering] ?? []).isEmpty
        return productionMissing || engineeringMissing
    }

    private func cacheSuccess(state: CreditsLookupState, bundle: CreditsBundle, key: String) async {
        DebugLogger.log(.cache, "cache write success key=\(key) ttl=30d")
        let entry = CachedCredits(
            key: key,
            state: state,
            bundle: bundle,
            expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60)
        )
        await cache.set(entry, for: key)
    }

    private func cacheNegativeState(_ state: CreditsLookupState, key: String) async {
        DebugLogger.log(.cache, "cache write negative key=\(key) state=\(state) ttl=24h")
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
            .map { CreditsTextNormalizer.normalize($0) }
            .joined(separator: "|")

        return "meta:\(components)"
    }
}
