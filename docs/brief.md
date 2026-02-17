## 1) Menu bar app shell (SwiftUI)

If you’re on macOS 13+, SwiftUI’s `MenuBarExtra` makes this straightforward. ([Stack Overflow][2])
(If you need older macOS support, you can do `NSStatusBar`/`NSStatusItem` instead. ([polpiella.dev][3]))

UI pattern I’d use:

- Menu bar icon
- On click: a popover with
  - Track title / artist / album
  - Credits grouped by role (Musicians, Production, Writing, Engineering)
  - “Other versions” section
  - Links: Open in Spotify / Open in MusicBrainz

---

## 2) Get “currently playing” from the Spotify macOS app

### Easiest: AppleScript / ScriptingBridge

Spotify’s macOS app exposes the current track via AppleScript (`current track`, including the **Spotify URI** via `id of current track`). ([Stack Overflow][4])

Example AppleScript snippet (you can run this from Swift via `NSAppleScript` or `OSAScript`):

```applescript
tell application "Spotify"
  if player state is playing then
    set t to current track
    return (id of t) & "||" & (name of t) & "||" & (artist of t) & "||" & (album of t)
  else
    return ""
  end if
end tell
```

That `id` will look like `spotify:track:...` (a Spotify URI). ([Spotify for Developers][5])

**Important:** the first time you do this, macOS will prompt for **Automation / Apple Events permission** (“App wants to control Spotify”).

### Alternative: Spotify Web API “Get Playback State”

This gives you playback info for the user’s account/device, but it requires OAuth and the right scopes. ([Spotify for Developers][6])
For a simple “Spotify desktop app → menu bar credits” tool, AppleScript is usually the smoothest.

---

## 3) Convert “Now Playing” into stable IDs (Spotify track ID + ISRC)

From the AppleScript URI `spotify:track:6rqhFgbbKwnb9MLmUQDhG6`, parse the last segment as `trackId`.

Then call Spotify Web API **Get Track** to retrieve metadata, including `external_ids` (commonly includes **ISRC**). ([Spotify for Developers][7])

Why ISRC matters: it identifies the _recording_, and is the best bridge to external credit databases. ([MusicBrainz][8])

---

## 4) Fetch personnel/credits (best-effort, high coverage)

### Best “free + structured” source: MusicBrainz

MusicBrainz is built for exactly this kind of metadata linking. ([MusicBrainz][9])

Flow that works well:

**A) Lookup recording(s) by ISRC**

- `GET https://musicbrainz.org/ws/2/isrc/{ISRC}?fmt=json`
  - Returns recordings that match that ISRC. ([MetaBrainz Community Discourse][10])

**B) Pick the best recording**
Heuristics:

- Title similarity
- Artist credit match
- Prefer recordings tied to an official release

**C) Fetch relationships (the credits!)**
Once you have a MusicBrainz Recording MBID:

- `GET /ws/2/recording/{mbid}?inc=artist-rels+recording-rels+work-rels+url-rels&fmt=json`

Those `*-rels` are where you’ll commonly find:

- performers (instrument roles)
- producer
- engineer / mixing / mastering
- writers/composers via linked “work” relationships

MusicBrainz documents these “inc=” relationship includes and search patterns. ([MetaBrainz Community Discourse][11])

**D) “Other versions of the song”**
Two pragmatic interpretations:

1. **Other releases of the same recording/work** (singles, compilations, reissues)
2. **Related recordings** (remasters, radio edits, live, acoustic, covers)

MusicBrainz can get you there by:

- following the recording’s “work” link(s), then searching recordings for that work
- or browsing release groups / releases once you have the release/release-group MBIDs

---

## 5) Optional: Try to mirror Spotify’s in-app “Credits” (unofficial, may break)

There are community-documented endpoints under `spclient.wg.spotify.com` such as:

- `https://spclient.wg.spotify.com/track-credits-view/v0/experimental/{track-id}/credits` ([MetaBrainz Community Discourse][12])

And some people suggest grabbing a token from the Spotify web player endpoints. ([Spotify Community][13])

