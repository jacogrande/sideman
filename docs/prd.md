# PRD: Menu Bar Credits for Spotify

## Summary

A lightweight macOS menu bar app that detects what’s currently playing in the user’s **Spotify** Spotify desktop app and instantly shows **personnel and credits** for that track (musicians/instruments, producers, writers, engineers), plus “other versions” and useful links.

---

## Problem

When you hear a great part in a song (a drum fill, synth patch, guitar tone), it’s surprisingly hard to quickly answer:

- Who played that?
- Who produced/engineered it?
- Who wrote it?
- What other versions exist?

Credits are fragmented across sources, and the “moment of curiosity” is often lost.

---

## Goals

1. **One-click credits** from the macOS menu bar for the track currently playing in Spotify.
2. Present credits **grouped by role** (Performers, Production, Writing, Engineering).
3. Provide **other versions** discovery (remasters, live versions, radio edit, etc.).
4. Make the app **fast, low-friction, and private** (minimal permissions, transparent data usage).

### Non-goals (v1)

- Supporting streaming services other than Spotify (Apple Music, YouTube Music, etc.)
- Full library management / playlist features
- Social sharing, comments, or collaborative annotations
- Lyrics display (unless trivial later)

---

## Target users

- Music fans and hobbyists who love liner notes
- Musicians/producers learning from records
- DJs / music curators
- Music students and researchers

---

## Key user stories

1. **As a listener**, I want to click the menu bar icon and immediately see the track title/artist/album and top credits.
2. **As a producer**, I want to see production roles (producer, mixing, mastering, engineer) for the exact recording I’m hearing.
3. **As a musician**, I want performer credits including instruments (“bass”, “drums”, “strings”).
4. **As a curious fan**, I want “other versions” (live, acoustic, remaster, edit) in a list I can click to open in Spotify.
5. **As a privacy-conscious user**, I want to understand what data is accessed and have the ability to disable network lookups.

---

## Core experience (user flow)

1. User installs and launches app → menu bar icon appears.
2. App requests macOS permission to read Spotify “Now Playing” (Automation / Apple Events).
3. When Spotify is playing:
   - Menu bar popover shows: track, artist, album, artwork (if available)
   - Credits appear grouped by role
   - “Other versions” list appears
   - Links: Open in Spotify, Open in credits source page

4. If Spotify is paused/not running:
   - Popover shows friendly “Nothing playing” state

---

## Product requirements

### Functional requirements

**Now Playing Detection**

- FR1: Detect currently playing track in Spotify desktop app.
- FR2: Extract a stable identifier (Spotify track URI / ID).
- FR3: Update the popover when the track changes (near real-time, but battery-friendly).

**Metadata Resolution**

- FR4: Resolve track metadata: title, primary artists, album, album artwork (if available), duration.
- FR5: Prefer stable industry identifiers where possible (ISRC).

**Credits Retrieval**

- FR6: Fetch credits from at least one reputable source (see Data Sources) and map into normalized roles.
- FR7: Display credits grouped into:
  - Performers (with instruments where possible)
  - Writing (composer, lyricist, songwriter)
  - Production (producer, co-producer, executive producer)
  - Engineering (recording engineer, mixing, mastering)
  - Misc (arranger, programmer, etc.)

- FR8: Allow “Show more” to expand long lists.

**Other Versions**

- FR9: Provide a list of “other versions” (see definition below), each opening in Spotify if possible.
- FR10: Provide at least one alternate browsing route:
  - Search Spotify for the same title + artist
  - Or show variants from the credits database

**Links & Actions**

- FR11: “Open in Spotify” for the current track.
- FR12: “Copy credits” (plain text, nicely formatted).
- FR13: “Report mismatch” (creates a local diagnostic bundle the user can optionally share).

**Caching**

- FR14: Cache results per track ID/ISRC to make repeat lookups instant.
- FR15: Provide a “Refresh credits” action.

---

## “Other versions” definition (v1)

Because “version” can mean different things, v1 will implement two categories:

1. **Direct variants of the same song title by the same primary artist**
   Examples: “Remastered 2011”, “Radio Edit”, “Live at…”, “Acoustic”, “Demo”.

2. **Same composition/work** (when the credits source supports it)
   Examples: alternative recordings linked to the same underlying work.

UI should label them clearly:

- “Versions by this artist”
- “Other recordings of this work” (if supported)

---

## Data sources & strategy

Credits availability varies dramatically. The app should be designed as a **pluggable provider system**:

### Required provider (v1)

- **MusicBrainz** MusicBrainz (open metadata, relationship-based credits, ISRC lookups, work/recording relationships)

### Optional provider (post-v1 or “experimental” mode)

- Spotify internal credits endpoints (not official; may break; potential ToS concerns)
- Discogs / other commercial APIs (often require keys, have licensing constraints)

**Provider precedence**

