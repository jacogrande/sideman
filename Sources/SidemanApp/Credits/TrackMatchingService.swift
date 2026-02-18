import Foundation

actor TrackMatchingService {
    private let musicBrainzClient: MusicBrainzClient
    private let spotifyClient: SpotifyWebAPI
    private let maxConcurrency: Int

    init(musicBrainzClient: MusicBrainzClient, spotifyClient: SpotifyWebAPI, maxConcurrency: Int = 8) {
        self.musicBrainzClient = musicBrainzClient
        self.spotifyClient = spotifyClient
        self.maxConcurrency = maxConcurrency
    }

    func resolveToSpotify(
        recordings: [ArtistRecordingRel],
        onProgress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> [ResolvedTrack] {
        let total = recordings.count
        guard total > 0 else { return [] }

        // Shared mutable state protected by actor isolation via the progress closure
        let progressCounter = ProgressCounter(total: total, onProgress: onProgress)

        // Process in concurrent batches. If Spotify rate-limits us, we shrink the
        // batch size and retry the failed items rather than aborting.
        var pending = Array(recordings.enumerated())
        var allResolved: [ResolvedTrack] = []
        var currentConcurrency = maxConcurrency

        while !pending.isEmpty {
            try Task.checkCancellation()

            let batch = Array(pending.prefix(currentConcurrency))
            pending.removeFirst(batch.count)

            let results = try await resolveBatch(batch, progressCounter: progressCounter)

            var rateLimited: [(offset: Int, element: ArtistRecordingRel)] = []
            for result in results {
                switch result {
                case .resolved(let track):
                    allResolved.append(track)
                case .notFound:
                    break
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
        DebugLogger.log(.provider, "track matching complete: \(allResolved.count)/\(total) resolved")
        return allResolved
    }

    private enum ResolveResult: Sendable {
        case resolved(ResolvedTrack)
        case notFound
        case rateLimited((offset: Int, element: ArtistRecordingRel))
    }

    private func resolveBatch(
        _ items: [(offset: Int, element: ArtistRecordingRel)],
        progressCounter: ProgressCounter
    ) async throws -> [ResolveResult] {
        try await withThrowingTaskGroup(of: ResolveResult.self) { group in
            for item in items {
                group.addTask {
                    try Task.checkCancellation()
                    do {
                        let track = try await self.resolveOne(recording: item.element)
                        await progressCounter.increment()
                        if let track {
                            return .resolved(track)
                        }
                        return .notFound
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

    private func resolveOne(recording: ArtistRecordingRel) async throws -> ResolvedTrack? {
        if let track = try await resolveViaISRC(recording: recording) {
            return track
        }
        return try await resolveViaTextSearch(recording: recording)
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