**Big caution:** this is **not the official Spotify Web API** and may violate terms, break without notice, or require token handling you may not want in a desktop utility. If you want something dependable, use MusicBrainz-first and treat Spotify-internal credits as a best-effort enhancement.

---

## 6) Putting it together: a clean architecture

**Core modules**

- `NowPlayingProvider`
  - `SpotifyAppleScriptNowPlayingProvider` (reads URI/title/artist/album locally)

- `MetadataResolver`
  - `SpotifyWebAPIResolver` (Track ID → ISRC, canonical artist/album, artwork)

- `CreditsProvider`
  - `MusicBrainzCreditsProvider` (ISRC/recording → role-grouped credits + related versions)
  - _(optional)_ `SpotifyInternalCreditsProvider` (trackId → Spotify-style credits)

- `CreditsMerger`
  - Normalize names/roles, dedupe, and decide precedence (e.g., Spotify-internal > MusicBrainz when both exist)

**Performance**

- Cache by `spotifyTrackId` and/or `isrc` (memory + disk)
- Refresh on track change (poll AppleScript every ~1–2s, or on menu open)

**UX**

- If credits are missing: show “No credits found” + “Search MusicBrainz” link + “Report mismatch” button (for your own debugging logs)

---

## If you want, I can sketch the Swift code skeleton

I can give you:

- a minimal `MenuBarExtra` app
- a `NowPlayingProvider` that runs the AppleScript and parses `spotify:track:…`
- the two HTTP calls (Spotify Get Track → ISRC, MusicBrainz ISRC lookup → relationships)
- and a simple SwiftUI popover that renders role-grouped credits

Just tell me whether you’re targeting **macOS 13+ only** (simpler with `MenuBarExtra`) or need **older macOS support** too.

[1]: https://community.spotify.com/t5/Spotify-for-Developers/Request-to-expose-track-level-credits-via-tracks-endpoint/td-p/7055523?utm_source=chatgpt.com "Request to expose track-level credits via /tracks endpoint"
[2]: https://stackoverflow.com/questions/64949572/how-to-create-status-bar-icon-and-menu-in-macos-using-swiftui?utm_source=chatgpt.com "How to create Status Bar icon and menu in macOS using ..."
[3]: https://www.polpiella.dev/a-menu-bar-only-macos-app-using-appkit/?utm_source=chatgpt.com "A menu bar only macOS app using AppKit"
[4]: https://stackoverflow.com/questions/12675168/spotify-applescript-add-current-track-to-playlist?utm_source=chatgpt.com "Spotify + AppleScript: Add current track to playlist"
[5]: https://developer.spotify.com/documentation/web-api/concepts/spotify-uris-ids?utm_source=chatgpt.com "Spotify URIs and IDs"
[6]: https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback?utm_source=chatgpt.com "Get Playback State"
[7]: https://developer.spotify.com/documentation/web-api/reference/get-track?utm_source=chatgpt.com "Get Track"
[8]: https://musicbrainz.org/doc/ISRC?utm_source=chatgpt.com "ISRC"
[9]: https://musicbrainz.org/doc/MusicBrainz_API?utm_source=chatgpt.com "MusicBrainz API"
[10]: https://community.metabrainz.org/t/getting-the-details-of-the-album-of-a-track-using-isrc-code/378302?utm_source=chatgpt.com "Getting the details of the album of a track using ISRC code"
[11]: https://community.metabrainz.org/t/how-to-include-work-level-rels-in-web-service-api-for-a-large-release/517922?utm_source=chatgpt.com "How to include work-level-rels in web service API for a ..."
[12]: https://community.metabrainz.org/t/a-multi-source-seeder-for-digital-releases/444000?page=17&utm_source=chatgpt.com "A multi‐source seeder for digital releases - Page 17"
[13]: https://community.spotify.com/t5/Spotify-for-Developers/Ability-to-retrieve-track-language/td-p/5437477?utm_source=chatgpt.com "Ability to retrieve track language"
