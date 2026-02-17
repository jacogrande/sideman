import Foundation

actor WikipediaAPIClientImpl: WikipediaAPIClient {
    private let session: URLSession
    private let apiURL: URL
    private let userAgent: String
    private let minIntervalSeconds: TimeInterval
    private let requestTimeout: TimeInterval
    private var lastRequestAt: Date?

    private static let htmlTagRegex = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    private static let numericEntityRegex = try! NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#)
    private static let whitespaceRegex = try! NSRegularExpression(pattern: #"\s+"#)
    private static let namedEntities: [String: String] = [
        "&quot;": "\"",
        "&apos;": "'",
        "&#39;": "'",
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&nbsp;": " ",
        "&ndash;": "-",
        "&mdash;": "--",
        "&hellip;": "..."
    ]

    init(
        session: URLSession = .shared,
        apiURL: URL = URL(string: "https://en.wikipedia.org/w/api.php")!,
        userAgent: String = "Sideman/0.1 (https://github.com/jackson/sideman)",
        minIntervalSeconds: TimeInterval = 0.4,
        requestTimeout: TimeInterval = 12
    ) {
        self.session = session
        self.apiURL = apiURL
        self.userAgent = userAgent
        self.minIntervalSeconds = minIntervalSeconds
        self.requestTimeout = requestTimeout
    }

    func searchPages(query: String, limit: Int = 8) async throws -> [WikipediaSearchResult] {
        DebugLogger.log(.network, "wikipedia search query='\(query)' limit=\(limit)")

        let payload: WikipediaSearchResponseDTO = try await request(
            queryItems: [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "list", value: "search"),
                URLQueryItem(name: "srsearch", value: query),
                URLQueryItem(name: "srlimit", value: String(limit)),
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "utf8", value: "1")
            ]
        )

        let results = payload.query.search.map {
            WikipediaSearchResult(
                pageID: $0.pageID,
                title: $0.title,
                snippet: stripHTML($0.snippet)
            )
        }

        DebugLogger.log(.network, "wikipedia search results=\(results.count)")
        return results
    }

    func fetchPage(pageID: Int) async throws -> WikipediaPageContent {
        DebugLogger.log(.network, "wikipedia fetch pageID=\(pageID)")

        let payload: WikipediaPageResponseDTO = try await request(
            queryItems: [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "prop", value: "revisions|info"),
                URLQueryItem(name: "pageids", value: String(pageID)),
                URLQueryItem(name: "rvprop", value: "content"),
                URLQueryItem(name: "rvslots", value: "main"),
                URLQueryItem(name: "inprop", value: "url"),
                URLQueryItem(name: "formatversion", value: "2"),
                URLQueryItem(name: "format", value: "json")
            ]
        )

        guard let page = payload.query.pages.first,
              !page.missing,
              let content = page.revisions.first?.wikitext,
              !content.isEmpty else {
            throw WikipediaClientError.notFound
        }

        return WikipediaPageContent(
            pageID: page.pageID,
            title: page.title,
            fullURL: page.fullURL,
            wikitext: content
        )
    }

    private func request<T: Decodable>(queryItems: [URLQueryItem], attempt: Int = 0) async throws -> T {
        await paceRequests()

        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        guard let url = components.url else {
            throw WikipediaClientError.network("Could not build wikipedia request URL")
        }

        DebugLogger.log(.network, "wikipedia request \(url.absoluteString) attempt=\(attempt + 1)")

        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WikipediaClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WikipediaClientError.network("Non-HTTP response")
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw WikipediaClientError.decoding(error.localizedDescription)
            }
        case 404:
            throw WikipediaClientError.notFound
        case 429, 503:
            if attempt < 3 {
                let delay = retryDelay(for: http, attempt: attempt)
                DebugLogger.log(.network, "wikipedia response=\(http.statusCode) retry in \(String(format: "%.2f", delay))s")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await self.request(queryItems: queryItems, attempt: attempt + 1)
            }

            if http.statusCode == 429 {
                throw WikipediaClientError.rateLimited
            }

            throw WikipediaClientError.httpStatus(http.statusCode)
        default:
            throw WikipediaClientError.httpStatus(http.statusCode)
        }
    }

    private func retryDelay(for response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(retryAfter),
           seconds > 0 {
            return seconds
        }

        return 0.5 * pow(2, Double(attempt))
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

    private func stripHTML(_ value: String) -> String {
        let tagRange = NSRange(value.startIndex..., in: value)
        var output = Self.htmlTagRegex.stringByReplacingMatches(in: value, options: [], range: tagRange, withTemplate: " ")

        for (entity, replacement) in Self.namedEntities {
            output = output.replacingOccurrences(of: entity, with: replacement)
        }

        output = decodeNumericEntities(in: output)

        let whitespaceRange = NSRange(output.startIndex..., in: output)
        output = Self.whitespaceRegex.stringByReplacingMatches(
            in: output,
            options: [],
            range: whitespaceRange,
            withTemplate: " "
        )

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeNumericEntities(in value: String) -> String {
        let range = NSRange(value.startIndex..., in: value)
        var result = value

        let matches = Self.numericEntityRegex.matches(in: value, options: [], range: range)
        for match in matches.reversed() {
            guard let entityRange = Range(match.range(at: 0), in: result),
                  let codeRange = Range(match.range(at: 1), in: result) else {
                continue
            }

            let codeValue = String(result[codeRange])
            let scalarValue: UInt32?
            if codeValue.hasPrefix("x") || codeValue.hasPrefix("X") {
                scalarValue = UInt32(codeValue.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(codeValue, radix: 10)
            }

            guard let scalarValue,
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }

            result.replaceSubrange(entityRange, with: String(Character(scalar)))
        }

        return result
    }
}

private struct WikipediaSearchResponseDTO: Decodable {
    let query: SearchQueryDTO
}

private struct SearchQueryDTO: Decodable {
    let search: [SearchItemDTO]
}

private struct SearchItemDTO: Decodable {
    let pageID: Int
    let title: String
    let snippet: String

    enum CodingKeys: String, CodingKey {
        case pageID = "pageid"
        case title
        case snippet
    }
}

private struct WikipediaPageResponseDTO: Decodable {
    let query: PageQueryDTO
}

private struct PageQueryDTO: Decodable {
    let pages: [WikipediaPageDTO]
}

private struct WikipediaPageDTO: Decodable {
    let pageID: Int
    let title: String
    let fullURL: String
    let revisions: [RevisionDTO]
    let missing: Bool

    enum CodingKeys: String, CodingKey {
        case pageID = "pageid"
        case title
        case fullURL = "fullurl"
        case revisions
        case missing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageID = try container.decodeIfPresent(Int.self, forKey: .pageID) ?? -1
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        fullURL = try container.decodeIfPresent(String.self, forKey: .fullURL) ?? ""
        revisions = try container.decodeIfPresent([RevisionDTO].self, forKey: .revisions) ?? []
        missing = container.contains(.missing)
    }
}

private struct RevisionDTO: Decodable {
    let wikitext: String?

    enum CodingKeys: String, CodingKey {
        case slots
        case content
    }

    struct SlotsDTO: Decodable {
        let main: MainSlotDTO?
    }

    struct MainSlotDTO: Decodable {
        let content: String?

        enum CodingKeys: String, CodingKey {
            case content = "content"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let slots = try? container.decode(SlotsDTO.self, forKey: .slots),
           let slotContent = slots.main?.content {
            wikitext = slotContent
            return
        }

        wikitext = try? container.decode(String.self, forKey: .content)
    }
}
