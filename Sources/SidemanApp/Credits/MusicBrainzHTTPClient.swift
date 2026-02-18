import Foundation

actor MusicBrainzHTTPClient: MusicBrainzClient {
    private let session: URLSession
    private let baseURL: URL
    private let userAgent: String
    private let minIntervalSeconds: TimeInterval
    private let requestTimeout: TimeInterval
    private var lastRequestAt: Date?

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://musicbrainz.org/ws/2")!,
        userAgent: String = "Sideman/0.1 (https://github.com/jackson/sideman)",
        minIntervalSeconds: TimeInterval = 1.0,
        requestTimeout: TimeInterval = 10
    ) {
        self.session = session
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.minIntervalSeconds = minIntervalSeconds
        self.requestTimeout = requestTimeout
    }

    func searchRecordings(query: RecordingQuery) async throws -> [RecordingCandidate] {
        DebugLogger.log(
            .network,
            "searchRecordings title='\(query.title)' artist='\(query.artist)' album='\(query.album)'"
        )

        let queryString = buildQuery(title: query.title, artist: query.artist, album: query.album)
        let endpoint = Endpoint(
            path: "recording",
            queryItems: [
                URLQueryItem(name: "query", value: queryString),
                URLQueryItem(name: "fmt", value: "json"),
                URLQueryItem(name: "limit", value: "10")
            ]
        )

        let payload: RecordingSearchResponseDTO = try await request(endpoint: endpoint)
        DebugLogger.log(.network, "searchRecordings returned \(payload.recordings.count) candidates")

        return payload.recordings.map {
            RecordingCandidate(
                recordingMBID: $0.id,
                title: $0.title,
                artistNames: $0.artistCredit.map(\.name),
                releaseTitles: $0.releases.map(\.title),
                releaseIDs: $0.releases.map(\.id),
                musicBrainzScore: $0.score
            )
        }
    }

    func getRecording(id: String) async throws -> MBRecordingDetail {
        DebugLogger.log(.network, "getRecording id=\(id)")
        let endpoint = Endpoint(
            path: "recording/\(id)",
            queryItems: [
                URLQueryItem(name: "inc", value: "artist-rels+work-rels+releases"),
                URLQueryItem(name: "fmt", value: "json")
            ]
        )

        let payload: RecordingDetailDTO = try await request(endpoint: endpoint)

        return MBRecordingDetail(
            id: payload.id,
            title: payload.title,
            relations: payload.relations.map(toRelationship),
            releases: payload.releases.map { MBReleaseSummary(id: $0.id, title: $0.title) }
        )
    }

    func getWork(id: String) async throws -> MBWorkDetail {
        DebugLogger.log(.network, "getWork id=\(id)")
        let endpoint = Endpoint(
            path: "work/\(id)",
            queryItems: [
                URLQueryItem(name: "inc", value: "artist-rels"),
                URLQueryItem(name: "fmt", value: "json")
            ]
        )

        let payload: WorkDetailDTO = try await request(endpoint: endpoint)

        return MBWorkDetail(
            id: payload.id,
            title: payload.title,
            relations: payload.relations.map(toRelationship)
        )
    }

    func getRelease(id: String) async throws -> MBReleaseDetail {
        DebugLogger.log(.network, "getRelease id=\(id)")
        let endpoint = Endpoint(
            path: "release/\(id)",
            queryItems: [
                URLQueryItem(name: "inc", value: "artist-rels"),
                URLQueryItem(name: "fmt", value: "json")
            ]
        )

        let payload: ReleaseDetailDTO = try await request(endpoint: endpoint)

        return MBReleaseDetail(
            id: payload.id,
            title: payload.title,
            relations: payload.relations.map(toRelationship)
        )
    }

    func getArtistRecordingRels(id: String) async throws -> [ArtistRecordingRel] {
        DebugLogger.log(.network, "getArtistRecordingRels id=\(id)")
        let endpoint = Endpoint(
            path: "artist/\(id)",
            queryItems: [
                URLQueryItem(name: "inc", value: "recording-rels"),
                URLQueryItem(name: "fmt", value: "json")
            ]
        )

        let payload: ArtistRecordingRelsDTO = try await request(endpoint: endpoint)
        DebugLogger.log(.network, "getArtistRecordingRels returned \(payload.relations.count) relations")

        return payload.relations.compactMap { rel in
            guard let recording = rel.recording else { return nil }
            return ArtistRecordingRel(
                recordingMBID: recording.id,
                recordingTitle: recording.title,
                relationshipType: rel.type,
                attributes: rel.attributes,
                artistCredits: recording.artistCredit.map(\.name),
                isrcs: []
            )
        }
    }

    func browseRecordings(artistID: String, offset: Int, limit: Int, includeISRCs: Bool) async throws -> MBBrowseRecordingsPage {
        DebugLogger.log(.network, "browseRecordings artistID=\(artistID) offset=\(offset) limit=\(limit)")
        var incParts = ["artist-credits"]
        if includeISRCs {
            incParts.append("isrcs")
        }

        let endpoint = Endpoint(
            path: "recording",
            queryItems: [
                URLQueryItem(name: "artist", value: artistID),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "inc", value: incParts.joined(separator: "+")),
                URLQueryItem(name: "fmt", value: "json")
            ]
        )

        let payload: BrowseRecordingsDTO = try await request(endpoint: endpoint)
        DebugLogger.log(.network, "browseRecordings returned \(payload.recordings.count)/\(payload.recordingCount) recordings")

        let recordings = payload.recordings.map { rec in
            ArtistRecordingRel(
                recordingMBID: rec.id,
                recordingTitle: rec.title,
                relationshipType: "main",
                attributes: [],
                artistCredits: rec.artistCredit.map(\.name),
                isrcs: rec.isrcs
            )
        }

        return MBBrowseRecordingsPage(
            recordings: recordings,
            totalCount: payload.recordingCount,
            offset: payload.recordingOffset
        )
    }

    func getRecordingISRCs(id: String) async throws -> [String] {
        DebugLogger.log(.network, "getRecordingISRCs id=\(id)")
        let endpoint = Endpoint(
            path: "recording/\(id)",
            queryItems: [
                URLQueryItem(name: "inc", value: "isrcs"),
                URLQueryItem(name: "fmt", value: "json")
            ]
        )

        let payload: RecordingISRCsDTO = try await request(endpoint: endpoint)
        DebugLogger.log(.network, "getRecordingISRCs returned \(payload.isrcs.count) ISRCs")
        return payload.isrcs
    }

    func searchArtists(name: String) async throws -> [MBArtistSearchResult] {
        DebugLogger.log(.network, "searchArtists name='\(name)'")
        let escapedName = escapeQueryValue(name)
        let endpoint = Endpoint(
            path: "artist",
            queryItems: [
                URLQueryItem(name: "query", value: "artist:\"\(escapedName)\""),
                URLQueryItem(name: "fmt", value: "json"),
                URLQueryItem(name: "limit", value: "3")
            ]
        )

        let payload: ArtistSearchResponseDTO = try await request(endpoint: endpoint)
        DebugLogger.log(.network, "searchArtists returned \(payload.artists.count) results")

        return payload.artists.map {
            MBArtistSearchResult(id: $0.id, name: $0.name, score: $0.score)
        }
    }

    private func request<T: Decodable>(endpoint: Endpoint, attempt: Int = 0) async throws -> T {
        await paceRequests()

        let url = endpoint.url(relativeTo: baseURL)
        DebugLogger.log(.network, "request \(url.absoluteString) attempt=\(attempt + 1)")

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = requestTimeout
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw MusicBrainzClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MusicBrainzClientError.network("Non-HTTP response")
        }

        switch http.statusCode {
        case 200:
            DebugLogger.log(.network, "response 200 for \(url.path)")
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                DebugLogger.log(.network, "decode failure for \(url.path): \(error.localizedDescription)")
                throw MusicBrainzClientError.decoding(error.localizedDescription)
            }
        case 404:
            DebugLogger.log(.network, "response 404 for \(url.path)")
            throw MusicBrainzClientError.notFound
        case 429, 503:
            if attempt < 3 {
                let retryDelay = retryDelay(for: http, attempt: attempt)
                DebugLogger.log(.network, "response \(http.statusCode) retrying in \(String(format: "%.2f", retryDelay))s for \(url.path)")
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                return try await request(endpoint: endpoint, attempt: attempt + 1)
            }
            if http.statusCode == 429 {
                DebugLogger.log(.network, "response 429 rate limited for \(url.path)")
                throw MusicBrainzClientError.rateLimited
            }
            DebugLogger.log(.network, "response \(http.statusCode) for \(url.path)")
            throw MusicBrainzClientError.httpStatus(http.statusCode)
        default:
            DebugLogger.log(.network, "response \(http.statusCode) for \(url.path)")
            throw MusicBrainzClientError.httpStatus(http.statusCode)
        }
    }

    private func retryDelay(for response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(retryAfter),
           seconds > 0 {
            return seconds
        }

        let base = 0.5
        return base * pow(2, Double(attempt))
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

    private func buildQuery(title: String, artist: String, album: String) -> String {
        let escapedTitle = escapeQueryValue(title)
        let escapedArtist = escapeQueryValue(artist)
        let escapedAlbum = escapeQueryValue(album)

        if escapedAlbum.isEmpty {
            return "recording:\"\(escapedTitle)\" AND artist:\"\(escapedArtist)\""
        }

        return "recording:\"\(escapedTitle)\" AND artist:\"\(escapedArtist)\" AND release:\"\(escapedAlbum)\""
    }

    private func escapeQueryValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toRelationship(_ dto: RelationshipDTO) -> MBRelationship {
        MBRelationship(
            type: dto.type,
            targetType: dto.targetType,
            attributes: dto.attributes,
            artist: dto.artist.map { MBArtist(id: $0.id, name: $0.name) },
            work: dto.work.map { MBWorkReference(id: $0.id, title: $0.title) }
        )
    }
}

