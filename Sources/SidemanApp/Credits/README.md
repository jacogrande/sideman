# Credits

The credit lookup pipeline. Resolves a currently playing track to structured credit data from MusicBrainz and/or Wikipedia.

## Pipeline Overview

```
NowPlayingTrack
  -> TrackResolver (MusicBrainz search, confidence scoring)
  -> CreditsProvider (relationship fetch or wikitext parse)
  -> CreditsMapper (role grouping, merge with precedence)
  -> CreditsBundle (Musicians, Production, Writing, Engineering, Misc)
```

All network clients and caches are Swift actors with configurable rate limiting.

## Protocols (`CreditsProtocols.swift`)

| Protocol | Purpose |
|---|---|
| `MusicBrainzClient` | Recording search, relationship lookup, ISRC fetch, artist browse |
| `WikipediaAPIClient` | Page search and wikitext fetch |
| `TrackResolver` | Resolves `NowPlayingTrack` to a MusicBrainz recording/release |
| `WikipediaPageResolver` | Resolves album/artist to a Wikipedia page |
| `WikipediaWikitextParser` | Extracts credits from raw wikitext |
| `CreditsProvider` | Top-level interface: track in, credits out |
| `CreditsCache` | Get/set/remove cached credit results |
| `SpotifyWebAPI` | Spotify search, playlist creation, track add |

All test stubs conform to these protocols and are defined `private` within each test file.

## Data Models (`CreditsModels.swift`)

- `CreditRoleGroup` -- Musicians, Production, Writing, Engineering, Misc
- `CreditEntry` -- One person + role + scope (album-wide, track-specific, etc.)
- `CreditsBundle` -- Grouped credits with source metadata and matched track number
- `CreditsLookupState` -- State machine: idle -> resolving -> loading -> loaded/notFound/ambiguous/error
- `ArtistRecordingRel` -- MusicBrainz recording with relationship type, attributes, artist credits, and pre-fetched ISRCs
- `SpotifyTrack`, `SpotifyPlaylist`, `SpotifyTokens` -- Spotify domain models
- `SpotifyClientError`, `MusicBrainzClientError` -- Typed error enums

## Credit Providers

### `DefaultCreditsProvider`

MusicBrainz-based. Resolves the track to a recording, fetches relationships (recording-level and release-level), merges with precedence (recording > release), and maps to `CreditEntry` objects.

### `WikipediaCreditsProvider`

Wikipedia-based. Resolves the album to a Wikipedia page, fetches raw wikitext, parses the personnel/credits section. Handles inline track scopes (`on tracks 1, 3`), parenthetical scopes (`(tracks 2-5)`), semicolon-grouped roles, and nested subsections.

### `CreditsProviderFactory`

Creates the active provider based on the `SIDEMAN_CREDITS_BACKEND` environment variable. Also creates `PlaylistBuilder` instances with all required dependencies wired up.

## Network Clients

### `MusicBrainzHTTPClient`

Actor with 1.0s minimum interval between requests. Implements the full `MusicBrainzClient` protocol:

- `searchRecordings` -- Text search for recordings
- `getRecording` / `getWork` / `getRelease` -- Fetch entity details with relationships
- `getArtistRecordingRels` -- Recording-level relationships for an artist
- `browseRecordings` -- Paginated browse with optional `inc=isrcs` for bulk ISRC fetch
- `getRecordingISRCs` -- Per-recording ISRC lookup (fallback when bulk ISRCs unavailable)
- `searchArtists` -- Artist name search with match scores

### `WikipediaAPIClient`

Actor with 0.4s minimum interval. Searches `en.wikipedia.org` and fetches page content as raw wikitext.

### `ListenBrainzClient`

Actor querying `api.listenbrainz.org` for recording popularity. Supports batch POST (up to 1000 MBIDs) with fallback to per-artist top recordings.

## Caching

### `MemoryDiskCreditsCache`

Dual-layer cache (in-memory dictionary + JSON file at `~/Library/Caches/sideman/credits-cache.json`). TTLs: 30 days for successful lookups, 24 hours for not-found/ambiguous. Expired entries are purged on read.

### `DiscographyCache`

Same pattern for artist discographies. Stored at `~/Library/Application Support/sideman/discography-cache.json` with 7-day TTL.

## Track Matching (`TrackMatchingService`)

Resolves `ArtistRecordingRel` entries to Spotify tracks for playlist creation:

1. Use pre-fetched ISRCs (from bulk browse) when available
2. Fall back to per-recording ISRC fetch from MusicBrainz
3. Fall back to Spotify text search (`track:"title" artist:"name"`)
4. Skip recording if no match found

Rate-limit errors from MusicBrainz are propagated rather than silently swallowed.

## Text Matching (`CreditsTextMatching.swift`)

Configurable text normalization for fuzzy matching:

- Strip "featuring" suffixes
- Strip parenthetical content
- Reduce to alphanumerics only
- Case-insensitive comparison
- Similarity scoring with configurable thresholds

Used by both `DefaultTrackResolver` and `WikipediaPageResolver`.
