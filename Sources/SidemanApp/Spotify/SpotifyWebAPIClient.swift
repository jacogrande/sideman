import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(AppKit)
import AppKit
#endif

actor SpotifyWebAPIClient: SpotifyWebAPI {
    private let clientID = "0e45759716504c17b8441f9aaec23ed2"
    private let redirectURI = "http://127.0.0.1:28371/callback"
    private let scopes = "playlist-modify-public playlist-modify-private"
    private let authBaseURL = URL(string: "https://accounts.spotify.com")!
    private let apiBaseURL = URL(string: "https://api.spotify.com/v1")!

    private let session: URLSession
    private let minIntervalSeconds: TimeInterval
    private var lastRequestAt: Date?
    private var tokens: SpotifyTokens?
    private var isRefreshing = false

    var isAuthenticated: Bool {
        tokens != nil && !(tokens?.isExpired ?? true)
    }

    init(session: URLSession = .shared, minIntervalSeconds: TimeInterval = 0.05) {
        self.session = session
        self.minIntervalSeconds = minIntervalSeconds
    }

    // MARK: - Auth Lifecycle

    func restoreSession() {
        if let stored = SpotifyKeychain.loadTokens() {
            tokens = stored
            DebugLogger.log(.app, "Spotify session restored, expired=\(stored.isExpired)")
        }
    }

    func authenticate() async throws {
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = UUID().uuidString

        var authComponents = URLComponents(url: authBaseURL.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)!
        authComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = authComponents.url else {
            throw SpotifyClientError.authenticationFailed("Could not construct auth URL")
        }

        let server = SpotifyCallbackServer()
        DebugLogger.log(.app, "Opening Spotify auth URL in browser")

        #if canImport(AppKit)
        _ = await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }
        #endif

        let authCode = try await server.waitForCallback(expectedState: state)
        DebugLogger.log(.app, "Received Spotify auth code")

        let newTokens = try await exchangeCodeForTokens(code: authCode, codeVerifier: codeVerifier)
        tokens = newTokens
        try SpotifyKeychain.saveTokens(newTokens)
        DebugLogger.log(.app, "Spotify authentication complete")
    }

    func logout() {
        tokens = nil
        SpotifyKeychain.deleteTokens()
        DebugLogger.log(.app, "Spotify session cleared")
    }

    // MARK: - SpotifyWebAPI

    func searchTrackByISRC(_ isrc: String) async throws -> [SpotifyTrack] {
        let result: SpotifySearchResponseDTO = try await authenticatedRequest(
            path: "search",
            queryItems: [
                URLQueryItem(name: "q", value: "isrc:\(isrc)"),
                URLQueryItem(name: "type", value: "track"),
                URLQueryItem(name: "limit", value: "5")
            ]
        )

        return result.tracks.items.map(mapTrack)
    }

    func searchTracks(title: String, artist: String) async throws -> [SpotifyTrack] {
        let escapedTitle = stripSearchMetacharacters(title)
        let escapedArtist = stripSearchMetacharacters(artist)
        let query = "track:\"\(escapedTitle)\" artist:\"\(escapedArtist)\""
        let result: SpotifySearchResponseDTO = try await authenticatedRequest(
            path: "search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "track"),
                URLQueryItem(name: "limit", value: "3")
            ]
        )

        return result.tracks.items.map(mapTrack)
    }

    func createPlaylist(name: String, description: String, isPublic: Bool) async throws -> SpotifyPlaylist {
        let body: [String: Any] = [
            "name": name,
            "description": description,
            "public": isPublic
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let dto: SpotifyPlaylistDTO = try await authenticatedRequest(
            method: "POST",
            path: "me/playlists",
            body: bodyData
        )

        return SpotifyPlaylist(
            id: dto.id,
            name: dto.name,
            url: dto.externalUrls.spotify
        )
    }

    func addTracksToPlaylist(playlistID: String, trackURIs: [String]) async throws {
        let chunks = stride(from: 0, to: trackURIs.count, by: 100).map {
            Array(trackURIs[$0..<min($0 + 100, trackURIs.count)])
        }

        for chunk in chunks {
            let body = try JSONSerialization.data(withJSONObject: ["uris": chunk])
            let _: SpotifySnapshotDTO = try await authenticatedRequest(
                method: "POST",
                path: "playlists/\(playlistID)/items",
                body: body
            )
        }
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> SpotifyTokens {
        let url = authBaseURL.appendingPathComponent("api/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
            ("code_verifier", codeVerifier)
        ]
        request.httpBody = params.map { "\($0.0)=\(percentEncode($0.1))" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SpotifyClientError.authenticationFailed("Token exchange failed: HTTP \(status)")
        }

        let dto = try JSONDecoder().decode(TokenResponseDTO.self, from: data)
        DebugLogger.log(.network, "Spotify token granted scopes: \(dto.scope ?? "<none>")")
        guard let refreshToken = dto.refreshToken, !refreshToken.isEmpty else {
            throw SpotifyClientError.authenticationFailed("No refresh token in response")
        }
        return SpotifyTokens(
            accessToken: dto.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(dto.expiresIn))
        )
    }

    private func refreshTokens() async throws {
        guard !isRefreshing else {
            try? await Task.sleep(nanoseconds: 200_000_000)
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let currentTokens = tokens, !currentTokens.refreshToken.isEmpty else {
            throw SpotifyClientError.tokenRefreshFailed("No refresh token available")
        }

        DebugLogger.log(.network, "Refreshing Spotify access token")

        let url = authBaseURL.appendingPathComponent("api/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [(String, String)] = [
            ("grant_type", "refresh_token"),
            ("refresh_token", currentTokens.refreshToken),
            ("client_id", clientID)
        ]
        request.httpBody = params.map { "\($0.0)=\(percentEncode($0.1))" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SpotifyClientError.tokenRefreshFailed("Refresh failed: HTTP \(status)")
        }

        let dto = try JSONDecoder().decode(TokenResponseDTO.self, from: data)
        let newTokens = SpotifyTokens(
            accessToken: dto.accessToken,
            refreshToken: dto.refreshToken ?? currentTokens.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(dto.expiresIn))
        )
        tokens = newTokens
        try SpotifyKeychain.saveTokens(newTokens)
        DebugLogger.log(.network, "Spotify token refreshed successfully")
    }

    // MARK: - Authenticated Request

    private func authenticatedRequest<T: Decodable>(
        method: String = "GET",
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        attempt: Int = 0
    ) async throws -> T {
        guard var currentTokens = tokens else {
            throw SpotifyClientError.notAuthenticated
        }

        if currentTokens.isExpiringSoon {
            try await refreshTokens()
            guard let refreshed = tokens else {
                throw SpotifyClientError.notAuthenticated
            }
            currentTokens = refreshed
        }

        await paceRequests()

        guard var components = URLComponents(url: apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SpotifyClientError.network("Could not construct URL for path: \(path)")
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let requestURL = components.url else {
            throw SpotifyClientError.network("Could not construct URL for path: \(path)")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(currentTokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        DebugLogger.log(.network, "request \(requestURL.absoluteString) attempt=\(attempt + 1)")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SpotifyClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SpotifyClientError.network("Non-HTTP response")
        }

        switch http.statusCode {
        case 200...204:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw SpotifyClientError.decoding(error.localizedDescription)
            }

        case 401:
            if attempt < 1 {
                DebugLogger.log(.network, "Spotify 401, refreshing token and retrying")
                try await refreshTokens()
                return try await authenticatedRequest(method: method, path: path, queryItems: queryItems, body: body, attempt: attempt + 1)
            }
            throw SpotifyClientError.notAuthenticated

        case 429:
            if attempt < 3 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 1.0
                DebugLogger.log(.network, "Spotify 429, retrying in \(retryAfter)s")
                try? await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                return try await authenticatedRequest(method: method, path: path, queryItems: queryItems, body: body, attempt: attempt + 1)
            }
            throw SpotifyClientError.rateLimited

        case 404:
            throw SpotifyClientError.notFound

        case 403:
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            DebugLogger.log(.network, "Spotify 403 Forbidden: \(method) \(path) — \(responseBody)")
            throw SpotifyClientError.httpStatus(http.statusCode)

        default:
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            DebugLogger.log(.network, "Spotify HTTP \(http.statusCode): \(method) \(path) — \(responseBody)")
            throw SpotifyClientError.httpStatus(http.statusCode)
        }
    }

    // MARK: - Pacing

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

    // MARK: - PKCE

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    // MARK: - Helpers

    private func stripSearchMetacharacters(_ value: String) -> String {
        let metacharacters = CharacterSet(charactersIn: "\"+-!(){}[]^~*?:\\/")
        return value.unicodeScalars.filter { !metacharacters.contains($0) }.map(String.init).joined()
    }

    private func percentEncode(_ value: String) -> String {
        // RFC 3986 unreserved characters only — safe for application/x-www-form-urlencoded
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func mapTrack(_ dto: SpotifyTrackDTO) -> SpotifyTrack {
        SpotifyTrack(
            id: dto.id,
            name: dto.name,
            uri: dto.uri,
            artistNames: dto.artists.map(\.name),
            albumName: dto.album.name,
            isrc: dto.externalIds?.isrc,
            popularity: dto.popularity
        )
    }
}

// MARK: - Data Extensions

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Spotify DTOs

private struct TokenResponseDTO: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct SpotifySearchResponseDTO: Decodable {
    let tracks: SpotifyTracksPageDTO
}

private struct SpotifyTracksPageDTO: Decodable {
    let items: [SpotifyTrackDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([SpotifyTrackDTO].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case items
    }
}

private struct SpotifyTrackDTO: Decodable {
    let id: String
    let name: String
    let uri: String
    let artists: [SpotifyArtistDTO]
    let album: SpotifyAlbumDTO
    let externalIds: SpotifyExternalIdsDTO?
    let popularity: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, uri, artists, album, popularity
        case externalIds = "external_ids"
    }
}

private struct SpotifyArtistDTO: Decodable {
    let id: String
    let name: String
}

private struct SpotifyAlbumDTO: Decodable {
    let name: String
}

private struct SpotifyExternalIdsDTO: Decodable {
    let isrc: String?
}

private struct SpotifyPlaylistDTO: Decodable {
    let id: String
    let name: String
    let externalUrls: SpotifyExternalUrlsDTO

    enum CodingKeys: String, CodingKey {
        case id, name
        case externalUrls = "external_urls"
    }
}

private struct SpotifyExternalUrlsDTO: Decodable {
    let spotify: String?
}

private struct SpotifySnapshotDTO: Decodable {
    let snapshotId: String?

    enum CodingKeys: String, CodingKey {
        case snapshotId = "snapshot_id"
    }
}
