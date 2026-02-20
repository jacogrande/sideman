import Foundation

actor ArtistDiscographyService {
    private let musicBrainzClient: MusicBrainzClient
    private let cache: DiscographyCache
    private let coCreditTitleNormalization: TextNormalizationOptions = [
        .stripFeaturingSuffix,
        .stripParentheticalText,
        .alphanumericsOnly,
        .collapseWhitespace
    ]
    private let coCreditArtistNormalization: TextNormalizationOptions = [.alphanumericsOnly, .collapseWhitespace]

    init(musicBrainzClient: MusicBrainzClient, cache: DiscographyCache) {
        self.musicBrainzClient = musicBrainzClient
        self.cache = cache
    }

    func fetchDiscography(artistMBID: String, artistName: String, roleFilter: CreditRoleGroup?) async throws -> DiscographyResult {
        let all = try await fetchAllDiscography(artistMBID: artistMBID, artistName: artistName)
        let filtered = applyRoleFilter(all.recordings, roleFilter: roleFilter)

        return DiscographyResult(
            artistMBID: all.artistMBID,
            artistName: all.artistName,
            recordings: filtered,
            fetchedAt: all.fetchedAt
        )
    }

    func fetchCoCreditDiscography(
        artistA: CoCreditArtist,
        artistB: CoCreditArtist,
        matchMode: CoCreditMatchMode
    ) async throws -> DiscographyResult {
        let pairKey = coCreditCacheKey(artistAID: artistA.mbid, artistBID: artistB.mbid, matchMode: matchMode)
        if let cached = await cache.get(for: pairKey) {
            return cached
        }

        let discographyA = try await fetchAllDiscography(artistMBID: artistA.mbid, artistName: artistA.name)
        let discographyB = try await fetchAllDiscography(artistMBID: artistB.mbid, artistName: artistB.name)

        let intersection: CoCreditIntersectionResult
        switch matchMode {
        case .anyInvolvement:
            intersection = intersectRecordings(lhs: discographyA.recordings, rhs: discographyB.recordings)
        }

        DebugLogger.log(
            .provider,
            "co-credit join '\(artistA.name)' x '\(artistB.name)': " +
            "left=\(discographyA.recordings.count) right=\(discographyB.recordings.count) " +
            "joined=\(intersection.recordings.count) mbid=\(intersection.mbidMatches) fallback=\(intersection.fallbackMatches) " +
            "not_in_intersection.left=\(intersection.leftOnlyCount) not_in_intersection.right=\(intersection.rightOnlyCount)"
        )

        if !intersection.leftOnlySample.isEmpty || !intersection.rightOnlySample.isEmpty {
            DebugLogger.log(
                .provider,
                "co-credit unmatched samples left=\(intersection.leftOnlySample.joined(separator: " | ")) right=\(intersection.rightOnlySample.joined(separator: " | "))"
            )
        }

        guard !intersection.recordings.isEmpty else {
            throw PlaylistBuilderError.noIntersectionFound
        }

        let result = DiscographyResult(
            artistMBID: pairKey,
            artistName: "\(artistA.name) × \(artistB.name)",
            recordings: intersection.recordings,
            fetchedAt: Date()
        )

        await cache.set(result, for: pairKey)
        return result
    }

    private func applyRoleFilter(_ recordings: [ArtistRecordingRel], roleFilter: CreditRoleGroup?) -> [ArtistRecordingRel] {
        guard let filter = roleFilter else { return recordings }

        return recordings.filter { rec in
            let roleText = ([rec.relationshipType] + rec.attributes).joined(separator: " ")
            return CreditsMapper.roleGroup(forRoleText: roleText) == filter
        }
    }

    private func fetchAllDiscography(artistMBID: String, artistName: String) async throws -> DiscographyResult {
        if let cached = await cache.get(for: artistMBID) {
            return cached
        }

        DebugLogger.log(.provider, "fetching discography for \(artistName) (\(artistMBID))")

        var allRecordings: [ArtistRecordingRel] = []
        var seenMBIDs = Set<String>()

        // Fetch recording-rels (session work, production, etc.)
        do {
            let rels = try await musicBrainzClient.getArtistRecordingRels(id: artistMBID)
            for rel in rels {
                if !seenMBIDs.contains(rel.recordingMBID) {
                    seenMBIDs.insert(rel.recordingMBID)
                    allRecordings.append(rel)
                }
            }
            DebugLogger.log(.provider, "recording-rels: \(rels.count) unique=\(seenMBIDs.count)")
        } catch {
            DebugLogger.log(.provider, "recording-rels failed: \(error)")
        }

        // Supplement with browse recordings (main-artist tracks), capped to avoid
        // unbounded pagination for prolific artists
        let maxTotalRecordings = 500
        do {
            var offset = 0
            let pageSize = 100
            var hasMore = true

            while hasMore && allRecordings.count < maxTotalRecordings {
                try Task.checkCancellation()
                let page = try await musicBrainzClient.browseRecordings(
                    artistID: artistMBID,
                    offset: offset,
                    limit: pageSize,
                    includeISRCs: true
                )

                for rec in page.recordings {
                    if !seenMBIDs.contains(rec.recordingMBID) {
                        seenMBIDs.insert(rec.recordingMBID)
                        allRecordings.append(rec)
                    }
                }

                offset += page.recordings.count
                hasMore = offset < page.totalCount && !page.recordings.isEmpty
            }

            DebugLogger.log(.provider, "browse recordings complete total=\(allRecordings.count)")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            DebugLogger.log(.provider, "browse recordings failed: \(error)")
        }

        guard !allRecordings.isEmpty else {
            throw PlaylistBuilderError.noRecordingsFound
        }

        let result = DiscographyResult(
            artistMBID: artistMBID,
            artistName: artistName,
            recordings: allRecordings,
            fetchedAt: Date()
        )

        await cache.set(result, for: artistMBID)
        return result
    }

    private func coCreditCacheKey(artistAID: String, artistBID: String, matchMode: CoCreditMatchMode) -> String {
        let sorted = [artistAID, artistBID].sorted()
        return "co-credit:\(sorted[0])|\(sorted[1])|\(matchMode.rawValue)"
    }

    private func intersectRecordings(lhs: [ArtistRecordingRel], rhs: [ArtistRecordingRel]) -> CoCreditIntersectionResult {
        let lhsByMBID = Dictionary(grouping: lhs, by: \.recordingMBID)
        let rhsByMBID = Dictionary(grouping: rhs, by: \.recordingMBID)
        let sharedIDs = Set(lhsByMBID.keys).intersection(rhsByMBID.keys)

        var merged: [ArtistRecordingRel] = []
        var matchedLHSIDs = Set<String>()
        var matchedRHSIDs = Set<String>()
        var mbidMatches = 0

        for recordingID in sharedIDs {
            guard
                let lhsBest = lhsByMBID[recordingID].flatMap(preferredRecording(from:)),
                let rhsBest = rhsByMBID[recordingID].flatMap(preferredRecording(from:))
            else {
                continue
            }

            merged.append(mergeRecordings(lhs: lhsBest, rhs: rhsBest))
            matchedLHSIDs.insert(lhsBest.recordingMBID)
            matchedRHSIDs.insert(rhsBest.recordingMBID)
            mbidMatches += 1
        }

        let unmatchedLHS = lhs.filter { !matchedLHSIDs.contains($0.recordingMBID) }
        let unmatchedRHS = rhs.filter { !matchedRHSIDs.contains($0.recordingMBID) }

        let fallbackMatches = fallbackMatches(lhs: unmatchedLHS, rhs: unmatchedRHS)
        for match in fallbackMatches {
            merged.append(match.recording)
            matchedLHSIDs.insert(match.leftMBID)
            matchedRHSIDs.insert(match.rightMBID)
        }

        let sortedRecordings = merged.sorted { lhs, rhs in
            lhs.recordingTitle.localizedCaseInsensitiveCompare(rhs.recordingTitle) == .orderedAscending
        }
        let leftOnlySample = unmatchedLHS
            .filter { !matchedLHSIDs.contains($0.recordingMBID) }
            .prefix(4)
            .map(\.recordingTitle)
        let rightOnlySample = unmatchedRHS
            .filter { !matchedRHSIDs.contains($0.recordingMBID) }
            .prefix(4)
            .map(\.recordingTitle)

        return CoCreditIntersectionResult(
            recordings: sortedRecordings,
            mbidMatches: mbidMatches,
            fallbackMatches: fallbackMatches.count,
            leftOnlyCount: lhs.count - matchedLHSIDs.count,
            rightOnlyCount: rhs.count - matchedRHSIDs.count,
            leftOnlySample: Array(leftOnlySample),
            rightOnlySample: Array(rightOnlySample)
        )
    }

    private func mergeRecordings(lhs: ArtistRecordingRel, rhs: ArtistRecordingRel) -> ArtistRecordingRel {
        let preferred = choosePreferred(lhs: lhs, rhs: rhs)
        return ArtistRecordingRel(
            recordingMBID: preferred.recordingMBID,
            recordingTitle: preferred.recordingTitle,
            relationshipType: preferred.relationshipType,
            attributes: mergedUnique(lhs.attributes, rhs.attributes),
            artistCredits: mergedUnique(lhs.artistCredits, rhs.artistCredits),
            isrcs: mergedUnique(lhs.isrcs, rhs.isrcs)
        )
    }

    private struct CoCreditFallbackMatch {
        let recording: ArtistRecordingRel
        let leftMBID: String
        let rightMBID: String
    }

    private struct CoCreditIntersectionResult {
        let recordings: [ArtistRecordingRel]
        let mbidMatches: Int
        let fallbackMatches: Int
        let leftOnlyCount: Int
        let rightOnlyCount: Int
        let leftOnlySample: [String]
        let rightOnlySample: [String]
    }

    private func fallbackMatches(lhs: [ArtistRecordingRel], rhs: [ArtistRecordingRel]) -> [CoCreditFallbackMatch] {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return []
        }

        var rhsByTitle: [String: [ArtistRecordingRel]] = [:]
        for recording in rhs {
            let key = normalizedCoCreditTitle(recording.recordingTitle)
            guard !key.isEmpty else {
                continue
            }
            rhsByTitle[key, default: []].append(recording)
        }

        var usedRightMBIDs = Set<String>()
        var matches: [CoCreditFallbackMatch] = []

        for left in lhs.sorted(by: { $0.recordingTitle.localizedCaseInsensitiveCompare($1.recordingTitle) == .orderedAscending }) {
            let titleKey = normalizedCoCreditTitle(left.recordingTitle)
            guard !titleKey.isEmpty else {
                continue
            }

            let candidates = rhsByTitle[titleKey, default: []]
                .filter { !usedRightMBIDs.contains($0.recordingMBID) }
            guard !candidates.isEmpty else {
                continue
            }

            let scored = candidates.compactMap { right -> (recording: ArtistRecordingRel, rightMBID: String, score: Double)? in
                guard let score = fallbackMatchScore(left: left, right: right) else {
                    return nil
                }
                return (mergeRecordings(lhs: left, rhs: right), right.recordingMBID, score)
            }

            guard let best = scored.max(by: { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.recording.recordingTitle.localizedCaseInsensitiveCompare(rhs.recording.recordingTitle) == .orderedDescending
                }
                return lhs.score < rhs.score
            }) else {
                continue
            }

            matches.append(
                CoCreditFallbackMatch(
                    recording: best.recording,
                    leftMBID: left.recordingMBID,
                    rightMBID: best.rightMBID
                )
            )
            usedRightMBIDs.insert(best.rightMBID)
        }

        return matches
    }

    private func fallbackMatchScore(left: ArtistRecordingRel, right: ArtistRecordingRel) -> Double? {
        let sharedISRCCount = sharedISRCs(left: left, right: right).count
        if sharedISRCCount > 0 {
            return 1.20 + 0.05 * Double(min(sharedISRCCount, 3))
        }

        let titleSimilarity = CreditsTextSimilarity.jaccardSimilarity(
            normalizedCoCreditTitle(left.recordingTitle),
            normalizedCoCreditTitle(right.recordingTitle),
            containsMatchScore: 0.95
        )
        guard titleSimilarity >= 0.86 else {
            return nil
        }

        guard let artistOverlap = artistCreditOverlapRatio(left: left, right: right), artistOverlap >= 0.34 else {
            return nil
        }

        return (0.70 * titleSimilarity) + (0.30 * artistOverlap)
    }

    private func normalizedCoCreditTitle(_ title: String) -> String {
        var trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dashRange = trimmed.range(of: " - ") {
            let beforeDash = String(trimmed[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !beforeDash.isEmpty {
                trimmed = beforeDash
            }
        }
        return CreditsTextNormalizer.normalize(trimmed, options: coCreditTitleNormalization)
    }

    private func artistCreditOverlapRatio(left: ArtistRecordingRel, right: ArtistRecordingRel) -> Double? {
        let leftArtists = Set(
            left.artistCredits
                .map { CreditsTextNormalizer.normalize($0, options: coCreditArtistNormalization) }
                .filter { !$0.isEmpty }
        )
        let rightArtists = Set(
            right.artistCredits
                .map { CreditsTextNormalizer.normalize($0, options: coCreditArtistNormalization) }
                .filter { !$0.isEmpty }
        )

        guard !leftArtists.isEmpty, !rightArtists.isEmpty else {
            return nil
        }

        let overlap = leftArtists.intersection(rightArtists).count
        if overlap == 0 {
            return nil
        }

        let baseline = min(leftArtists.count, rightArtists.count)
        guard baseline > 0 else {
            return nil
        }
        return Double(overlap) / Double(baseline)
    }

    private func sharedISRCs(left: ArtistRecordingRel, right: ArtistRecordingRel) -> Set<String> {
        let leftISRCs = Set(left.isrcs.map { $0.uppercased() })
        let rightISRCs = Set(right.isrcs.map { $0.uppercased() })
        return leftISRCs.intersection(rightISRCs)
    }

    private func preferredRecording(from candidates: [ArtistRecordingRel]) -> ArtistRecordingRel? {
        candidates.max { lhs, rhs in
            let lhsScore = score(lhs)
            let rhsScore = score(rhs)
            if lhsScore == rhsScore {
                return lhs.recordingTitle.localizedCaseInsensitiveCompare(rhs.recordingTitle) == .orderedDescending
            }
            return lhsScore < rhsScore
        }
    }

    private func choosePreferred(lhs: ArtistRecordingRel, rhs: ArtistRecordingRel) -> ArtistRecordingRel {
        score(lhs) >= score(rhs) ? lhs : rhs
    }

    private func score(_ recording: ArtistRecordingRel) -> Int {
        var total = recording.isrcs.count * 3
        if recording.relationshipType == "main" {
            total += 1
        }
        total += recording.artistCredits.count
        return total
    }

    private func mergedUnique(_ lhs: [String], _ rhs: [String]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        for value in lhs + rhs {
            let key = value.lowercased()
            if seen.insert(key).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }
}
