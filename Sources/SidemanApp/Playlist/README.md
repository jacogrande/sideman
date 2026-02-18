# Playlist

Playlist curation from artist credits. Given a credited person, builds a Spotify playlist of tracks they've appeared on.

## Pipeline Overview

```
User taps a credited person
  -> PlaylistViewModel.beginFlow()
  -> Resolve person to MusicBrainz artist (if MBID unknown)
  -> Authenticate with Spotify (if needed)
  -> PlaylistBuilder.buildPlaylist()
     1. Fetch discography (MusicBrainz recording-rels + browse)
     2. Rank by popularity (ListenBrainz)
     3. Resolve to Spotify tracks (ISRC preferred, text search fallback)
     4. Create playlist + add tracks via Spotify Web API
  -> Open playlist in Spotify
```

## Files

| File | Purpose |
|------|---------|
| `PlaylistBuilder.swift` | Actor orchestrating the four-stage build pipeline |
| `PlaylistViewModel.swift` | `@MainActor` ObservableObject driving the UI flow |
| `PlaylistFlowView.swift` | SwiftUI views for each phase of the playlist flow |

## `PlaylistBuilder`

Actor that coordinates the full build pipeline. Takes a `PlaylistBuildRequest` (artist MBID, name, optional role filter, public/private) and produces a `PlaylistBuildResult` (playlist name, URI, track count, skipped count).

### Stages

1. **Fetch discography** — `ArtistDiscographyService` combines recording-rels (session work) with browse recordings (primary artist credits), capped at 500 total. ISRCs are bulk-fetched during the browse stage.
2. **Rank by popularity** — `ListenBrainzClient` batch query for listen counts. Falls back to per-artist top recordings, then alphabetical sort.
3. **Resolve to Spotify** — `TrackMatchingService` matches each recording via ISRC (preferred) or text search. Progress is reported via callback.
4. **Create playlist** — Creates the playlist via `SpotifyWebAPI`, adds tracks in batches of 100, opens the result in Spotify.

A `@Sendable` stage callback reports progress to the ViewModel throughout.

## `PlaylistViewModel`

`@MainActor` ObservableObject managing the playlist creation flow. Publishes `PlaylistFlowPhase`:

| Phase | Description |
|-------|-------------|
| `.idle` | No active flow |
| `.confirming(PersonContext)` | Showing confirmation UI with role filter and public/private toggle |
| `.resolvingArtist` | Searching MusicBrainz for the person's MBID |
| `.authenticating` | Waiting for Spotify OAuth |
| `.building(PlaylistBuildStage)` | Active build with stage progress |
| `.completed(PlaylistBuildResult)` | Done — shows result with "Open in Spotify" button |
| `.failed(String)` | Error message display |

Configured at app startup with `PlaylistBuilder`, `SpotifyAuthState`, and `MusicBrainzClient` via `configure()`.

## `PlaylistFlowView`

SwiftUI view that switches on `PlaylistFlowPhase` to render the appropriate sub-view:

- **PlaylistConfirmationView** — Role filter capsules, public/private toggle, create/cancel buttons
- **ArtistSearchView** — Spinner while searching MusicBrainz
- **SpotifyAuthPromptView** — Spinner while waiting for OAuth
- **PlaylistProgressView** — Four-stage checklist with progress bar during track resolution
- **PlaylistCompletionView** — Track count, skipped count, "Open in Spotify" button
- **PlaylistErrorView** — Error message with dismiss button

All sub-views use the glassmorphism button styles from `GlassComponents.swift`.
