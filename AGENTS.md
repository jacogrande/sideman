# Repository Guidelines

## Project Structure & Module Organization
- This repository is currently docs-first.
- `docs/prd.md` contains product requirements and scope.
- `docs/brief.md` contains implementation notes, technical options, and references.
- Keep decisions and design changes in `docs/` until code is introduced. When app code is scaffolded, use a standard SwiftPM layout: `Sources/` for app modules, `Tests/` for unit tests, and `Assets/` for static resources.

## Build, Test, and Development Commands
- `ls docs` - quick inventory of repository content.
- `rg -n "TODO|FIXME|TBD" docs` - find unresolved doc items before opening a PR.
- `wc -w docs/*.md` - verify document size and conciseness.
- After Swift modules are added, use `swift build` to compile project targets.
- After Swift modules are added, use `swift test` to run automated test suites.

## Coding Style & Naming Conventions
- Markdown: use short sections, actionable bullets, and specific wording.
- Swift (when added): 4-space indentation; `UpperCamelCase` for types; `lowerCamelCase` for properties and functions.
- Use clear domain names for providers and services (for example, `NowPlayingProvider`, `CreditsProvider`, `MetadataResolver`).
- Keep files focused: one primary type per file, with small protocols for interchangeable providers.

## Testing Guidelines
- Use `XCTest` in `Tests/<ModuleName>Tests`.
- Name tests by behavior, for example `test_resolvesCreditsFromISRC()`.
- Prioritize unit coverage for parsing, identifier resolution, provider fallback, and cache behavior.
- Target strong coverage for core data logic (aim for at least 80% in provider/merging layers).

## Commit & Pull Request Guidelines
- Git history is not available in this directory today; use Conventional Commits going forward.
- Examples: `feat: add MusicBrainz lookup client`, `docs: clarify permissions flow`.
- PRs should include: summary of changes, rationale, test evidence (`swift test` output or manual validation), and screenshots for UI changes.
- Link the related issue/task when available.

## Security & Configuration Tips
- Never commit tokens, OAuth secrets, or local debug artifacts.
- Document any permission changes (especially macOS Automation/Apple Events for Spotify) in the PR description.