- If multiple sources are enabled:
  1. Prefer the most complete / structured provider for role detail
  2. Merge with deduplication rules (same person, same role)
  3. Show source badges (small “MB” or “Spotify”) for transparency

---

## Technical requirements

### Platform & stack

- macOS app written in Swift + SwiftUI
- Menu bar app pattern (`MenuBarExtra` on macOS 13+; fallback to `NSStatusBar` if supporting older versions)

### Now Playing integration

- Use Apple Events / AppleScript to read Spotify desktop app state and track ID.
- Polling strategy:
  - Low-frequency idle polling (e.g., every 2–3s when popover closed)
  - Higher frequency when popover open (e.g., 0.5–1s) if needed
  - Backoff when Spotify not running

### Networking

- Use `URLSession`
- Respect provider rate limits (MusicBrainz is rate-limited; implement throttling + caching)
- Timeouts and robust retry (small, bounded)

### Caching

- In-memory cache (fast UI)
- On-disk cache (SQLite or lightweight JSON store) keyed by:
  - spotifyTrackId
  - ISRC (when available)
  - provider version + fetched timestamp

### Performance targets

- Popover opens in <150ms
- Credits display within:
  - <300ms for cached tracks
  - <2.5s p95 for cold fetch (show skeleton/loading states)

---

## Privacy, security, and permissions

**Permissions**

- macOS Automation permission to control/query Spotify (Apple Events)

**Data handling**

- By default, only track identifiers + metadata needed for lookup are sent to credit providers.
- No audio content, no listening history stored beyond local cache.
- Provide toggles:
  - “Enable online credits lookup” (on by default)
  - “Clear cache”
  - “Disable telemetry” (off by default; ideally no telemetry in v1)

**Security**

- If Spotify Web API is used (optional):
  - Use OAuth securely (Keychain)
  - Minimal scopes

- Otherwise, avoid sign-in for v1 to reduce friction.

---

## UX requirements (popover)

**Header**

- Artwork (small)
- Track title (1–2 lines)
- Artist + album (secondary)

**Tabs or sections**

- Credits (default)
- Versions
- Sources (optional debug view: MBIDs, ISRC, resolution path)

**Credits layout**

- Section headers: Performers, Production, Writing, Engineering
- Each entry: Person — Role (and instrument where relevant)
- Expand/collapse if >8 entries

**States**

- Loading (skeleton)
- No Spotify / not playing
- Track found but credits missing (actionable: “Search in sources”, “Report mismatch”)
- Network error (retry)

---

## Metrics (success criteria)

**Activation**

- % of installs that successfully grant Spotify permission and show now-playing within first session

**Core usage**

- Popover opens per day / per active user
- Credits resolved success rate:
  - By track ID
  - By ISRC
  - By provider

- Time-to-first-credits (TTFC) median / p95

**Quality**

- “Report mismatch” rate
- Refresh retries per track

---

## Rollout plan

### Milestone 1 — Prototype (1–2 days)

- Menu bar app shell
- AppleScript now-playing
- Display track title/artist/album only

### Milestone 2 — MVP credits (3–7 days)

- Resolve track → ISRC (if using Spotify Web API, or defer)
- MusicBrainz lookup by ISRC and/or title+artist fallback
- Render grouped credits + caching

### Milestone 3 — Versions + polish (1–2 weeks)

- Other versions list
- Links + copy credits
- Better matching heuristics + error handling

### Milestone 4 — Experimental providers (optional)

- Add additional providers behind a toggle
- Source badges + merge logic

---

## Risks & mitigations

1. **Credits incompleteness / mismatch**
   - Mitigation: multi-step matching, show confidence indicators, provide “Open source page” fallback

2. **Rate limiting**
   - Mitigation: aggressive caching, throttling, batch requests, only fetch on track change / popover open

3. **Spotify permission friction**
   - Mitigation: clear onboarding microcopy + “Why we need this” screen

4. **Using unofficial Spotify endpoints (if added)**
   - Mitigation: keep as “Experimental”, off by default, avoid if ToS risk is unacceptable

---

## Open questions

1. Do we require Spotify login (Web API) in v1, or avoid it entirely and rely on MusicBrainz search + AppleScript metadata?
2. What’s the minimum acceptable credits coverage for “success”? (e.g., 70% of tracks showing at least producer + writers?)
3. Should the app support “scrobble-like” history locally (last 20 tracks) for quick backtracking?
4. How should we handle compilations/VA tracks and classical recordings (complex credit structures)?
5. Do we want a “pin this credit view” window (non-popover) for longer reading?

---

## Appendix: Matching strategy (recommended v1)

**Best case**

- Spotify track ID → (optional Spotify API) ISRC → MusicBrainz ISRC lookup → Recording relationships → credits

**Fallback**

- title + primary artist → MusicBrainz search → select best candidate via heuristics → fetch relationships

**Confidence**

- Show “Matched via ISRC” vs “Matched via search” in Sources view to help users trust results.
