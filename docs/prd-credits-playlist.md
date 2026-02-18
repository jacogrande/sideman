# PRD: Playlist Curation from Credits

## Problem

You're listening to a track and see "Bass: Pino Palladino" in the credits panel. You think, "this bass line is incredible — what else has this person played on?" Today, Sideman shows credits but treats them as dead-end text. There's no way to act on that curiosity.

## Solution

Make credited names tappable. Clicking a name triggers a pipeline that discovers all recordings that person contributed to, ranks them by popularity, resolves them to Spotify tracks, and creates a Spotify playlist — all from a single click.

### User flow

1. User is listening to "Slow Dancing in a Burning Room" in Spotify
2. Sideman's credits panel shows: **Musicians → Pino Palladino — bass guitar**
3. User clicks "Pino Palladino"
4. Sideman shows a popover: "Create playlist of tracks featuring Pino Palladino?"
   - Option to filter by the specific role (e.g., "bass guitar only") or "all roles"
   - Option to set playlist visibility (public/private)
5. User confirms; a progress indicator shows stages: "Fetching discography... Ranking tracks... Matching on Spotify... Creating playlist..."
6. Sideman opens the new playlist in Spotify

## Technical architecture

### Data we already have

Each `CreditEntry` (defined in `CreditsModels.swift:144`) already carries:

- `personName` — display name
- `personMBID` — MusicBrainz artist ID (key to the whole pipeline)
- `roleRaw` / `roleGroup` — what they did (e.g., "bass guitar" / `.musicians`)
- `instrument` — parsed instrument name
- `source` — Wikipedia or MusicBrainz

The `personMBID` is the critical piece — it's the globally unique key that lets us query MusicBrainz for everything that person has ever been credited on.

### Pipeline: credited name → Spotify playlist

#### Stage 1: Fetch discography from MusicBrainz

**Endpoint:** `GET /ws/2/artist/{personMBID}?inc=recording-rels&fmt=json`

This returns all recording-level relationships for the artist in a single response (no pagination needed — tested with Pino Palladino, returned 674 relationships). Each relationship includes:

- `type`: "instrument", "vocal", "producer", "engineer", "mixer", etc.
- `attributes`: specific details like ["bass guitar"], ["background vocals"]
- Recording MBID and title

**Client-side filtering:** If the user chose "bass guitar only", filter to entries where `type == "instrument"` and `attributes` contains "bass guitar" (or similar). If "all roles", keep everything.

**For artists who are primarily performers** (listed as the main artist on tracks, not just session work), supplement with the browse endpoint: `GET /ws/2/recording?artist={MBID}&limit=100&offset=0&fmt=json`. This catches tracks where they're the main artist but no specific instrument relationship was recorded. Paginate with `offset` (max 100 per page).

**Rate limiting:** Reuse the existing `MusicBrainzHTTPClient` actor which already enforces 1 req/sec pacing and retry logic for 429/503 responses.

#### Stage 2: Rank by popularity

Two options, in order of preference:

**Option A — ListenBrainz popularity (no auth required):**

```
POST https://api.listenbrainz.org/1/popularity/recording
Body: {"recording_mbids": ["mbid1", "mbid2", ...]}
```

Returns `total_listen_count` per recording. Batch up to ~1000 MBIDs per request. Sort descending, take top 100.

Alternatively, for well-known artists:

```
GET https://api.listenbrainz.org/1/popularity/top-recordings-for-artist/{artist_mbid}
```

Returns pre-ranked top recordings. Cross-reference with the relationship list to filter by role.

**Option B — Spotify popularity (requires auth, available later):**
Once we have Spotify track IDs from Stage 3, each search result includes a `popularity` field (0-100). Re-rank using this. More comprehensive than ListenBrainz but adds a dependency on completing the Spotify→track matching first.

**Fallback:** If popularity data is unavailable, include all recordings (no ranking, alphabetical by title). Cap at 100 tracks for playlist sanity.

#### Stage 3: Resolve MusicBrainz recordings → Spotify tracks

For each recording MBID, we need a Spotify track URI. Three strategies, tried in order:

**Strategy A — ISRC bridge (fastest, most accurate):**