private struct Endpoint {
    let path: String
    let queryItems: [URLQueryItem]

    func url(relativeTo baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        return components.url!
    }
}

private struct RecordingSearchResponseDTO: Decodable {
    let recordings: [RecordingCandidateDTO]
}

private struct RecordingCandidateDTO: Decodable {
    let id: String
    let title: String
    let score: Int
    let artistCredit: [ArtistCreditDTO]
    let releases: [ReleaseSummaryDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case score
        case artistCredit = "artist-credit"
        case releases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        artistCredit = try container.decodeIfPresent([ArtistCreditDTO].self, forKey: .artistCredit) ?? []
        releases = try container.decodeIfPresent([ReleaseSummaryDTO].self, forKey: .releases) ?? []

        if let intScore = try? container.decode(Int.self, forKey: .score) {
            score = intScore
        } else if let stringScore = try? container.decode(String.self, forKey: .score),
                  let intScore = Int(stringScore) {
            score = intScore
        } else {
            score = 0
        }
    }
}

private struct ArtistCreditDTO: Decodable {
    let name: String
}

private struct ReleaseSummaryDTO: Decodable {
    let id: String
    let title: String
}

private struct RecordingDetailDTO: Decodable {
    let id: String
    let title: String
    let relations: [RelationshipDTO]
    let releases: [ReleaseSummaryDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case relations
        case releases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        relations = try container.decodeIfPresent([RelationshipDTO].self, forKey: .relations) ?? []
        releases = try container.decodeIfPresent([ReleaseSummaryDTO].self, forKey: .releases) ?? []
    }
}

