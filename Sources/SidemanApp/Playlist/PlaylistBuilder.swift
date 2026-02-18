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

        let discography = try await discographyService.fetchDiscography(
            artistMBID: request.artistMBID,
            artistName: request.artistName,
            roleFilter: request.roleFilter
        )

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
            artistMBID: request.artistMBID,
            maxTracks: fetchCount
        )

        // Stage 3: Resolve to Spotify tracks
        try Task.checkCancellation()
        let resolvedTracks = try await trackMatchingService.resolveToSpotify(
            recordings: rankedRecordings
        ) { resolved, total in
            await onStageChange(.resolvingTracks(resolved: resolved, total: total))
        }

        guard !resolvedTracks.isEmpty else {
            throw PlaylistBuilderError.noTracksResolved
        }

        // Deduplicate by Spotify URI (keep first/highest-ranked occurrence)
        var seenURIs = Set<String>()
        let uniqueTracks = resolvedTracks.filter { seenURIs.insert($0.spotifyURI).inserted }

        // Re-sort by Spotify popularity, then truncate to the user's target
        let sortedTracks = Array(uniqueTracks.sorted { lhs, rhs in
            (rhs.spotifyPopularity ?? 0) < (lhs.spotifyPopularity ?? 0)
        }.prefix(request.maxTracks))

        DebugLogger.log(.provider, "deduplication: \(resolvedTracks.count) resolved → \(uniqueTracks.count) unique → \(sortedTracks.count) final")

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

    private func rankByPopularity(recordings: [ArtistRecordingRel], artistMBID: String, maxTracks: Int) async -> [ArtistRecordingRel] {
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
        if popularityMap.isEmpty {
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
        if let role = request.roleFilter {
            return "\(request.artistName) as a \(role.filterLabel.lowercased())"
        }
        return "\(request.artistName) — all credits"
    }

    private func buildPlaylistDescription(request: PlaylistBuildRequest, trackCount: Int) -> String {
        let roleDesc = request.roleFilter.map { "as a \($0.filterLabel.lowercased())" } ?? "across all credits"
        return "\(trackCount) tracks featuring \(request.artistName) \(roleDesc). Generated by Sideman."
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
