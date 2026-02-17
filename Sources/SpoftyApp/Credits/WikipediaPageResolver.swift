import Foundation

actor DefaultWikipediaPageResolver: WikipediaPageResolver {
    private let client: WikipediaAPIClient
    private let normalizationOptions: TextNormalizationOptions = [.stripParentheticalText, .alphanumericsOnly, .collapseWhitespace]
    // Resolver keeps a middle-ground substring bonus because Wikipedia titles often append descriptors.
    private let containsMatchScore: Double = 0.87

    init(client: WikipediaAPIClient) {
        self.client = client
    }

    func resolvePage(for track: NowPlayingTrack) async -> Result<WikipediaPageResolution, ResolverError> {
        DebugLogger.log(.resolver, "wikipedia resolve start album='\(track.album)' artist='\(track.artist)'")

        let primaryQuery = buildPrimaryQuery(track: track)
        let fallbackQuery = buildFallbackQuery(track: track)

        do {
            var results = try await client.searchPages(query: primaryQuery, limit: 10)

            if results.isEmpty, fallbackQuery != primaryQuery {
                results = try await client.searchPages(query: fallbackQuery, limit: 10)
            }

            guard !results.isEmpty else {
                DebugLogger.log(.resolver, "wikipedia resolve result=notFound")
                return .failure(.notFound)
            }

            let scored = results.map {
                ScoredWikiPage(result: $0, score: score(result: $0, track: track))
            }
            .sorted { $0.score > $1.score }

            guard let best = scored.first else {
                return .failure(.notFound)
            }

            let secondScore = scored.dropFirst().first?.score ?? 0
            let margin = best.score - secondScore
            DebugLogger.log(
                .resolver,
                "wikipedia candidate pageID=\(best.result.pageID) title='\(best.result.title)' score=\(String(format: "%.3f", best.score)) margin=\(String(format: "%.3f", margin))"
            )

            if best.score < 0.45 {
                return .failure(.notFound)
            }

            if best.score >= 0.60, secondScore >= 0.55, margin < 0.07 {
                return .failure(.ambiguous)
            }

            let resolution = WikipediaPageResolution(pageID: best.result.pageID, title: best.result.title, confidence: best.score)
            return .success(resolution)
        } catch let error as WikipediaClientError {
            switch error {
            case .rateLimited:
                return .failure(.rateLimited)
            case .notFound:
                return .failure(.notFound)
            case .httpStatus, .decoding, .network:
                return .failure(.network(String(describing: error)))
            }
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    private func buildPrimaryQuery(track: NowPlayingTrack) -> String {
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)

        if !album.isEmpty, !artist.isEmpty {
            return "\(album) \(artist) album"
        }

        if !album.isEmpty {
            return "\(album) album"
        }

        return "\(track.title) \(artist) song"
    }

    private func buildFallbackQuery(track: NowPlayingTrack) -> String {
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        if !album.isEmpty {
            return "\(album) album"
        }

        return "\(track.title) \(track.artist)"
    }

    private func score(result: WikipediaSearchResult, track: NowPlayingTrack) -> Double {
        let normalizedTitle = CreditsTextNormalizer.normalize(result.title, options: normalizationOptions)
        let normalizedAlbum = CreditsTextNormalizer.normalize(track.album, options: normalizationOptions)
        let normalizedArtist = CreditsTextNormalizer.normalize(track.artist, options: normalizationOptions)
        let normalizedSnippet = CreditsTextNormalizer.normalize(result.snippet, options: normalizationOptions)
        let rawLowerTitle = result.title.lowercased()

        let titleSimilarity = CreditsTextSimilarity.jaccardSimilarity(
            normalizedTitle,
            normalizedAlbum,
            containsMatchScore: containsMatchScore
        )
        let albumTagBoost = normalizedTitle.contains("album") ? 0.12 : 0
        let disambiguationBoost = rawLowerTitle.contains("(album)") ? 0.18 : 0
        let artistBoost = !normalizedArtist.isEmpty && normalizedSnippet.contains(normalizedArtist) ? 0.18 : 0

        return min(1.0, titleSimilarity + albumTagBoost + disambiguationBoost + artistBoost)
    }
}

private struct ScoredWikiPage {
    let result: WikipediaSearchResult
    let score: Double
}