1. Fetch ISRCs: `GET /ws/2/recording/{MBID}?inc=isrcs&fmt=json` → `isrcs: ["USSM10603632"]`
2. Search Spotify: `GET /v1/search?q=isrc:USSM10603632&type=track&limit=1`

Confirmed working: "Slow Dancing in a Burning Room" has ISRC `USSM10603632` on MusicBrainz.

**Bottleneck:** 1 req/sec to MusicBrainz for ISRC lookup per recording. For 100 tracks, this takes ~100 seconds.

**Mitigation — batch via browse:** `GET /ws/2/recording?artist={MBID}&limit=100&offset=0&inc=isrcs&fmt=json` returns ISRCs for up to 100 recordings per request. However, this only covers recordings where the artist is the primary artist-credit — not session work. For session work recordings, individual lookups are needed.

**Strategy B — Title + artist text search (fallback):**

```
GET /v1/search?q=track:"Slow Dancing in a Burning Room" artist:"John Mayer"&type=track&limit=1
```

Less precise (may match covers, remasters, live versions) but requires no MusicBrainz ISRC lookup.

**Strategy C — Skip unresolvable recordings:**
If both ISRC and text search fail, skip the recording. Log it for diagnostics.

#### Stage 4: Create Spotify playlist

```
POST /v1/me/playlists
Body: {
  "name": "Pino Palladino — Bass Credits",
  "description": "Tracks featuring Pino Palladino on bass guitar. Generated by Sideman.",
  "public": false
}

POST /v1/playlists/{id}/tracks
Body: {"uris": ["spotify:track:...", ...]}  // max 100 per request
```

Then open in Spotify via AppleScript:

```applescript
tell application "Spotify" to open location "spotify:playlist:{id}"
```

### New subsystem: Spotify Web API authentication

**This is the biggest new piece.** Today Sideman talks to Spotify only via AppleScript. Playlist creation requires the Spotify Web API, which needs OAuth 2.0 with PKCE.

**Flow:**

1. Register a Spotify app at developer.spotify.com → get `client_id`
2. On first "create playlist" action, open the browser to Spotify's authorization URL
3. User grants permission; Spotify redirects to a local callback (`http://localhost:{port}/callback`)
4. Exchange code for access token + refresh token
5. Store tokens in Keychain
6. Refresh automatically when expired

**Required scopes:** `playlist-modify-public`, `playlist-modify-private`

**Implementation:** A new `SpotifyWebAPIClient` actor, separate from the AppleScript provider. Handles token lifecycle, token refresh, and authenticated HTTP requests to `api.spotify.com`.

## Handling the "not notable enough" case

The pipeline works best for artists with substantial MusicBrainz data. For obscure contributors:

- **No MBID available:** Some Wikipedia-sourced credits have `personMBID == nil`. Show a disabled state on the name with tooltip: "MusicBrainz profile not found for this person."
- **Few or no recording relationships:** If MusicBrainz returns <5 recordings, show a message: "Only N tracks found for [Name]. Create playlist anyway?" — user can proceed or cancel.
- **No Spotify matches:** If ISRC + text search resolve <3 tracks, warn the user before creating a near-empty playlist.

## Scope and phasing

### Phase 1 — Core pipeline (MVP)

- Tappable names in the credits panel (only for entries with `personMBID != nil`)
- Fetch recording relationships from MusicBrainz
- Rank using ListenBrainz popularity (no Spotify auth needed for ranking)
- Resolve to Spotify via ISRC → text search fallback
- Spotify OAuth 2.0 PKCE flow with Keychain token storage
- Create private playlist and open in Spotify
- Progress UI with cancellation
- Cache discography results (7-day TTL, same pattern as `MemoryDiskCreditsCache`)

### Phase 2 — Polish

- Role filtering ("bass guitar only" vs. "all contributions")
- "Add to existing playlist" option (in addition to "create new")
- Playlist artwork: auto-generate a collage from album covers, or use the artist's photo
- Persistent Spotify auth (stay logged in across app restarts, refresh tokens)
- Batch ISRC resolution optimization (pre-fetch ISRCs when browsing credits)

### Phase 3 — Power features