private struct WorkDetailDTO: Decodable {
    let id: String
    let title: String
    let relations: [RelationshipDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case relations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        relations = try container.decodeIfPresent([RelationshipDTO].self, forKey: .relations) ?? []
    }
}

private struct ReleaseDetailDTO: Decodable {
    let id: String
    let title: String
    let relations: [RelationshipDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case relations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        relations = try container.decodeIfPresent([RelationshipDTO].self, forKey: .relations) ?? []
    }
}

private struct RelationshipDTO: Decodable {
    let type: String
    let targetType: String?
    let attributes: [String]
    let artist: ArtistDTO?
    let work: WorkReferenceDTO?

    enum CodingKeys: String, CodingKey {
        case type
        case targetType = "target-type"
        case attributes
        case artist
        case work
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
        targetType = try container.decodeIfPresent(String.self, forKey: .targetType)
        attributes = try container.decodeIfPresent([String].self, forKey: .attributes) ?? []
        artist = try container.decodeIfPresent(ArtistDTO.self, forKey: .artist)
        work = try container.decodeIfPresent(WorkReferenceDTO.self, forKey: .work)
    }
}

private struct ArtistDTO: Decodable {
    let id: String?
    let name: String
}

private struct WorkReferenceDTO: Decodable {
    let id: String
    let title: String
}

