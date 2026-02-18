# Spotify

Spotify Web API integration: OAuth authentication (PKCE), token management, Keychain persistence, and API client.

## Authentication Flow

```
User taps "Connect"
  -> SpotifyAuthState.startLogin()
  -> SpotifyWebAPIClient.authenticate()
     -> Generate PKCE code verifier + challenge
     -> Open Spotify authorize URL in browser
     -> SpotifyCallbackServer listens on localhost:28371
     -> User approves in browser -> redirect to /callback
     -> Exchange auth code for tokens
     -> Save tokens to Keychain
```

Re-authentication is automatic: `authenticatedRequest()` refreshes expired tokens and retries on 401.

## Files

| File | Purpose |
|------|---------|
| `SpotifyAuthState.swift` | `@MainActor` ObservableObject managing auth status for the UI |
| `SpotifyWebAPIClient.swift` | Actor implementing `SpotifyWebAPI` protocol — auth, search, playlist creation |
| `SpotifyCallbackServer.swift` | NWListener-based local HTTP server for OAuth redirect |
| `SpotifyKeychain.swift` | macOS Keychain read/write/delete for `SpotifyTokens` |

## `SpotifyAuthState`

`@MainActor` wrapper that bridges the actor-isolated client to SwiftUI. Publishes `SpotifyAuthStatus` (`.notAuthenticated`, `.authenticating`, `.authenticated`, `.error`). Called from `SidemanApp.swift` on launch to restore sessions and from the UI to trigger login/logout.

## `SpotifyWebAPIClient`

Swift actor conforming to `SpotifyWebAPI`. Handles:

- **PKCE OAuth** — `authenticate()` generates a code verifier/challenge, opens the browser, waits for the callback server, and exchanges the auth code for tokens.
- **Token refresh** — `refreshTokens()` uses the refresh token grant. Guarded by `isRefreshing` to prevent concurrent refresh races.
- **Search** — `searchTrackByISRC` (ISRC query) and `searchTracks` (title + artist text query). Search metacharacters are stripped to avoid Spotify query syntax errors.
- **Playlist creation** — `createPlaylist` (POST to `me/playlists`) and `addTracksToPlaylist` (chunked in batches of 100).
- **Rate limiting** — Configurable minimum interval between requests (default 50ms). Spotify 429 responses are retried up to 3 times with `Retry-After` backoff.
- **Error mapping** — HTTP status codes map to typed `SpotifyClientError` cases.

Private DTOs (`TokenResponseDTO`, `SpotifyTrackDTO`, etc.) live at the bottom of the file.

## `SpotifyCallbackServer`

Actor wrapping an `NWListener` on port 28371. Waits for a single `/callback` GET request matching the expected OAuth `state` parameter, extracts the authorization code, and returns it. Non-`/callback` paths get a 404. A 120-second timeout cancels the flow if the user doesn't complete authorization.

Uses `ContinuationGuard` (private `NSLock`-based wrapper) to ensure the `CheckedContinuation` is resumed exactly once across timeout, success, and error paths.

## `SpotifyKeychain`

Static methods for saving, loading, and deleting `SpotifyTokens` via the macOS Security framework. Tokens are stored as JSON under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Failures throw `SpotifyClientError.keychainError`.
