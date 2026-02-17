import Foundation

actor DefaultTrackResolver: TrackResolver {
    private let client: MusicBrainzClient
    private let confidenceThreshold: Double
    private let minimumMargin: Double
    private let normalizationOptions: TextNormalizationOptions = [.stripFeaturingSuffix, .alphanumericsOnly, .collapseWhitespace]
    // Track resolver intentionally favors substring matches slightly more to handle release title variants.
    private let containsMatchScore: Double = 0.88

    init(client: MusicBrainzClient, confidenceThreshold: Double = 0.78, minimumMargin: Double = 0.10) {
        self.client = client
        self.confidenceThreshold = confidenceThreshold
        self.minimumMargin = minimumMargin
    }

    func resolve(_ track: NowPlayingTrack) async -> Result<ResolutionResult, ResolverError> {
        DebugLogger.log(.resolver, "resolve start '\(track.title)' by '\(track.artist)' [album='\(track.album)']")

        do {
            let primaryQuery = RecordingQuery(title: track.title, artist: track.artist, album: track.album)
            var candidates = try await client.searchRecordings(query: primaryQuery)
            DebugLogger.log(.resolver, "primary query candidates=\(candidates.count)")

            if candidates.isEmpty, !track.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let fallbackQuery = RecordingQuery(title: track.title, artist: track.artist, album: "")
                candidates = try await client.searchRecordings(query: fallbackQuery)
                DebugLogger.log(.resolver, "fallback query candidates=\(candidates.count)")
            }

            guard !candidates.isEmpty else {
                DebugLogger.log(.resolver, "resolve result=notFound")
                return .failure(.notFound)
            }

            let scored = candidates.map { candidate in
                ScoredCandidate(candidate: candidate, score: score(candidate: candidate, track: track))
            }
            .sorted { $0.score > $1.score }

            guard let best = scored.first else {
                return .failure(.notFound)
            }

            let secondScore = scored.dropFirst().first?.score ?? 0
            let margin = best.score - secondScore
            DebugLogger.log(
                .resolver,
                "top candidate id=\(best.candidate.recordingMBID) score=\(String(format: "%.3f", best.score)) margin=\(String(format: "%.3f", margin))"
            )

            guard best.score >= confidenceThreshold, margin >= minimumMargin else {
                DebugLogger.log(
                    .resolver,
                    "resolve result=ambiguous (threshold=\(String(format: "%.2f", confidenceThreshold)) marginMin=\(String(format: "%.2f", minimumMargin)))"
                )
                return .failure(.ambiguous)
            }

            let releaseMBID = selectReleaseID(from: best.candidate, album: track.album)

            let success = ResolutionResult(
                recordingMBID: best.candidate.recordingMBID,
                releaseMBID: releaseMBID,
                workMBIDs: [],
                confidence: best.score
            )

            DebugLogger.log(
                .resolver,
                "resolve result=success recording=\(success.recordingMBID) release=\(success.releaseMBID ?? "nil")"
            )

            return .success(
                ResolutionResult(
                    recordingMBID: success.recordingMBID,
                    releaseMBID: success.releaseMBID,
                    workMBIDs: success.workMBIDs,
                    confidence: success.confidence
                )
            )
        } catch let clientError as MusicBrainzClientError {
            switch clientError {
            case .notFound:
                DebugLogger.log(.resolver, "resolve client error=notFound")
                return .failure(.notFound)
            case .rateLimited:
                DebugLogger.log(.resolver, "resolve client error=rateLimited")
                return .failure(.rateLimited)
            case .httpStatus, .decoding, .network:
                DebugLogger.log(.resolver, "resolve client error=\(String(describing: clientError))")
                return .failure(.network(String(describing: clientError)))
            }
        } catch {
            DebugLogger.log(.resolver, "resolve error=\(error.localizedDescription)")
            return .failure(.network(error.localizedDescription))
        }
    }

    private func score(candidate: RecordingCandidate, track: NowPlayingTrack) -> Double {
        let mbScore = min(max(Double(candidate.musicBrainzScore) / 100.0, 0), 1)
        let titleScore = similarityScore(candidate.title, track.title)

        let candidateArtist = candidate.artistNames.joined(separator: " ")
        let artistScore = similarityScore(candidateArtist, track.artist)

        let albumScore: Double
        if track.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            albumScore = 0.6
        } else {
            albumScore = candidate.releaseTitles.map { similarityScore($0, track.album) }.max() ?? 0
        }

        return (0.45 * mbScore) + (0.30 * titleScore) + (0.20 * artistScore) + (0.05 * albumScore)
    }

    private func similarityScore(_ lhs: String, _ rhs: String) -> Double {
        let normalizedLeft = CreditsTextNormalizer.normalize(lhs, options: normalizationOptions)
        let normalizedRight = CreditsTextNormalizer.normalize(rhs, options: normalizationOptions)
        return CreditsTextSimilarity.jaccardSimilarity(
            normalizedLeft,
            normalizedRight,
            containsMatchScore: containsMatchScore
        )
    }

    private func selectReleaseID(from candidate: RecordingCandidate, album: String) -> String? {
        guard !candidate.releaseIDs.isEmpty else {
            return nil
        }

        if album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return candidate.releaseIDs.first
        }

        let paired = zip(candidate.releaseIDs, candidate.releaseTitles)
        let best = paired.max { lhs, rhs in
            similarityScore(lhs.1, album) < similarityScore(rhs.1, album)
        }

        return best?.0 ?? candidate.releaseIDs.first
    }
}

private struct ScoredCandidate {
    let candidate: RecordingCandidate
    let score: Double
}