// MARK: - Artist Recording Rels DTOs

private struct ArtistRecordingRelsDTO: Decodable {
    let relations: [ArtistRelationDTO]

    enum CodingKeys: String, CodingKey {
        case relations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relations = try container.decodeIfPresent([ArtistRelationDTO].self, forKey: .relations) ?? []
    }
}

private struct ArtistRelationDTO: Decodable {
    let type: String
    let attributes: [String]
    let recording: RecordingRefDTO?

    enum CodingKeys: String, CodingKey {
        case type
        case attributes
        case recording
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
        attributes = try container.decodeIfPresent([String].self, forKey: .attributes) ?? []
        recording = try container.decodeIfPresent(RecordingRefDTO.self, forKey: .recording)
    }
}

private struct RecordingRefDTO: Decodable {
    let id: String
    let title: String
    let artistCredit: [ArtistCreditDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case artistCredit = "artist-credit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        artistCredit = try container.decodeIfPresent([ArtistCreditDTO].self, forKey: .artistCredit) ?? []
    }
}

// MARK: - Browse Recordings DTOs

private struct BrowseRecordingsDTO: Decodable {
    let recordings: [BrowseRecordingDTO]
    let recordingCount: Int
    let recordingOffset: Int

    enum CodingKeys: String, CodingKey {
        case recordings
        case recordingCount = "recording-count"
        case recordingOffset = "recording-offset"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordings = try container.decodeIfPresent([BrowseRecordingDTO].self, forKey: .recordings) ?? []
        recordingCount = try container.decodeIfPresent(Int.self, forKey: .recordingCount) ?? 0
        recordingOffset = try container.decodeIfPresent(Int.self, forKey: .recordingOffset) ?? 0
    }
}

private struct BrowseRecordingDTO: Decodable {
    let id: String
    let title: String
    let artistCredit: [ArtistCreditDTO]
    let isrcs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case artistCredit = "artist-credit"
        case isrcs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        artistCredit = try container.decodeIfPresent([ArtistCreditDTO].self, forKey: .artistCredit) ?? []
        isrcs = try container.decodeIfPresent([String].self, forKey: .isrcs) ?? []
    }
}

// MARK: - Recording ISRCs DTO

private struct RecordingISRCsDTO: Decodable {
    let isrcs: [String]

    enum CodingKeys: String, CodingKey {
        case isrcs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isrcs = try container.decodeIfPresent([String].self, forKey: .isrcs) ?? []
    }
}

// MARK: - Artist Search DTOs

private struct ArtistSearchResponseDTO: Decodable {
    let artists: [ArtistSearchResultDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artists = try container.decodeIfPresent([ArtistSearchResultDTO].self, forKey: .artists) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case artists
    }
}

private struct ArtistSearchResultDTO: Decodable {
    let id: String
    let name: String
    let score: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        if let intScore = try? container.decode(Int.self, forKey: .score) {
            score = intScore
        } else if let stringScore = try? container.decode(String.self, forKey: .score),
                  let intScore = Int(stringScore) {
            score = intScore
        } else {
            score = 0
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case score
    }
}
