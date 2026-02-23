import Foundation

actor DiscogsHTTPClient: DiscogsClient {
    private let session: URLSession
    private let baseURL: URL
    private let token: String
    private let userAgent: String
    private let minIntervalSeconds: TimeInterval
    private let requestTimeout: TimeInterval
    private var lastRequestAt: Date?

    private let titleNormalization: TextNormalizationOptions = [
        .stripFeaturingSuffix,
        .stripParentheticalText,
        .alphanumericsOnly,
        .collapseWhitespace
    ]

    init(
        token: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.discogs.com")!,
        userAgent: String = "Sideman/0.1 (https://github.com/jackson/sideman)",
        minIntervalSeconds: TimeInterval = 0.5,
        requestTimeout: TimeInterval = 10
    ) {
        self.token = token
        self.session = session
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.minIntervalSeconds = minIntervalSeconds
        self.requestTimeout = requestTimeout
    }

    func artistHintsForTrack(title: String, artistHints: [String], limit: Int) async throws -> [String] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return []
        }

        let targetNormalized = normalizeTrackTitle(trimmedTitle)
        guard !targetNormalized.isEmpty else {
            return []
        }

        let cleanedHints = cleanArtistHints(artistHints)
        let primaryHint = cleanedHints.first
        let candidateReleaseIDs = try await searchReleaseIDs(
            title: trimmedTitle,
            artistHint: primaryHint,
            limit: max(6, min(limit * 3, 12))
        )
        guard !candidateReleaseIDs.isEmpty else {
            return []
        }

        var counts: [String: Int] = [:]
        var order: [String] = []

        for releaseID in candidateReleaseIDs.prefix(3) {
            do {
                let release = try await fetchRelease(id: releaseID)
                let matchedTracks = release.tracklist.filter { track in
                    guard let trackTitle = track.title else {
                        return false
                    }
                    let normalized = normalizeTrackTitle(trackTitle)
                    guard !normalized.isEmpty else {
                        return false
                    }
                    let similarity = CreditsTextSimilarity.jaccardSimilarity(
                        targetNormalized,
                        normalized,
                        containsMatchScore: 0.96
                    )
                    return similarity >= 0.84
                }
                if matchedTracks.isEmpty {
                    continue
                }

                let candidateArtists = artistNames(from: matchedTracks, releaseArtists: release.artists)
                for artist in candidateArtists {
                    let key = artist.lowercased()
                    if counts[key] == nil {
                        order.append(artist)
                    }
                    counts[key, default: 0] += 1
                }
            } catch let error as DiscogsClientError where error == .rateLimited {
                throw error
            } catch {
                DebugLogger.log(.provider, "discogs release lookup failed id=\(releaseID): \(error)")
            }
        }

        if counts.isEmpty {
            return []
        }

        let rankIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1.lowercased(), $0) })
        let sorted = counts.keys.sorted { lhs, rhs in
            let lhsCount = counts[lhs] ?? 0
            let rhsCount = counts[rhs] ?? 0
            if lhsCount == rhsCount {
                return (rankIndex[lhs] ?? Int.max) < (rankIndex[rhs] ?? Int.max)
            }
            return lhsCount > rhsCount
        }

        let resolvedNames = sorted.compactMap { key in
            order.first { $0.lowercased() == key }
        }
        return Array(resolvedNames.prefix(max(1, limit)))
    }

    private func searchReleaseIDs(title: String, artistHint: String?, limit: Int) async throws -> [Int] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "track", value: title),
            URLQueryItem(name: "per_page", value: String(limit)),
            URLQueryItem(name: "page", value: "1")
        ]
        if let artistHint, !artistHint.isEmpty {
            queryItems.append(URLQueryItem(name: "artist", value: artistHint))
        }

        let endpoint = DiscogsEndpoint(path: "database/search", queryItems: queryItems)
        let payload: DiscogsSearchResponseDTO = try await request(endpoint: endpoint)

        var ids: [Int] = []
        var seen = Set<Int>()
        for result in payload.results {
            guard let id = result.id else {
                continue
            }
            if seen.insert(id).inserted {
                ids.append(id)
            }
        }
        DebugLogger.log(.network, "discogs search title='\(title)' artist='\(artistHint ?? "")' releases=\(ids.count)")
        return ids
    }

    private func fetchRelease(id: Int) async throws -> DiscogsReleaseDTO {
        let endpoint = DiscogsEndpoint(path: "releases/\(id)", queryItems: [])
        return try await request(endpoint: endpoint)
    }

    private func request<T: Decodable>(endpoint: DiscogsEndpoint, attempt: Int = 0) async throws -> T {
        await paceRequests()

        let url = endpoint.url(relativeTo: baseURL)
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = requestTimeout
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw DiscogsClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DiscogsClientError.network("Non-HTTP response")
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw DiscogsClientError.decoding(error.localizedDescription)
            }
        case 401, 403:
            throw DiscogsClientError.unauthorized
        case 429:
            if attempt < 2 {
                let delay = retryDelay(for: http, attempt: attempt)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await request(endpoint: endpoint, attempt: attempt + 1)
            }
            throw DiscogsClientError.rateLimited
        default:
            throw DiscogsClientError.httpStatus(http.statusCode)
        }
    }

    private func paceRequests() async {
        if let lastRequestAt {
            let elapsed = Date().timeIntervalSince(lastRequestAt)
            if elapsed < minIntervalSeconds {
                let remaining = minIntervalSeconds - elapsed
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        lastRequestAt = Date()
    }

    private func retryDelay(for response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(retryAfter),
           seconds > 0 {
            return seconds
        }
        return 0.5 * pow(2, Double(attempt))
    }

    private func artistNames(from tracks: [DiscogsTrackDTO], releaseArtists: [DiscogsArtistDTO]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        for track in tracks {
            let names = track.artists?.compactMap { cleanedArtistName($0.name) } ?? []
            for name in names where seen.insert(name.lowercased()).inserted {
                ordered.append(name)
            }
        }

        if ordered.isEmpty {
            for releaseArtist in releaseArtists {
                if let name = cleanedArtistName(releaseArtist.name), seen.insert(name.lowercased()).inserted {
                    ordered.append(name)
                }
            }
        }

        return ordered
    }

    private func cleanArtistHints(_ hints: [String]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for hint in hints {
            guard let cleaned = cleanedArtistName(hint), seen.insert(cleaned.lowercased()).inserted else {
                continue
            }
            ordered.append(cleaned)
        }
        return ordered
    }

    private func cleanedArtistName(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value
            .replacingOccurrences(of: #" \(\d+\)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func normalizeTrackTitle(_ title: String) -> String {
        CreditsTextNormalizer.normalize(title, options: titleNormalization)
    }
}

private struct DiscogsEndpoint {
    let path: String
    let queryItems: [URLQueryItem]

    func url(relativeTo baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }
}

private struct DiscogsSearchResponseDTO: Decodable {
    let results: [DiscogsSearchResultDTO]

    enum CodingKeys: String, CodingKey {
        case results
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeIfPresent([DiscogsSearchResultDTO].self, forKey: .results) ?? []
    }
}

private struct DiscogsSearchResultDTO: Decodable {
    let id: Int?

    enum CodingKeys: String, CodingKey {
        case id
    }
}

private struct DiscogsReleaseDTO: Decodable {
    let artists: [DiscogsArtistDTO]
    let tracklist: [DiscogsTrackDTO]

    enum CodingKeys: String, CodingKey {
        case artists
        case tracklist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artists = try container.decodeIfPresent([DiscogsArtistDTO].self, forKey: .artists) ?? []
        tracklist = try container.decodeIfPresent([DiscogsTrackDTO].self, forKey: .tracklist) ?? []
    }
}

private struct DiscogsArtistDTO: Decodable {
    let name: String?
}

private struct DiscogsTrackDTO: Decodable {
    let title: String?
    let artists: [DiscogsArtistDTO]?
}
