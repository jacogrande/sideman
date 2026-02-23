import Foundation

actor TrackMatchingService {
    private let musicBrainzClient: MusicBrainzClient
    private let spotifyClient: SpotifyWebAPI
    private let discogsClient: DiscogsClient?
    private let maxConcurrency: Int
    private let textSearchMinScore = 0.58
    private let textSearchStrongScore = 0.80
    private let maxArtistQueries = 4
    private let titleNormalization: TextNormalizationOptions = [
        .stripFeaturingSuffix,
        .stripParentheticalText,
        .alphanumericsOnly,
        .collapseWhitespace
    ]
    private let artistNormalization: TextNormalizationOptions = [.alphanumericsOnly, .collapseWhitespace]

    init(
        musicBrainzClient: MusicBrainzClient,
        spotifyClient: SpotifyWebAPI,
        discogsClient: DiscogsClient? = nil,
        maxConcurrency: Int = 8
    ) {
        self.musicBrainzClient = musicBrainzClient
        self.spotifyClient = spotifyClient
        self.discogsClient = discogsClient
        self.maxConcurrency = maxConcurrency
    }

    func resolveToSpotify(
        recordings: [ArtistRecordingRel],
        fallbackArtistQueries: [String] = [],
        onProgress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> [ResolvedTrack] {
        let summary = try await resolveToSpotifyDetailed(
            recordings: recordings,
            fallbackArtistQueries: fallbackArtistQueries,
            onProgress: onProgress
        )
        return summary.resolved
    }

    func resolveToSpotifyDetailed(
        recordings: [ArtistRecordingRel],
        fallbackArtistQueries: [String] = [],
        onProgress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> TrackResolutionSummary {
        let total = recordings.count
        guard total > 0 else {
            return TrackResolutionSummary(resolved: [], unresolved: [])
        }

        // Shared mutable state protected by actor isolation via the progress closure
        let progressCounter = ProgressCounter(total: total, onProgress: onProgress)

        // Process in concurrent batches. If Spotify rate-limits us, we shrink the
        // batch size and retry the failed items rather than aborting.
        var pending = Array(recordings.enumerated())
        var allResolved: [ResolvedTrack] = []
        var unresolved: [UnresolvedTrack] = []
        var currentConcurrency = maxConcurrency

        while !pending.isEmpty {
            try Task.checkCancellation()

            let batch = Array(pending.prefix(currentConcurrency))
            pending.removeFirst(batch.count)

            let results = try await resolveBatch(
                batch,
                fallbackArtistQueries: fallbackArtistQueries,
                progressCounter: progressCounter
            )

            var rateLimited: [(offset: Int, element: ArtistRecordingRel)] = []
            for result in results {
                switch result {
                case .resolved(let track):
                    allResolved.append(track)
                case .unresolved(let dropped):
                    unresolved.append(dropped)
                case .rateLimited(let item):
                    rateLimited.append(item)
                }
            }

            if !rateLimited.isEmpty {
                // Back off: halve concurrency (minimum 1) and re-queue failed items
                currentConcurrency = max(1, currentConcurrency / 2)
                let backoff: UInt64 = 2_000_000_000 // 2 seconds
                DebugLogger.log(.provider, "rate limited, reducing concurrency to \(currentConcurrency), backing off 2s")
                try? await Task.sleep(nanoseconds: backoff)
                pending = rateLimited + pending
            } else if currentConcurrency < maxConcurrency {
                // Gradually restore concurrency after successful batches
                currentConcurrency = min(maxConcurrency, currentConcurrency + 1)
            }
        }

        await progressCounter.finish()
        let unresolvedReasonSummary = Dictionary(grouping: unresolved, by: \.reason)
            .map { key, value in "\(key.rawValue)=\(value.count)" }
            .sorted()
            .joined(separator: ", ")
        DebugLogger.log(
            .provider,
            "track matching complete: \(allResolved.count)/\(total) resolved; unresolved=\(unresolved.count) [\(unresolvedReasonSummary)]"
        )
        return TrackResolutionSummary(resolved: allResolved, unresolved: unresolved)
    }

    private enum ResolveResult: Sendable {
        case resolved(ResolvedTrack)
        case unresolved(UnresolvedTrack)
        case rateLimited((offset: Int, element: ArtistRecordingRel))
    }

    private enum ResolveOneResult: Sendable {
        case resolved(ResolvedTrack)
        case unresolved(TrackResolutionDropReason)
    }

    private struct ScoredSpotifyTrack {
        let track: SpotifyTrack
        let score: Double
    }

    private func resolveBatch(
        _ items: [(offset: Int, element: ArtistRecordingRel)],
        fallbackArtistQueries: [String],
        progressCounter: ProgressCounter
    ) async throws -> [ResolveResult] {
        try await withThrowingTaskGroup(of: ResolveResult.self) { group in
            for item in items {
                group.addTask {
                    try Task.checkCancellation()
                    do {
                        let resolution = try await self.resolveOne(
                            recording: item.element,
                            fallbackArtistQueries: fallbackArtistQueries
                        )
                        await progressCounter.increment()
                        switch resolution {
                        case .resolved(let track):
                            return .resolved(track)
                        case .unresolved(let reason):
                            return .unresolved(
                                UnresolvedTrack(
                                    recordingMBID: item.element.recordingMBID,
                                    recordingTitle: item.element.recordingTitle,
                                    reason: reason
                                )
                            )
                        }
                    } catch let spotifyError as SpotifyClientError where spotifyError == .rateLimited {
                        return .rateLimited(item)
                    }
                }
            }

            var results: [ResolveResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func resolveOne(
        recording: ArtistRecordingRel,
        fallbackArtistQueries: [String]
    ) async throws -> ResolveOneResult {
        if let track = try await resolveViaISRC(recording: recording) {
            return .resolved(track)
        }
        return try await resolveViaTextSearch(recording: recording, fallbackArtistQueries: fallbackArtistQueries)
    }

    private func resolveViaISRC(recording: ArtistRecordingRel) async throws -> ResolvedTrack? {
        let isrcs: [String]
        if !recording.isrcs.isEmpty {
            isrcs = recording.isrcs
        } else {
            do {
                isrcs = try await musicBrainzClient.getRecordingISRCs(id: recording.recordingMBID)
            } catch let error as MusicBrainzClientError where error == .rateLimited {
                throw error
            } catch {
                return nil
            }
        }

        for isrc in isrcs.prefix(3) {
            try Task.checkCancellation()
            do {
                let tracks = try await spotifyClient.searchTrackByISRC(isrc)
                if let best = bestSpotifyCandidate(
                    in: tracks,
                    recording: recording,
                    queryArtist: recording.artistCredits.first ?? "",
                    isRelaxedQuery: false,
                    preferredISRC: isrc
                ) {
                    return ResolvedTrack(
                        recordingMBID: recording.recordingMBID,
                        recordingTitle: recording.recordingTitle,
                        spotifyURI: best.track.uri,
                        spotifyPopularity: best.track.popularity,
                        matchStrategy: .isrc
                    )
                }
            } catch let error as SpotifyClientError where error == .rateLimited {
                throw error
            } catch {
                continue
            }
        }

        return nil
    }

    private func resolveViaTextSearch(
        recording: ArtistRecordingRel,
        fallbackArtistQueries: [String]
    ) async throws -> ResolveOneResult {
        let titleQueries = buildTitleQueries(for: recording.recordingTitle)
        let baseArtistQueries = buildArtistQueries(from: recording.artistCredits + fallbackArtistQueries)

        var queriedArtistKeys = Set(baseArtistQueries.map(normalizedArtistKey))
        var best = try await findBestViaTextSearch(
            recording: recording,
            titleQueries: titleQueries,
            artistQueries: baseArtistQueries
        )

        var discogsQueries: [String] = []
        if best == nil, let discogsClient {
            let seedArtists = !baseArtistQueries.isEmpty ? baseArtistQueries : fallbackArtistQueries
            do {
                let hints = try await discogsClient.artistHintsForTrack(
                    title: recording.recordingTitle,
                    artistHints: seedArtists,
                    limit: maxArtistQueries
                )
                discogsQueries = buildArtistQueries(from: hints).filter { artist in
                    queriedArtistKeys.insert(normalizedArtistKey(artist)).inserted
                }
                if !discogsQueries.isEmpty {
                    DebugLogger.log(
                        .provider,
                        "discogs hints for '\(recording.recordingTitle)': \(discogsQueries.joined(separator: ", "))"
                    )
                    let discogsBest = try await findBestViaTextSearch(
                        recording: recording,
                        titleQueries: titleQueries,
                        artistQueries: discogsQueries
                    )
                    if let discogsBest {
                        if let currentBest = best {
                            best = chooseBetter(currentBest, discogsBest)
                        } else {
                            best = discogsBest
                        }
                    }
                }
            } catch let error as DiscogsClientError where error == .rateLimited {
                DebugLogger.log(.provider, "discogs hint lookup rate-limited for '\(recording.recordingTitle)'")
            } catch {
                DebugLogger.log(.provider, "discogs hint lookup failed for '\(recording.recordingTitle)': \(error)")
            }
        }

        let attemptedArtistQuery = !baseArtistQueries.isEmpty || !discogsQueries.isEmpty

        guard let best else {
            return .unresolved(attemptedArtistQuery ? .noSpotifyMatch : .missingArtistCredits)
        }

        guard best.score >= textSearchMinScore else {
            DebugLogger.log(
                .provider,
                "text search rejected '\(recording.recordingTitle)' bestScore=\(String(format: "%.3f", best.score))"
            )
            return .unresolved(.noSpotifyMatch)
        }

        return .resolved(
            ResolvedTrack(
                recordingMBID: recording.recordingMBID,
                recordingTitle: recording.recordingTitle,
                spotifyURI: best.track.uri,
                spotifyPopularity: best.track.popularity,
                matchStrategy: .textSearch
            )
        )
    }

    private func findBestViaTextSearch(
        recording: ArtistRecordingRel,
        titleQueries: [String],
        artistQueries: [String]
    ) async throws -> ScoredSpotifyTrack? {
        guard !titleQueries.isEmpty, !artistQueries.isEmpty else {
            return nil
        }

        var best: ScoredSpotifyTrack?
        searchLoop: for (titleIndex, titleQuery) in titleQueries.enumerated() {
            let isRelaxed = titleIndex > 0

            for artistQuery in artistQueries.prefix(maxArtistQueries) {
                try Task.checkCancellation()

                do {
                    let tracks = try await spotifyClient.searchTracks(
                        title: titleQuery,
                        artist: artistQuery
                    )
                    guard !tracks.isEmpty else {
                        continue
                    }

                    if let candidate = bestSpotifyCandidate(
                        in: tracks,
                        recording: recording,
                        queryArtist: artistQuery,
                        isRelaxedQuery: isRelaxed,
                        preferredISRC: nil
                    ) {
                        if let currentBest = best {
                            best = chooseBetter(currentBest, candidate)
                        } else {
                            best = candidate
                        }

                        if let best, best.score >= textSearchStrongScore {
                            break searchLoop
                        }
                    }
                } catch let error as SpotifyClientError where error == .rateLimited {
                    throw error
                } catch {
                    DebugLogger.log(.provider, "text search failed for '\(recording.recordingTitle)' artist='\(artistQuery)': \(error)")
                }
            }
        }

        return best
    }

    private func chooseBetter(_ lhs: ScoredSpotifyTrack, _ rhs: ScoredSpotifyTrack) -> ScoredSpotifyTrack {
        if rhs.score == lhs.score {
            return (rhs.track.popularity ?? 0) > (lhs.track.popularity ?? 0) ? rhs : lhs
        }
        return rhs.score > lhs.score ? rhs : lhs
    }

    private func bestSpotifyCandidate(
        in tracks: [SpotifyTrack],
        recording: ArtistRecordingRel,
        queryArtist: String,
        isRelaxedQuery: Bool,
        preferredISRC: String?
    ) -> ScoredSpotifyTrack? {
        tracks
            .map { track in
                ScoredSpotifyTrack(
                    track: track,
                    score: score(
                        track: track,
                        recording: recording,
                        queryArtist: queryArtist,
                        isRelaxedQuery: isRelaxedQuery,
                        preferredISRC: preferredISRC
                    )
                )
            }
            .max { lhs, rhs in
                if lhs.score == rhs.score {
                    return (lhs.track.popularity ?? 0) < (rhs.track.popularity ?? 0)
                }
                return lhs.score < rhs.score
            }
    }

    private func score(
        track: SpotifyTrack,
        recording: ArtistRecordingRel,
        queryArtist: String,
        isRelaxedQuery: Bool,
        preferredISRC: String?
    ) -> Double {
        let normalizedRecordingTitle = CreditsTextNormalizer.normalize(recording.recordingTitle, options: titleNormalization)
        let normalizedSpotifyTitle = CreditsTextNormalizer.normalize(track.name, options: titleNormalization)
        let titleSimilarity = CreditsTextSimilarity.jaccardSimilarity(
            normalizedRecordingTitle,
            normalizedSpotifyTitle,
            containsMatchScore: 0.94
        )

        let normalizedRecordingArtists = recording.artistCredits
            .map { CreditsTextNormalizer.normalize($0, options: artistNormalization) }
            .filter { !$0.isEmpty }
        let normalizedSpotifyArtists = track.artistNames
            .map { CreditsTextNormalizer.normalize($0, options: artistNormalization) }
            .filter { !$0.isEmpty }

        let bestArtistSimilarity = maxArtistSimilarity(
            sourceArtists: normalizedRecordingArtists,
            candidateArtists: normalizedSpotifyArtists
        )
        let artistCoverage = artistCoverageScore(
            sourceArtists: normalizedRecordingArtists,
            candidateArtists: normalizedSpotifyArtists
        )

        let normalizedQueryArtist = CreditsTextNormalizer.normalize(queryArtist, options: artistNormalization)
        let queryArtistSimilarity = queryArtistArtistSimilarity(
            queryArtist: normalizedQueryArtist,
            candidateArtists: normalizedSpotifyArtists
        )

        var total = 0.63 * titleSimilarity
        total += 0.23 * bestArtistSimilarity
        total += 0.08 * artistCoverage
        total += 0.04 * queryArtistSimilarity
        total += 0.02 * popularityScore(track.popularity)

        if isPreferredISRC(track: track, recording: recording, preferredISRC: preferredISRC) {
            total += 0.25
        }

        if isRelaxedQuery {
            total -= 0.03
        }

        return max(0, min(total, 1.5))
    }

    private func maxArtistSimilarity(sourceArtists: [String], candidateArtists: [String]) -> Double {
        guard !sourceArtists.isEmpty, !candidateArtists.isEmpty else {
            return 0
        }

        var best = 0.0
        for source in sourceArtists {
            for candidate in candidateArtists {
                let similarity = CreditsTextSimilarity.jaccardSimilarity(source, candidate, containsMatchScore: 0.9)
                if similarity > best {
                    best = similarity
                }
            }
        }
        return best
    }

    private func artistCoverageScore(sourceArtists: [String], candidateArtists: [String]) -> Double {
        guard !sourceArtists.isEmpty, !candidateArtists.isEmpty else {
            return 0
        }

        let matchedCount = sourceArtists.filter { source in
            candidateArtists.contains { candidate in
                CreditsTextSimilarity.jaccardSimilarity(source, candidate, containsMatchScore: 0.9) >= 0.75
            }
        }.count

        return Double(matchedCount) / Double(sourceArtists.count)
    }

    private func queryArtistArtistSimilarity(queryArtist: String, candidateArtists: [String]) -> Double {
        guard !queryArtist.isEmpty, !candidateArtists.isEmpty else {
            return 0
        }
        return candidateArtists.map {
            CreditsTextSimilarity.jaccardSimilarity(queryArtist, $0, containsMatchScore: 0.9)
        }.max() ?? 0
    }

    private func popularityScore(_ popularity: Int?) -> Double {
        let clamped = max(0, min(100, popularity ?? 0))
        return Double(clamped) / 100.0
    }

    private func isPreferredISRC(track: SpotifyTrack, recording: ArtistRecordingRel, preferredISRC: String?) -> Bool {
        guard let trackISRC = track.isrc?.uppercased() else {
            return false
        }

        if let preferredISRC = preferredISRC?.uppercased(), trackISRC == preferredISRC {
            return true
        }

        return recording.isrcs.contains { $0.uppercased() == trackISRC }
    }

    private func buildArtistQueries(from credits: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for artist in credits {
            let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            let key = CreditsTextNormalizer.normalize(trimmed, options: artistNormalization)
            if key.isEmpty {
                continue
            }
            if seen.insert(key).inserted {
                ordered.append(trimmed)
            }
        }

        return ordered
    }

    private func normalizedArtistKey(_ value: String) -> String {
        CreditsTextNormalizer.normalize(value, options: artistNormalization)
    }

    private func buildTitleQueries(for title: String) -> [String] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        var variants: [String] = [trimmed]
        let withoutParens = trimmed.replacingOccurrences(
            of: #"\([^\)]*\)"#,
            with: " ",
            options: .regularExpression
        )
        let withoutFeat = withoutParens.replacingOccurrences(
            of: #"\b(feat\.?|featuring)\b.*$"#,
            with: " ",
            options: .regularExpression
        )
        let cleanedWithoutFeat = withoutFeat
            .split(separator: " ")
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedWithoutFeat.isEmpty, cleanedWithoutFeat.caseInsensitiveCompare(trimmed) != .orderedSame {
            variants.append(cleanedWithoutFeat)
        }

        if let dashRange = trimmed.range(of: " - ") {
            let beforeDash = String(trimmed[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !beforeDash.isEmpty, beforeDash.caseInsensitiveCompare(trimmed) != .orderedSame {
                variants.append(beforeDash)
            }
        }

        var deduped: [String] = []
        var seen = Set<String>()
        for variant in variants {
            let key = variant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.isEmpty {
                continue
            }
            if seen.insert(key).inserted {
                deduped.append(variant)
            }
        }
        return deduped
    }
}

/// Actor-based progress counter for concurrent track resolution.
private actor ProgressCounter {
    private var completed: Int = 0
    private let total: Int
    private let onProgress: @Sendable (Int, Int) async -> Void

    init(total: Int, onProgress: @escaping @Sendable (Int, Int) async -> Void) {
        self.total = total
        self.onProgress = onProgress
    }

    func increment() async {
        completed += 1
        await onProgress(completed, total)
    }

    func finish() async {
        await onProgress(total, total)
    }
}
