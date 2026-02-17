import Foundation

actor DefaultTrackResolver: TrackResolver {
    private let client: MusicBrainzClient
    private let confidenceThreshold: Double
    private let minimumMargin: Double

    init(client: MusicBrainzClient, confidenceThreshold: Double = 0.78, minimumMargin: Double = 0.10) {
        self.client = client
        self.confidenceThreshold = confidenceThreshold
        self.minimumMargin = minimumMargin
    }

    func resolve(_ track: NowPlayingTrack) async -> Result<ResolutionResult, ResolverError> {
        do {
            let primaryQuery = RecordingQuery(title: track.title, artist: track.artist, album: track.album)
            var candidates = try await client.searchRecordings(query: primaryQuery)

            if candidates.isEmpty, !track.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let fallbackQuery = RecordingQuery(title: track.title, artist: track.artist, album: "")
                candidates = try await client.searchRecordings(query: fallbackQuery)
            }

            guard !candidates.isEmpty else {
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

            guard best.score >= confidenceThreshold, margin >= minimumMargin else {
                return .failure(.ambiguous)
            }

            let releaseMBID = selectReleaseID(from: best.candidate, album: track.album)

            return .success(
                ResolutionResult(
                    recordingMBID: best.candidate.recordingMBID,
                    releaseMBID: releaseMBID,
                    workMBIDs: [],
                    confidence: best.score
                )
            )
        } catch let clientError as MusicBrainzClientError {
            switch clientError {
            case .notFound:
                return .failure(.notFound)
            case .rateLimited:
                return .failure(.rateLimited)
            case .httpStatus, .decoding, .network:
                return .failure(.network(String(describing: clientError)))
            }
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    private func score(candidate: RecordingCandidate, track: NowPlayingTrack) -> Double {
        let mbScore = min(max(Double(candidate.musicBrainzScore) / 100.0, 0), 1)
        let titleScore = similarity(candidate.title, track.title)

        let candidateArtist = candidate.artistNames.joined(separator: " ")
        let artistScore = similarity(candidateArtist, track.artist)

        let albumScore: Double
        if track.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            albumScore = 0.6
        } else {
            albumScore = candidate.releaseTitles.map { similarity($0, track.album) }.max() ?? 0
        }

        return (0.45 * mbScore) + (0.30 * titleScore) + (0.20 * artistScore) + (0.05 * albumScore)
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = normalize(lhs)
        let b = normalize(rhs)

        guard !a.isEmpty, !b.isEmpty else {
            return 0
        }

        if a == b {
            return 1
        }

        if a.contains(b) || b.contains(a) {
            return 0.88
        }

        let leftTokens = Set(a.split(separator: " ").map(String.init))
        let rightTokens = Set(b.split(separator: " ").map(String.init))

        guard !leftTokens.isEmpty, !rightTokens.isEmpty else {
            return 0
        }

        let intersection = leftTokens.intersection(rightTokens).count
        let union = leftTokens.union(rightTokens).count

        guard union > 0 else {
            return 0
        }

        return Double(intersection) / Double(union)
    }

    private func normalize(_ value: String) -> String {
        var cleaned = value.lowercased()
        if let range = cleaned.range(of: #"\b(feat\.?|featuring)\b.*$"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }

        let scalarView = cleaned.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }

        let normalized = String(scalarView)
            .split(separator: " ")
            .map(String.init)
            .joined(separator: " ")

        return normalized
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
            similarity(lhs.1, album) < similarity(rhs.1, album)
        }

        return best?.0 ?? candidate.releaseIDs.first
    }
}

private struct ScoredCandidate {
    let candidate: RecordingCandidate
    let score: Double
}
