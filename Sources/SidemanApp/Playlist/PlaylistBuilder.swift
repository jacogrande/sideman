import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum PlaylistBuildStage: Equatable {
    case fetchingDiscography
    case rankingByPopularity(total: Int)
    case resolvingTracks(resolved: Int, total: Int)
    case creatingPlaylist(trackCount: Int)
    case complete(playlistName: String, trackCount: Int)
    case failed(String)
}

actor PlaylistBuilder {
    private let discographyService: ArtistDiscographyService
    private let listenBrainzClient: ListenBrainzClient
    private let trackMatchingService: TrackMatchingService
    private let spotifyClient: SpotifyWebAPI

    init(
        discographyService: ArtistDiscographyService,
        listenBrainzClient: ListenBrainzClient,
        trackMatchingService: TrackMatchingService,
        spotifyClient: SpotifyWebAPI
    ) {
        self.discographyService = discographyService
        self.listenBrainzClient = listenBrainzClient
        self.trackMatchingService = trackMatchingService
        self.spotifyClient = spotifyClient
    }

    func buildPlaylist(
        request: PlaylistBuildRequest,
        onStageChange: @escaping @Sendable (PlaylistBuildStage) async -> Void
    ) async throws -> PlaylistBuildResult {
        // Stage 1: Fetch discography
        await onStageChange(.fetchingDiscography)
        try Task.checkCancellation()

        let discography: DiscographyResult
        switch request.mode {
        case .singleArtist:
            discography = try await discographyService.fetchDiscography(
                artistMBID: request.artistMBID,
                artistName: request.artistName,
                roleFilter: request.roleFilter
            )
        case .coCredit:
            guard let coCredit = request.coCredit else {
                throw PlaylistBuilderError.artistResolutionFailed("Co-credit configuration is missing.")
            }
            discography = try await discographyService.fetchCoCreditDiscography(
                artistA: coCredit.artistA,
                artistB: coCredit.artistB,
                matchMode: coCredit.matchMode
            )
        }

        guard !discography.recordings.isEmpty else {
            throw PlaylistBuilderError.noRecordingsFound
        }

        // Stage 2: Rank by popularity
        await onStageChange(.rankingByPopularity(total: discography.recordings.count))
        try Task.checkCancellation()

        // Over-fetch by 1.5x to account for duplicates after dedup
        let fetchCount = min(Int(Double(request.maxTracks) * 1.5), discography.recordings.count)
        let rankedRecordings = await rankByPopularity(
            recordings: discography.recordings,
            artistMBID: request.mode == .singleArtist ? request.artistMBID : nil,
            maxTracks: fetchCount
        )
        var dropTelemetry = PlaylistDropTelemetry(totalCandidates: discography.recordings.count)
        let rankedIDs = Set(rankedRecordings.map(\.recordingMBID))
        for recording in discography.recordings where !rankedIDs.contains(recording.recordingMBID) {
            dropTelemetry.record(
                recordingMBID: recording.recordingMBID,
                recordingTitle: recording.recordingTitle,
                reason: .rankedOut
            )
        }

        // Stage 3: Resolve to Spotify tracks
        try Task.checkCancellation()
        let resolutionSummary = try await trackMatchingService.resolveToSpotifyDetailed(
            recordings: rankedRecordings
        ) { resolved, total in
            await onStageChange(.resolvingTracks(resolved: resolved, total: total))
        }
        let resolvedTracks = resolutionSummary.resolved
        for unresolved in resolutionSummary.unresolved {
            dropTelemetry.record(
                recordingMBID: unresolved.recordingMBID,
                recordingTitle: unresolved.recordingTitle,
                reason: mapDropReason(unresolved.reason)
            )
        }

        guard !resolvedTracks.isEmpty else {
            throw PlaylistBuilderError.noTracksResolved
        }

        // Deduplicate by Spotify URI (keep first/highest-ranked occurrence)
        var seenURIs = Set<String>()
        var uniqueTracks: [ResolvedTrack] = []
        for track in resolvedTracks {
            if seenURIs.insert(track.spotifyURI).inserted {
                uniqueTracks.append(track)
            } else {
                dropTelemetry.record(
                    recordingMBID: track.recordingMBID,
                    recordingTitle: track.recordingTitle,
                    reason: .duplicateSpotifyURI
                )
            }
        }

        // Re-sort by Spotify popularity, then truncate to the user's target
        let popularitySortedTracks = uniqueTracks.sorted { lhs, rhs in
            (rhs.spotifyPopularity ?? 0) < (lhs.spotifyPopularity ?? 0)
        }
        let sortedTracks = Array(popularitySortedTracks.prefix(request.maxTracks))
        if popularitySortedTracks.count > request.maxTracks {
            for track in popularitySortedTracks.dropFirst(request.maxTracks) {
                dropTelemetry.record(
                    recordingMBID: track.recordingMBID,
                    recordingTitle: track.recordingTitle,
                    reason: .truncatedByTrackLimit
                )
            }
        }

        DebugLogger.log(.provider, "deduplication: \(resolvedTracks.count) resolved → \(uniqueTracks.count) unique → \(sortedTracks.count) final")
        dropTelemetry.log()

        // Stage 4: Create playlist
        let trackCount = sortedTracks.count
        await onStageChange(.creatingPlaylist(trackCount: trackCount))
        try Task.checkCancellation()

        let playlistName = buildPlaylistName(request: request)
        let description = buildPlaylistDescription(request: request, trackCount: trackCount)

        let playlist = try await spotifyClient.createPlaylist(
            name: playlistName,
            description: description,
            isPublic: request.isPublic
        )

        let uris = sortedTracks.map(\.spotifyURI)
        try await spotifyClient.addTracksToPlaylist(playlistID: playlist.id, trackURIs: uris)

        let skippedCount = rankedRecordings.count - trackCount
        let result = PlaylistBuildResult(
            playlistName: playlistName,
            playlistURI: "spotify:playlist:\(playlist.id)",
            trackCount: trackCount,
            skippedCount: skippedCount
        )

        await onStageChange(.complete(playlistName: playlistName, trackCount: trackCount))

        // Open in Spotify
        openInSpotify(playlistID: playlist.id)

        DebugLogger.log(.app, "playlist created: \(playlistName) tracks=\(trackCount) skipped=\(skippedCount)")
        return result
    }

    private func rankByPopularity(recordings: [ArtistRecordingRel], artistMBID: String?, maxTracks: Int) async -> [ArtistRecordingRel] {
        let mbids = recordings.map(\.recordingMBID)

        // Try batch popularity lookup
        var popularityMap: [String: Int] = [:]
        do {
            let popularity = try await listenBrainzClient.recordingPopularity(mbids: mbids)
            for item in popularity {
                if let count = item.listenCount {
                    popularityMap[item.recordingMBID] = count
                }
            }
        } catch {
            DebugLogger.log(.provider, "ListenBrainz popularity batch failed: \(error)")
        }

        // Fallback: try top recordings for artist
        if popularityMap.isEmpty, let artistMBID {
            do {
                let topRecordings = try await listenBrainzClient.topRecordingsForArtist(artistMBID: artistMBID)
                for item in topRecordings {
                    if let count = item.listenCount {
                        popularityMap[item.recordingMBID] = count
                    }
                }
            } catch {
                DebugLogger.log(.provider, "ListenBrainz top recordings failed: \(error)")
            }
        }

        let ranked: [ArtistRecordingRel]
        if popularityMap.isEmpty {
            // Fallback: alphabetical
            ranked = recordings.sorted { $0.recordingTitle.localizedCaseInsensitiveCompare($1.recordingTitle) == .orderedAscending }
        } else {
            ranked = recordings.sorted {
                (popularityMap[$0.recordingMBID] ?? 0) > (popularityMap[$1.recordingMBID] ?? 0)
            }
        }

        return Array(ranked.prefix(maxTracks))
    }

    private func buildPlaylistName(request: PlaylistBuildRequest) -> String {
        if request.mode == .coCredit, let coCredit = request.coCredit {
            return "\(coCredit.artistA.name) × \(coCredit.artistB.name) — co-credits"
        }
        if let role = request.roleFilter {
            return "\(request.artistName) — \(role.filterLabel)"
        }
        return "\(request.artistName) — all credits"
    }

    private func buildPlaylistDescription(request: PlaylistBuildRequest, trackCount: Int) -> String {
        if request.mode == .coCredit, let coCredit = request.coCredit {
            return "\(trackCount) tracks where both \(coCredit.artistA.name) and \(coCredit.artistB.name) are credited (\(coCredit.matchMode.title.lowercased())). Generated by Sideman."
        }
        let roleDesc = request.roleFilter.map { "as a \($0.filterLabel.lowercased())" } ?? "across all credits"
        return "\(trackCount) tracks featuring \(request.artistName) \(roleDesc). Generated by Sideman."
    }

    private func mapDropReason(_ reason: TrackResolutionDropReason) -> PlaylistDropReason {
        switch reason {
        case .missingArtistCredits:
            return .missingArtistCredits
        case .noSpotifyMatch:
            return .noSpotifyMatch
        }
    }

    private func openInSpotify(playlistID: String) {
        #if canImport(AppKit)
        guard let url = URL(string: "spotify:playlist:\(playlistID)") else { return }
        Task { @MainActor in
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

private enum PlaylistDropReason: String, CaseIterable {
    case rankedOut = "ranked_out"
    case missingArtistCredits = "missing_artist_credits"
    case noSpotifyMatch = "spotify_no_match"
    case duplicateSpotifyURI = "duplicate_spotify_uri"
    case truncatedByTrackLimit = "truncated_by_track_limit"
}

private struct PlaylistDropEntry {
    let recordingMBID: String
    let recordingTitle: String
    let reason: PlaylistDropReason
}

private struct PlaylistDropTelemetry {
    let totalCandidates: Int
    private(set) var entries: [PlaylistDropEntry] = []

    mutating func record(recordingMBID: String, recordingTitle: String, reason: PlaylistDropReason) {
        entries.append(
            PlaylistDropEntry(
                recordingMBID: recordingMBID,
                recordingTitle: recordingTitle,
                reason: reason
            )
        )
    }

    func log() {
        let reasonCounts = Dictionary(grouping: entries, by: \.reason)
            .mapValues(\.count)
        let reasonSummary = PlaylistDropReason.allCases
            .map { "\($0.rawValue)=\(reasonCounts[$0, default: 0])" }
            .joined(separator: ", ")

        DebugLogger.log(
            .provider,
            "playlist drop telemetry: total_candidates=\(totalCandidates), dropped=\(entries.count) [\(reasonSummary)]"
        )

        for entry in entries.prefix(160) {
            DebugLogger.log(
                .provider,
                "playlist drop reason=\(entry.reason.rawValue) recording=\(entry.recordingMBID) title='\(entry.recordingTitle)'"
            )
        }
    }
}
