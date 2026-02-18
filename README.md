# Sideman

A macOS menu bar app that shows who played on the track you're listening to.

Sideman reads the currently playing track from Spotify, resolves it against MusicBrainz and Wikipedia, and displays session musicians, producers, engineers, and writers grouped by role. Tap any credited person to generate a Spotify playlist of tracks they've appeared on.

## Architecture

```
Sources/SidemanApp/
  Credits/     Credit lookup pipeline (MusicBrainz, Wikipedia, caching)
  Spotify/     Spotify OAuth (PKCE), Web API client, Keychain storage
  Playlist/    Playlist curation from artist discographies
  *.swift      App entry point, menu bar UI, now-playing detection, diagnostics
```

Concurrency uses Swift actors for all network clients and caches, `@MainActor` for ViewModels and UI state, and structured concurrency (`Task`, `checkCancellation`) throughout.

## Requirements

- macOS 13+
- Spotify desktop app (for now-playing detection via AppleScript)
- Network access to MusicBrainz, Wikipedia, ListenBrainz, and Spotify Web API

## Build & Run

```bash
swift build
swift run SidemanApp
```

The app appears as a music note icon in the menu bar. Play a track in Spotify and open the popover to see credits.

## Test

```bash
swift test
```

69 tests covering the credits pipeline, caching, Wikipedia parsing, track resolution, and playlist model logic.

## How It Works

### Credits Lookup

1. **Now-playing detection** -- `SpotifyAppleScriptNowPlayingProvider` polls Spotify via AppleScript to get the current track URI, title, artist, and album.

2. **Track resolution** -- `DefaultTrackResolver` searches MusicBrainz for the recording by title/artist, scoring candidates with text normalization and confidence thresholds.

3. **Credit extraction** -- Either `DefaultCreditsProvider` (MusicBrainz relationships) or `WikipediaCreditsProvider` (Wikipedia personnel sections) fetches credits and maps them to role groups: Musicians, Production, Writing, Engineering, Misc.

4. **Caching** -- `MemoryDiskCreditsCache` provides a dual-layer cache (in-memory dict + JSON file on disk) with configurable TTL (30 days for successful lookups, 24 hours for not-found).

### Playlist Creation

1. **Discography fetch** -- `ArtistDiscographyService` combines MusicBrainz recording-rels (session work) with browse recordings (primary artist credits), capped at 500 total. ISRCs are bulk-fetched during the browse stage.

2. **Popularity ranking** -- `ListenBrainzClient` ranks recordings by listen count, with fallback to top-recordings-for-artist, then alphabetical.

3. **Track matching** -- `TrackMatchingService` resolves each recording to Spotify via ISRC (preferred) or text search fallback.

4. **Playlist creation** -- `PlaylistBuilder` creates the playlist via the Spotify Web API and opens it in Spotify.

## Configuration

| Environment Variable | Values | Default |
|---|---|---|
| `SIDEMAN_CREDITS_BACKEND` | `wikipedia`, `musicbrainz`, `wikipedia_then_musicbrainz` | `wikipedia` |

## Project Structure

| File | Purpose |
|---|---|
| `SidemanApp.swift` | `@main` entry point; wires up providers, caches, and ViewModels |
| `MenuBarContentView.swift` | SwiftUI popover UI (track info, credits, settings, diagnostics) |
| `MenuBarViewModel.swift` | Orchestrates polling, credits lookup, and resource monitoring |
| `NowPlayingProvider.swift` | Protocol for playback state detection |
| `NowPlayingModels.swift` | `PlaybackState`, `NowPlayingTrack`, `PlaybackSnapshot` |
| `SpotifyAppleScriptNowPlayingProvider.swift` | AppleScript bridge to Spotify desktop app |
| `DebugLogging.swift` | Categorized logging (`app`, `ui`, `provider`, `network`, `cache`, ...) |
| `GlassComponents.swift` | Glass-morphism button styles and UI components |
| `ResourceMonitor.swift` | Captures memory, CPU, and cache file metrics |
| `DiagnosticsCardView.swift` | Diagnostics display card |

See each subdirectory's README for domain-specific documentation.
