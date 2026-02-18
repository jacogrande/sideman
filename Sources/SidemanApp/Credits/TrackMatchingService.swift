import Foundation

actor TrackMatchingService {
    private let musicBrainzClient: MusicBrainzClient
    private let spotifyClient: SpotifyWebAPI

    init(musicBrainzClient: MusicBrainzClient, spotifyClient: SpotifyWebAPI) {
        self.musicBrainzClient = musicBrainzClient
        self.spotifyClient = spotifyClient
    }

    func resolveToSpotify(
        recordings: [ArtistRecordingRel],
        onProgress: @Sendable (Int, Int) async -> Void
    ) async throws -> [ResolvedTrack] {
        var resolved: [ResolvedTrack] = []
        let total = recordings.count

        for (index, recording) in recordings.enumerated() {
            try Task.checkCancellation()
            await onProgress(index, total)

            if let track = try await resolveViaISRC(recording: recording) {
                resolved.append(track)
                continue
            }

            if let track = try await resolveViaTextSearch(recording: recording) {
                resolved.append(track)
                continue
            }

            DebugLogger.log(.provider, "track skip: no match for '\(recording.recordingTitle)' (\(recording.recordingMBID))")
        }

        await onProgress(total, total)
        DebugLogger.log(.provider, "track matching complete: \(resolved.count)/\(total) resolved")
        return resolved
    }

    private func resolveViaISRC(recording: ArtistRecordingRel) async throws -> ResolvedTrack? {
        let isrcs: [String]
        do {
            isrcs = try await musicBrainzClient.getRecordingISRCs(id: recording.recordingMBID)
        } catch {
            return nil
        }

        for isrc in isrcs.prefix(2) {
            try Task.checkCancellation()
            do {
                let tracks = try await spotifyClient.searchTrackByISRC(isrc)
                if let first = tracks.first {
                    return ResolvedTrack(
                        recordingMBID: recording.recordingMBID,
                        recordingTitle: recording.recordingTitle,
                        spotifyURI: first.uri,
                        spotifyPopularity: first.popularity,
                        matchStrategy: .isrc
                    )
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private func resolveViaTextSearch(recording: ArtistRecordingRel) async throws -> ResolvedTrack? {
        let artist = recording.artistCredits.first ?? ""
        guard !artist.isEmpty else { return nil }

        do {
            let tracks = try await spotifyClient.searchTracks(
                title: recording.recordingTitle,
                artist: artist
            )

            if let first = tracks.first {
                return ResolvedTrack(
                    recordingMBID: recording.recordingMBID,
                    recordingTitle: recording.recordingTitle,
                    spotifyURI: first.uri,
                    spotifyPopularity: first.popularity,
                    matchStrategy: .textSearch
                )
            }
        } catch {
            DebugLogger.log(.provider, "text search failed for '\(recording.recordingTitle)': \(error)")
        }

        return nil
    }
}