- "Similar contributors" — if you like this bassist, here are other bassists who played on the same albums
- Cross-credit playlists — "all tracks from this album's personnel" (everyone who played on _Continuum_)
- Export to other formats (Apple Music via MusicKit, plain text tracklist)

## Files to create/modify

| File                                                        | Change                                                                     |
| ----------------------------------------------------------- | -------------------------------------------------------------------------- |
| `Sources/SidemanApp/Spotify/SpotifyWebAPIClient.swift`      | New — OAuth 2.0 PKCE flow, token management, playlist CRUD                 |
| `Sources/SidemanApp/Spotify/SpotifyAuthState.swift`         | New — Published auth state for UI binding                                  |
| `Sources/SidemanApp/Credits/ArtistDiscographyService.swift` | New — Fetches + filters recording-rels from MusicBrainz                    |
| `Sources/SidemanApp/Credits/ListenBrainzClient.swift`       | New — Popularity ranking API client                                        |
| `Sources/SidemanApp/Credits/TrackMatchingService.swift`     | New — ISRC bridge + text search fallback to resolve MB→Spotify             |
| `Sources/SidemanApp/Playlist/PlaylistBuilder.swift`         | New — Orchestrates the full pipeline (discography → rank → match → create) |
| `Sources/SidemanApp/Playlist/PlaylistBuilderState.swift`    | New — Observable state for progress UI                                     |
| `Sources/SidemanApp/MenuBarContentView.swift`               | Modify — Make person names tappable, add playlist creation popover         |
| `Sources/SidemanApp/Credits/CreditsModels.swift`            | Modify — Add `MBArtistDiscography` model                                   |
| `Sources/SidemanApp/Credits/MusicBrainzHTTPClient.swift`    | Modify — Add `getArtistRecordingRels(id:)` method                          |
| `SupportFiles/Info.plist`                                   | Modify — Add URL scheme for OAuth callback                                 |

## Performance considerations

| Operation                      | Time estimate            | Mitigation                                                                         |
| ------------------------------ | ------------------------ | ---------------------------------------------------------------------------------- |
| Fetch recording-rels           | 1-2s (single request)    | Cache 7 days                                                                       |
| ListenBrainz popularity        | 1-2s (single batch POST) | Cache 7 days                                                                       |
| ISRC resolution (100 tracks)   | ~100s at 1 req/sec       | Use browse endpoint where possible; parallelize with Spotify search; show progress |
| Spotify text search (fallback) | ~2s per track            | Batch via concurrent requests (Spotify allows ~30 req/sec)                         |
| Playlist creation              | <1s                      | N/A                                                                                |

**Total worst case:** ~2 minutes for 100 tracks with full ISRC resolution. **Realistic case** (50% ISRC hit from browse, 50% text search): ~30 seconds.

## Decisions (formerly open questions)

1. **Spotify app registration:** Ship with a **hardcoded `client_id`**. The client ID is not a secret in OAuth PKCE flows — that's the entire point of PKCE (no client secret). Requiring users to register a Spotify developer app would kill adoption. The ID is visible in the binary but can only be used with PKCE, which requires user consent in the browser.

2. **Rate limiting strategy for MusicBrainz:** **Add a dedicated background bulk worker queue.** Lean on the browse endpoint (`/ws/2/recording?artist={MBID}&inc=isrcs`) first — it covers main-artist tracks in pages of 100. For session-work recordings that need individual ISRC lookups, run those on the bulk queue at 1 req/sec with live progress updates ("Resolving track 47 of 83..."). Cancellation support is essential.

3. **ListenBrainz vs. Spotify popularity:** **Use both, in sequence.** ListenBrainz first (free, auth-less, single batch POST) for initial ranking and pre-filtering — avoids wasting Spotify searches on obscure recordings. Then re-sort the final playlist by Spotify popularity, which comes free from the search results. Best of both worlds at zero extra API cost.

4. **Wikipedia-only credits:** **Attempt a lightweight MusicBrainz artist search by name** (`GET /ws/2/artist?query=name:"Name"&fmt=json&limit=3`). If we get a high-confidence match (exact name, score > 90), use it. Otherwise, show the name as non-tappable with a tooltip: "MusicBrainz profile not found for this person." This catches well-known musicians without creating false-positive playlists for ambiguous names.
