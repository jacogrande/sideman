import Foundation

enum SpotifyAuthStatus: Equatable {
    case notAuthenticated
    case authenticating
    case authenticated
    case error(String)
}

@MainActor
final class SpotifyAuthState: ObservableObject {
    @Published private(set) var status: SpotifyAuthStatus = .notAuthenticated
    let client: SpotifyWebAPIClient

    init(client: SpotifyWebAPIClient = SpotifyWebAPIClient()) {
        self.client = client
    }

    func restoreSession() async {
        await client.restoreSession()
        let authed = await client.isAuthenticated
        if authed {
            status = .authenticated
            DebugLogger.log(.app, "Spotify auth restored from Keychain")
        } else {
            status = .notAuthenticated
        }
    }

    func startLogin() async {
        status = .authenticating
        do {
            try await client.authenticate()
            status = .authenticated
            DebugLogger.log(.app, "Spotify login succeeded")
        } catch let error as SpotifyClientError {
            switch error {
            case .authenticationCancelled:
                status = .notAuthenticated
                DebugLogger.log(.app, "Spotify login cancelled")
            default:
                status = .error(error.localizedDescription)
                DebugLogger.log(.app, "Spotify login failed: \(error)")
            }
        } catch {
            status = .error(error.localizedDescription)
            DebugLogger.log(.app, "Spotify login failed: \(error)")
        }
    }

    func logout() async {
        await client.logout()
        status = .notAuthenticated
        DebugLogger.log(.app, "Spotify logout")
    }
}
