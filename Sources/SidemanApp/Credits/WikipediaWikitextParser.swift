import Foundation

struct DefaultWikipediaWikitextParser: WikipediaWikitextParser {
    private let attribution = "Wikipedia contributors (CC BY-SA)"
    private let trackTitleNormalizationOptions: TextNormalizationOptions = [.stripFeaturingSuffix, .alphanumericsOnly, .collapseWhitespace]
    // Track title matching stays slightly stricter to avoid false positives from noisy wikitext rows.
    private let trackTitleContainsMatchScore: Double = 0.86

    private static let lineItemPrefixRegex = makeRegex(#"^[\*#;:]+\s*"#)
    private static let scopeRegex = makeRegex(#"\(([^\)]*track[^\)]*)\)"#, options: [.caseInsensitive])
    private static let numericScopeRegex = makeRegex(#"\(([^)]+)\)\s*$"#)
    private static let trackRangeRegex = makeRegex(#"(\d+)\s*[-–]\s*(\d+)"#)
    private static let trackNumberRegex = makeRegex(#"\b(\d+)\b"#)
    private static let numberedTrackRegexes: [NSRegularExpression] = [
        makeRegex(#"\|\s*(\d+)\.?\s*\|?\s*\"([^\"]+)\""#, options: [.caseInsensitive]),
        makeRegex(#"\|\s*(\d+)\.?\s*\|?\s*''\[\[[^\]|]+\|([^\]]+)\]\]''"#, options: [.caseInsensitive]),
        makeRegex(#"\|\s*(\d+)\.\s*([^\|]+)$"#, options: [.caseInsensitive])
    ]
    private static let templateTrackTitleRegex = makeRegex(
        #"^\|\s*title\s*(\d+)\s*=\s*(.+)$"#,
        options: [.caseInsensitive]
    )
    private static let quotedTitleRegex = makeRegex(#"\"([^\"]+)\""#)
    private static let listIndexPrefixRegex = makeRegex(#"^#+\s*"#)
    private static let headingRegex = makeRegex(#"(?m)^(=+)\s*([^=\n]+?)\s*\1\s*$"#)
    private static let inlineTrackScopeRegex = makeRegex(#"\s+on\s+((?:all\s+)?tracks?\b.*)$"#, options: [.caseInsensitive])

    private static func makeRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are compile-time constants. Fail fast if one becomes invalid.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    func parse(page: WikipediaPageContent, for track: NowPlayingTrack) -> WikipediaParsedCredits {
        let normalized = sanitizeWikitext(page.wikitext)
        let trackListing = extractSection(matchingAny: ["track listing"], in: normalized)
        let trackMap = parseTrackListing(from: trackListing ?? "")
        let inferredTrack = resolveTrackNumber(for: track.title, using: trackMap)
        let matchedTrack = track.trackNumber ?? inferredTrack

        DebugLogger.log(
            .provider,
            "wikipedia parse page='\(page.title)' trackMatch=\(matchedTrack.map(String.init) ?? "nil") inferredTrack=\(inferredTrack.map(String.init) ?? "nil") parsedTrackRows=\(trackMap.count)"
        )

        guard let personnelSection = extractSection(
            matchingAny: ["personnel", "personnel and credits", "credits"],
            in: normalized
        ) else {
            DebugLogger.log(.provider, "wikipedia parse no personnel section found")
            return WikipediaParsedCredits(entries: [], matchedTrackNumber: matchedTrack)
        }

        let rawEntries = parsePersonnelEntries(from: personnelSection, page: page)
        let deduped = CreditsMapper.mergeDeduplicating(rawEntries)

        let filtered: [CreditEntry]
        if let matchedTrack {
            filtered = deduped.filter { $0.scope.applies(to: matchedTrack) }
        } else {
            filtered = deduped
        }

        DebugLogger.log(.provider, "wikipedia parse entries raw=\(rawEntries.count) deduped=\(deduped.count) filtered=\(filtered.count)")

        return WikipediaParsedCredits(entries: filtered, matchedTrackNumber: matchedTrack)
    }

    private func parsePersonnelEntries(from section: String, page: WikipediaPageContent) -> [CreditEntry] {
        if section.range(of: #"(?m)^\{\|"#, options: .regularExpression) != nil {
            return parseWikitableCredits(from: section, page: page)
        }

        let lines = section
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var entries: [CreditEntry] = []

        for line in lines {
            guard line.hasPrefix("*") || line.hasPrefix("#") || line.hasPrefix(":") || line.hasPrefix(";") else {
                continue
            }

            let item = stripLineItemPrefix(from: line)

            guard let split = splitPersonnelItem(item) else {
                // Name-only line: try extracting a numeric track scope.
                var nameCandidate = item
                let nameScope = extractScope(from: &nameCandidate)
                if nameScope != .albumWide {
                    let cleanedName = cleanupWikiMarkup(nameCandidate)
                    guard !cleanedName.isEmpty else { continue }
                    let entry = CreditEntry(
                        personName: cleanedName,
                        roleRaw: "performer",
                        roleGroup: .musicians,
                        sourceLevel: .recording,
                        instrument: nil,
                        source: .wikipedia,
                        scope: nameScope,
                        sourceURL: page.fullURL,
                        sourceAttribution: attribution
                    )
                    entries.append(entry)
                }
                continue
            }

            let cleanedName = cleanupWikiMarkup(split.name)
            let roleText = cleanupWikiMarkup(split.role)
            let segments = splitRoleSegments(roleText)

            for segment in segments {
                var segText = segment.text
                let beforeExtract = segText
                var scope = extractScope(from: &segText)
                // Only inherit group scope if no explicit scope was found (text unchanged).
                if scope == .albumWide, segText == beforeExtract, let groupScope = segment.groupScope {
                    scope = groupScope
                }
                let role = segText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !role.isEmpty else { continue }

                let roleGroup = CreditsMapper.roleGroup(forRoleText: role)
                let instrument = inferInstrument(role: role, roleGroup: roleGroup)
                let sourceLevel: CreditSourceLevel = (scope == .albumWide) ? .release : .recording

                let entry = CreditEntry(
                    personName: cleanedName,
                    roleRaw: role,
                    roleGroup: roleGroup,
                    sourceLevel: sourceLevel,
                    instrument: instrument,
                    source: .wikipedia,
                    scope: scope,
                    sourceURL: page.fullURL,
                    sourceAttribution: attribution
                )
                entries.append(entry)
            }
        }

        return entries
    }

    private func splitPersonnelItem(_ line: String) -> (name: String, role: String)? {
        let delimiters = [" – ", " — ", " - ", " : ", ": "]

        for delimiter in delimiters {
            if let range = line.range(of: delimiter) {
                let name = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let role = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

                if !name.isEmpty, !role.isEmpty {
                    return (name, role)
                }
            }
        }

        return nil
    }

    private struct RoleSegment {
        let text: String
        let groupScope: CreditScope?
    }

    /// Splits role text by semicolons (groups) then commas within each group, respecting parentheses.
    /// Items without a scope inherit the trailing scope of their semicolon group.
    private func splitRoleSegments(_ roleText: String) -> [RoleSegment] {
        let groups = splitParenAware(roleText, on: ";")
        var result: [RoleSegment] = []

        for group in groups {
            let converted = parenthesizeInlineTrackScope(group)
            let items = splitParenAware(converted, on: ",")

            // Determine group scope from the last item.
            var trailingText = items.last ?? ""
            let trailingScope = extractScope(from: &trailingText)
            let groupScope: CreditScope? = (trailingScope != .albumWide) ? trailingScope : nil

            for item in items {
                result.append(RoleSegment(text: item, groupScope: groupScope))
            }
        }

        if result.isEmpty {
            return [RoleSegment(text: roleText.trimmingCharacters(in: .whitespacesAndNewlines), groupScope: nil)]
        }

        return result
    }

    /// Splits text by a delimiter character and " and ", respecting parenthesized content.
    private func splitParenAware(_ text: String, on delimiter: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]
            if char == "(" {
                depth += 1
                current.append(char)
                index = text.index(after: index)
            } else if char == ")" {
                depth = max(0, depth - 1)
                current.append(char)
                index = text.index(after: index)
            } else if depth == 0, char == delimiter {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
                current = ""
                index = text.index(after: index)
            } else if depth == 0, delimiter == ",", text[index...].hasPrefix(" and ") {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
                current = ""
                index = text.index(index, offsetBy: 5)
            } else {
                current.append(char)
                index = text.index(after: index)
            }
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }

        return parts
    }

    private func stripLineItemPrefix(from line: String) -> String {
        let nsRange = NSRange(line.startIndex..., in: line)
        return Self.lineItemPrefixRegex.stringByReplacingMatches(in: line, options: [], range: nsRange, withTemplate: "")
    }

    /// Converts inline "on track(s) N, M" to parenthetical "(tracks N, M)" so the
    /// paren-aware splitter keeps track-list commas intact.
    private func parenthesizeInlineTrackScope(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = Self.inlineTrackScopeRegex.firstMatch(in: text, options: [], range: range),
              let fullRange = Range(match.range(at: 0), in: text),
              let captureRange = Range(match.range(at: 1), in: text) else {
            return text
        }
        let scopeContent = String(text[captureRange])
        let prefix = String(text[..<fullRange.lowerBound])
        return "\(prefix) (\(scopeContent))"
    }

    private func extractScope(from roleText: inout String) -> CreditScope {
        let range = NSRange(roleText.startIndex..., in: roleText)

        // First: try the existing "track" keyword pattern.
        if let match = Self.scopeRegex.firstMatch(in: roleText, options: [], range: range),
           let fullRange = Range(match.range(at: 0), in: roleText),
           let scopeRange = Range(match.range(at: 1), in: roleText) {
            let scopeText = String(roleText[scopeRange])
            roleText.removeSubrange(fullRange)
            roleText = roleText.trimmingCharacters(in: .whitespacesAndNewlines)
            return scopeFromText(scopeText)
        }

        // Second: try a trailing numeric parenthetical like (1, 3, 7).
        if let match = Self.numericScopeRegex.firstMatch(in: roleText, options: [], range: range),
           let fullRange = Range(match.range(at: 0), in: roleText),
           let scopeRange = Range(match.range(at: 1), in: roleText) {
            let candidate = String(roleText[scopeRange])
            if isNumericTrackList(candidate) {
                roleText.removeSubrange(fullRange)
                roleText = roleText.trimmingCharacters(in: .whitespacesAndNewlines)
                return scopeFromText(candidate)
            }
        }

        return .albumWide
    }

    private func scopeFromText(_ scopeText: String) -> CreditScope {
        let lowered = scopeText.lowercased()

        if lowered.contains("all tracks except") {
            return .trackUnknown
        }

        if lowered.contains("all tracks") {
            return .albumWide
        }

        let parsed = parseTrackReferences(from: lowered)
        if let range = parsed.range, parsed.explicitTracks.isEmpty {
            return .trackRange(range.lowerBound, range.upperBound)
        }

        if !parsed.allTracks.isEmpty {
            return .trackSpecific(Array(parsed.allTracks).sorted())
        }

        return .trackUnknown
    }

    private func parseTrackReferences(from value: String) -> (allTracks: Set<Int>, explicitTracks: Set<Int>, range: ClosedRange<Int>?) {
        var tracks = Set<Int>()
        var explicit = Set<Int>()
        var onlyRange: ClosedRange<Int>?
        let nsRange = NSRange(value.startIndex..., in: value)

        for match in Self.trackRangeRegex.matches(in: value, range: nsRange) {
            guard let leftRange = Range(match.range(at: 1), in: value),
                  let rightRange = Range(match.range(at: 2), in: value),
                  let left = Int(value[leftRange]),
                  let right = Int(value[rightRange]) else {
                continue
            }

            let start = min(left, right)
            let end = max(left, right)
            onlyRange = start...end
            for index in start...end {
                tracks.insert(index)
            }
        }

        for match in Self.trackNumberRegex.matches(in: value, range: nsRange) {
            guard let numberRange = Range(match.range(at: 1), in: value),
                  let number = Int(value[numberRange]) else {
                continue
            }

            tracks.insert(number)
            explicit.insert(number)
        }

        return (tracks, explicit, onlyRange)
    }

    private func isNumericTrackList(_ text: String) -> Bool {
        let stripped = text
            .replacingOccurrences(of: "and", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return false }
        return stripped.allSatisfy { $0.isNumber || $0.isWhitespace || $0 == "," || $0 == "-" || $0 == "–" }
    }

    private func inferInstrument(role: String, roleGroup: CreditRoleGroup) -> String? {
        guard roleGroup == .musicians else {
            return nil
        }

        let cleaned = role.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return nil
        }

        return cleaned
    }

    private func parseTrackListing(from section: String) -> [Int: String] {
        guard !section.isEmpty else {
            return [:]
        }

        var tracks: [Int: String] = [:]
        let lines = section.components(separatedBy: .newlines)
        var listIndex = 1

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            if let parsed = parseNumberedTrackLine(trimmed) {
                tracks[parsed.number] = parsed.title
                continue
            }

            if let parsed = parseTemplateTrackLine(trimmed) {
                tracks[parsed.number] = parsed.title
                continue
            }

            if trimmed.hasPrefix("#"), let title = extractListTrackTitle(from: trimmed) {
                if tracks[listIndex] == nil {
                    tracks[listIndex] = title
                }
                listIndex += 1
            }
        }

        return tracks
    }

    private func parseNumberedTrackLine(_ line: String) -> (number: Int, title: String)? {
        for regex in Self.numberedTrackRegexes {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  let numberRange = Range(match.range(at: 1), in: line),
                  let number = Int(line[numberRange]) else {
                continue
            }

            let titleRangeIndex = match.numberOfRanges > 2 ? 2 : 1
            guard let titleRange = Range(match.range(at: titleRangeIndex), in: line) else {
                continue
            }

            let title = cleanupWikiMarkup(String(line[titleRange]))
            if !title.isEmpty {
                return (number, title)
            }
        }

        return nil
    }

    private func parseTemplateTrackLine(_ line: String) -> (number: Int, title: String)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = Self.templateTrackTitleRegex.firstMatch(in: line, options: [], range: range),
              let numberRange = Range(match.range(at: 1), in: line),
              let number = Int(line[numberRange]),
              let titleRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let title = cleanupWikiMarkup(String(line[titleRange]))
        guard !title.isEmpty else {
            return nil
        }

        return (number, title)
    }

    private func extractQuotedTitle(from line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = Self.quotedTitleRegex.firstMatch(in: line, options: [], range: range),
              let capture = Range(match.range(at: 1), in: line) else {
            return nil
        }

        return cleanupWikiMarkup(String(line[capture]))
    }

    private func extractListTrackTitle(from line: String) -> String? {
        if let quoted = extractQuotedTitle(from: line) {
            return quoted
        }

        let nsRange = NSRange(line.startIndex..., in: line)
        var candidate = Self.listIndexPrefixRegex.stringByReplacingMatches(
            in: line,
            options: [],
            range: nsRange,
            withTemplate: ""
        )
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = candidate.range(of: " – ") ?? candidate.range(of: " - ") {
            candidate = String(candidate[..<separator.lowerBound])
        }

        let cleaned = cleanupWikiMarkup(candidate)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func resolveTrackNumber(for title: String, using tracks: [Int: String]) -> Int? {
        guard !tracks.isEmpty else {
            return nil
        }

        let normalizedTitle = CreditsTextNormalizer.normalize(title, options: trackTitleNormalizationOptions)
        guard !normalizedTitle.isEmpty else {
            return nil
        }

        var best: (number: Int, score: Double)?

        for (number, trackTitle) in tracks {
            let normalizedTrackTitle = CreditsTextNormalizer.normalize(trackTitle, options: trackTitleNormalizationOptions)
            let score = CreditsTextSimilarity.jaccardSimilarity(
                normalizedTitle,
                normalizedTrackTitle,
                containsMatchScore: trackTitleContainsMatchScore
            )
            if let current = best {
                if score > current.score {
                    best = (number, score)
                }
            } else {
                best = (number, score)
            }
        }

        guard let best, best.score >= 0.40 else {
            return nil
        }

        return best.number
    }

    private func extractSection(matchingAny candidates: [String], in text: String) -> String? {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = Self.headingRegex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else {
            return nil
        }

        for (index, match) in matches.enumerated() {
            guard let levelRange = Range(match.range(at: 1), in: text),
                  let titleRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let currentHeadingLevel = text[levelRange].count
            let title = text[titleRange].lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let isMatch = candidates.contains(where: { title.contains($0) })
            guard isMatch else {
                continue
            }

            let sectionStart = match.range.upperBound
            var sectionEnd = nsRange.upperBound
            if index + 1 < matches.count {
                for nextIndex in (index + 1)..<matches.count {
                    let nextMatch = matches[nextIndex]
                    guard let nextLevelRange = Range(nextMatch.range(at: 1), in: text) else {
                        continue
                    }

                    let nextHeadingLevel = text[nextLevelRange].count
                    // Keep nested subsections (e.g. ===Additional personnel===) inside the parent section.
                    if nextHeadingLevel <= currentHeadingLevel {
                        sectionEnd = nextMatch.range.location
                        break
                    }
                }
            }
            let sectionRange = NSRange(location: sectionStart, length: max(sectionEnd - sectionStart, 0))

            if let swiftRange = Range(sectionRange, in: text) {
                return String(text[swiftRange])
            }
        }

        return nil
    }

    // MARK: - Wikitable parsing

    private static let creditRoleByNameRegex = makeRegex(#"^([A-Za-z][A-Za-z\s]{0,40}?)\s+by\s+"#, options: [.caseInsensitive])

    private static let nonMusicalRolePrefixes = [
        "a&r", "management", "business management", "legal representation",
        "art direction", "art director", "design", "designer", "photography",
    ]

    private func parseWikitableCredits(from section: String, page: WikipediaPageContent) -> [CreditEntry] {
        // Strip table-close marker only when it appears on its own line.
        let cleaned = section.replacingOccurrences(of: #"(?m)^\|}\s*$"#, with: "", options: .regularExpression)
        let rows = cleaned.components(separatedBy: "|-")
        var entries: [CreditEntry] = []

        for row in rows {
            let trimmedRow = row.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRow.isEmpty else { continue }
            // Skip table-open markers.
            guard !trimmedRow.hasPrefix("{|") else { continue }
            // Skip header rows (cells start with !).
            guard !trimmedRow.hasPrefix("!") else { continue }

            let cells = extractWikitableCells(from: trimmedRow)

            guard !cells.isEmpty else { continue }

            // First cell may be a track number. Last cell is typically the notes/credits.
            let firstCell = cells[0].trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            let trackNumber = Int(firstCell)
            let scope: CreditScope = trackNumber.map { .trackSpecific([$0]) } ?? .albumWide

            // The notes/credits cell is the last cell (or the only cell).
            let rawNotesCell = cells.count > 1 ? cells[cells.count - 1] : cells[0]
            let notesCell = rawNotesCell
                .replacingOccurrences(of: #"</?small>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            let creditLines = notesCell.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { cleanupWikiMarkup($0) }
                .filter { !$0.isEmpty }

            for line in creditLines {
                let parsed = parseInvertedCreditLine(line)
                for (name, role) in parsed {
                    guard !isNonMusicalRole(role) else { continue }
                    let roleGroup = CreditsMapper.roleGroup(forRoleText: role)
                    let instrument = inferInstrument(role: role, roleGroup: roleGroup)
                    let sourceLevel: CreditSourceLevel = (scope == .albumWide) ? .release : .recording

                    entries.append(CreditEntry(
                        personName: name,
                        roleRaw: role,
                        roleGroup: roleGroup,
                        sourceLevel: sourceLevel,
                        instrument: instrument,
                        source: .wikipedia,
                        scope: scope,
                        sourceURL: page.fullURL,
                        sourceAttribution: attribution
                    ))
                }
            }
        }

        return entries
    }

    /// Extracts cells from a wikitable row, handling both inline `||` and multi-line `|` formats.
    /// In multi-line format, continuation lines (not starting with `|`) are appended to the current cell.
    private func extractWikitableCells(from row: String) -> [String] {
        // Try inline || separator first.
        let inlineCells = row.components(separatedBy: "||")
        if inlineCells.count > 1 {
            return inlineCells
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { cell -> String in
                    var c = cell
                    if c.hasPrefix("|") { c = String(c.dropFirst()) }
                    return c.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
        }

        // Multi-line format: each | starts a new cell, non-| lines continue the current cell.
        let lines = row.components(separatedBy: .newlines)
        var cells: [String] = []
        var current: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("|") {
                if let prev = current {
                    cells.append(prev)
                }
                current = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if !trimmed.isEmpty {
                if current != nil {
                    current! += "\n" + trimmed
                }
            }
        }
        if let last = current {
            cells.append(last)
        }

        return cells.filter { !$0.isEmpty }
    }

    private func parseInvertedCreditLine(_ line: String) -> [(name: String, role: String)] {
        // Try "Role by Name1 and Name2" format (anchored to line start).
        let nsRange = NSRange(line.startIndex..., in: line)
        if let match = Self.creditRoleByNameRegex.firstMatch(in: line, options: [], range: nsRange),
           let fullRange = Range(match.range, in: line),
           let roleRange = Range(match.range(at: 1), in: line) {
            let role = String(line[roleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let namesStr = stripLocationSuffix(String(line[fullRange.upperBound...]))
            if !role.isEmpty, !namesStr.isEmpty {
                let names = splitNames(namesStr)
                if !names.isEmpty {
                    return names.map { ($0, role) }
                }
            }
        }

        // Try "Role: Name1, Name2" format.
        if let colonIdx = line.range(of: ": ") {
            let role = String(line[..<colonIdx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let namesStr = stripLocationSuffix(String(line[colonIdx.upperBound...]))
            if !role.isEmpty, !namesStr.isEmpty {
                let names = splitNames(namesStr)
                if !names.isEmpty {
                    return names.map { ($0, role) }
                }
            }
        }

        return []
    }

    /// Strips " at Studio/Location" suffixes from a names string.
    private func stripLocationSuffix(_ text: String) -> String {
        guard let atRange = text.range(of: " at ", options: .caseInsensitive) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(text[..<atRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitNames(_ text: String) -> [String] {
        text.components(separatedBy: ", ")
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix("and ") ? String($0.dropFirst(4)).trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty }
    }

    private func isNonMusicalRole(_ role: String) -> Bool {
        let lowered = role.lowercased()
        return Self.nonMusicalRolePrefixes.contains { lowered.hasPrefix($0) || lowered == $0 }
    }

    private func sanitizeWikitext(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(?s)<!--.*?-->"#, with: " ", options: .regularExpression)
            // Remove self-closing refs FIRST so they don't get mismatched as opening tags.
            .replacingOccurrences(of: #"<ref\b[^>]*/>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<ref\b[^>]*>.*?</ref>"#, with: " ", options: .regularExpression)
    }

    private func cleanupWikiMarkup(_ value: String) -> String {
        var output = value
        output = output.replacingOccurrences(of: #"\[\[([^\]|]+)\|([^\]]+)\]\]"#, with: "$2", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\[\[([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\{\{[^\}]*\}\}"#, with: " ", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\[[0-9]+\]"#, with: " ", options: .regularExpression)
        output = output.replacingOccurrences(of: "''", with: "")
        output = output.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
