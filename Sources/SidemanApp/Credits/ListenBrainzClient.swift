import Foundation

actor ListenBrainzClient {
    private let session: URLSession
    private let baseURL: URL
    private let minIntervalSeconds: TimeInterval
    private var lastRequestAt: Date?

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.listenbrainz.org/1")!,
        minIntervalSeconds: TimeInterval = 1.0
    ) {
        self.session = session
        self.baseURL = baseURL
        self.minIntervalSeconds = minIntervalSeconds
    }

    func recordingPopularity(mbids: [String]) async throws -> [RecordingPopularity] {
        DebugLogger.log(.network, "ListenBrainz recordingPopularity count=\(mbids.count)")

        var allResults: [RecordingPopularity] = []
        let batchSize = 1000

        for batchStart in stride(from: 0, to: mbids.count, by: batchSize) {
            try Task.checkCancellation()
            let batchEnd = min(batchStart + batchSize, mbids.count)
            let batch = Array(mbids[batchStart..<batchEnd])

            await paceRequests()

            let url = baseURL.appendingPathComponent("popularity/recording")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let body = ["recording_mbids": batch]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await performRequest(request)

            guard let http = response as? HTTPURLResponse else {
                throw MusicBrainzClientError.network("Non-HTTP response from ListenBrainz")
            }

            guard http.statusCode == 200 else {
                if http.statusCode == 429 {
                    DebugLogger.log(.network, "ListenBrainz rate limited")
                    throw MusicBrainzClientError.rateLimited
                }
                throw MusicBrainzClientError.httpStatus(http.statusCode)
            }

            let items = try JSONDecoder().decode([ListenBrainzPopularityDTO].self, from: data)
            let results = items.map {
                RecordingPopularity(recordingMBID: $0.recordingMBID, listenCount: $0.totalListenCount)
            }
            allResults.append(contentsOf: results)
        }

        DebugLogger.log(.network, "ListenBrainz recordingPopularity returned \(allResults.count) results")
        return allResults
    }

    func topRecordingsForArtist(artistMBID: String) async throws -> [RecordingPopularity] {
        DebugLogger.log(.network, "ListenBrainz topRecordingsForArtist \(artistMBID)")

        await paceRequests()

        let url = baseURL.appendingPathComponent("popularity/top-recordings-for-artist/\(artistMBID)")
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)

        guard let http = response as? HTTPURLResponse else {
            throw MusicBrainzClientError.network("Non-HTTP response from ListenBrainz")
        }

        guard http.statusCode == 200 else {
            if http.statusCode == 429 {
                throw MusicBrainzClientError.rateLimited
            }
            throw MusicBrainzClientError.httpStatus(http.statusCode)
        }

        let items = try JSONDecoder().decode([ListenBrainzPopularityDTO].self, from: data)
        DebugLogger.log(.network, "ListenBrainz topRecordings returned \(items.count) results")

        return items.map {
            RecordingPopularity(recordingMBID: $0.recordingMBID, listenCount: $0.totalListenCount)
        }
    }

    private func performRequest(_ request: URLRequest, attempt: Int = 0) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            if attempt < 2 {
                let delay = 0.5 * pow(2, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequest(request, attempt: attempt + 1)
            }
            throw MusicBrainzClientError.network(error.localizedDescription)
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
}

private struct ListenBrainzPopularityDTO: Decodable {
    let recordingMBID: String
    let totalListenCount: Int?

    enum CodingKeys: String, CodingKey {
        case recordingMBID = "recording_mbid"
        case totalListenCount = "total_listen_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordingMBID = try container.decode(String.self, forKey: .recordingMBID)
        totalListenCount = try container.decodeIfPresent(Int.self, forKey: .totalListenCount)
    }
}
