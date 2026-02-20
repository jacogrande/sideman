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
    private let maxTotalRecordings = 650
    private let maxHydratedWorks = 120
    private let canonicalMatchThreshold = 0.74

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
            "left_raw=\(discographyA.recordings.count) right_raw=\(discographyB.recordings.count) " +
            "left_canonical=\(intersection.leftCanonicalizedCount) right_canonical=\(intersection.rightCanonicalizedCount) " +
            "joined=\(intersection.recordings.count) " +
            "mbid=\(intersection.mbidMatches) isrc=\(intersection.isrcMatches) canonical=\(intersection.canonicalMatches) " +
            "variant_drops.left=\(intersection.leftVariantDrops) variant_drops.right=\(intersection.rightVariantDrops) " +
            "below_join_confidence=\(intersection.belowJoinConfidenceCount) " +
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
            let primaryRoleText = ([rec.relationshipType] + rec.attributes).joined(separator: " ")
            let evidenceRoleText = rec.evidence
                .map { evidence in ([evidence.relationshipType] + evidence.attributes).joined(separator: " ") }
                .joined(separator: " ")
            let roleText = [primaryRoleText, evidenceRoleText]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return CreditsMapper.roleGroup(forRoleText: roleText) == filter
        }
    }

    private func fetchAllDiscography(artistMBID: String, artistName: String) async throws -> DiscographyResult {
        let cacheKey = artistCacheKey(artistMBID)
        if let cached = await cache.get(for: cacheKey) {
            return cached
        }

        DebugLogger.log(.provider, "fetching discography for \(artistName) (\(artistMBID))")

        var recordingsByMBID: [String: ArtistRecordingRel] = [:]
        var stats = SourceCollectionStats()

        do {
            let rels = try await musicBrainzClient.getArtistRecordingRels(id: artistMBID)
            stats.recordingRels = rels.count

            for rel in rels {
                try Task.checkCancellation()
                upsertRecording(
                    rel,
                    artistMBID: artistMBID,
                    source: .recordingRel,
                    relationshipType: rel.relationshipType,
                    attributes: rel.attributes,
                    confidence: 1.0,
                    into: &recordingsByMBID
                )
                if recordingsByMBID.count >= maxTotalRecordings {
                    break
                }
            }
            DebugLogger.log(.provider, "recording-rels: \(rels.count) unique=\(recordingsByMBID.count)")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            DebugLogger.log(.provider, "recording-rels failed: \(error)")
        }

        do {
            var offset = 0
            let pageSize = 100
            var hasMore = true

            while hasMore && recordingsByMBID.count < maxTotalRecordings {
                try Task.checkCancellation()
                let page = try await musicBrainzClient.browseRecordings(
                    artistID: artistMBID,
                    offset: offset,
                    limit: pageSize,
                    includeISRCs: true
                )
                stats.browseRecordings += page.recordings.count

                for rec in page.recordings {
                    upsertRecording(
                        rec,
                        artistMBID: artistMBID,
                        source: .browseMain,
                        relationshipType: rec.relationshipType,
                        attributes: rec.attributes,
                        confidence: 0.90,
                        into: &recordingsByMBID
                    )
                    if recordingsByMBID.count >= maxTotalRecordings {
                        break
                    }
                }

                offset += page.recordings.count
                hasMore = offset < page.totalCount && !page.recordings.isEmpty
            }

            DebugLogger.log(.provider, "browse recordings complete total=\(recordingsByMBID.count)")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            DebugLogger.log(.provider, "browse recordings failed: \(error)")
        }

        do {
            let workRels = try await musicBrainzClient.getArtistWorkRels(id: artistMBID)
            stats.workRels = workRels.count

            for workRel in workRels {
                if recordingsByMBID.count >= maxTotalRecordings {
                    break
                }
                if stats.workHydrationAttempts >= maxHydratedWorks {
                    break
                }

                try Task.checkCancellation()
                stats.workHydrationAttempts += 1

                do {
                    let workRecordings = try await musicBrainzClient.getWorkRecordings(id: workRel.workMBID)
                    stats.workHydratedRecordings += workRecordings.count
                    for workRecording in workRecordings {
                        let mapped = ArtistRecordingRel(
                            recordingMBID: workRecording.recordingMBID,
                            recordingTitle: workRecording.recordingTitle,
                            relationshipType: workRel.relationshipType,
                            attributes: workRel.attributes,
                            artistCredits: workRecording.artistCredits,
                            isrcs: workRecording.isrcs
                        )
                        upsertRecording(
                            mapped,
                            artistMBID: artistMBID,
                            source: .workRel,
                            relationshipType: workRel.relationshipType,
                            attributes: workRel.attributes,
                            confidence: 0.74,
                            into: &recordingsByMBID
                        )
                        if recordingsByMBID.count >= maxTotalRecordings {
                            break
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    stats.workHydrationFailures += 1
                    DebugLogger.log(.provider, "work hydration failed for \(workRel.workMBID): \(error)")
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            DebugLogger.log(.provider, "work-rels failed: \(error)")
        }

        let allRecordings = recordingsByMBID.values.sorted(by: recordingSort(lhs:rhs:))
        guard !allRecordings.isEmpty else {
            throw PlaylistBuilderError.noRecordingsFound
        }

        DebugLogger.log(
            .provider,
            "discography sources for \(artistName): " +
            "recording_rels=\(stats.recordingRels) browse=\(stats.browseRecordings) " +
            "work_rels=\(stats.workRels) work_hydration_attempts=\(stats.workHydrationAttempts) " +
            "work_hydrated_recordings=\(stats.workHydratedRecordings) work_hydration_failures=\(stats.workHydrationFailures) " +
            "unique_recordings=\(allRecordings.count)"
        )

        let result = DiscographyResult(
            artistMBID: artistMBID,
            artistName: artistName,
            recordings: allRecordings,
            fetchedAt: Date()
        )

        await cache.set(result, for: cacheKey)
        return result
    }

    private func artistCacheKey(_ artistMBID: String) -> String {
        "artist:v2:\(artistMBID)"
    }

    private func coCreditCacheKey(artistAID: String, artistBID: String, matchMode: CoCreditMatchMode) -> String {
        let sorted = [artistAID, artistBID].sorted()
        return "co-credit:v2:\(sorted[0])|\(sorted[1])|\(matchMode.rawValue)"
    }

    private func intersectRecordings(lhs: [ArtistRecordingRel], rhs: [ArtistRecordingRel]) -> CoCreditIntersectionResult {
        let lhsCanonical = canonicalizeRecordings(lhs)
        let rhsCanonical = canonicalizeRecordings(rhs)

        let lhsByMBID = Dictionary(grouping: lhsCanonical.recordings, by: \.recordingMBID)
        let rhsByMBID = Dictionary(grouping: rhsCanonical.recordings, by: \.recordingMBID)
        let sharedIDs = Set(lhsByMBID.keys).intersection(rhsByMBID.keys)

        var merged: [ArtistRecordingRel] = []
        var matchedLHSIDs = Set<String>()
        var matchedRHSIDs = Set<String>()
        var mbidMatches = 0

        for recordingID in sharedIDs.sorted() {
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

        var unmatchedLHS = lhsCanonical.recordings.filter { !matchedLHSIDs.contains($0.recordingMBID) }
        var unmatchedRHS = rhsCanonical.recordings.filter { !matchedRHSIDs.contains($0.recordingMBID) }

        let isrcStage = matchByISRC(lhs: unmatchedLHS, rhs: unmatchedRHS)
        for match in isrcStage.matches {
            merged.append(match.recording)
            matchedLHSIDs.insert(match.leftMBID)
            matchedRHSIDs.insert(match.rightMBID)
        }
        unmatchedLHS = unmatchedLHS.filter { !isrcStage.matchedLeft.contains($0.recordingMBID) }
        unmatchedRHS = unmatchedRHS.filter { !isrcStage.matchedRight.contains($0.recordingMBID) }

        let canonicalStage = matchByCanonicalKey(lhs: unmatchedLHS, rhs: unmatchedRHS)
        for match in canonicalStage.matches {
            merged.append(match.recording)
            matchedLHSIDs.insert(match.leftMBID)
            matchedRHSIDs.insert(match.rightMBID)
        }

        let remainingLHS = lhsCanonical.recordings.filter { !matchedLHSIDs.contains($0.recordingMBID) }
        let remainingRHS = rhsCanonical.recordings.filter { !matchedRHSIDs.contains($0.recordingMBID) }

        let sortedRecordings = merged.sorted { lhs, rhs in
            lhs.recordingTitle.localizedCaseInsensitiveCompare(rhs.recordingTitle) == .orderedAscending
        }

        return CoCreditIntersectionResult(
            recordings: sortedRecordings,
            mbidMatches: mbidMatches,
            isrcMatches: isrcStage.matches.count,
            canonicalMatches: canonicalStage.matches.count,
            leftCanonicalizedCount: lhsCanonical.recordings.count,
            rightCanonicalizedCount: rhsCanonical.recordings.count,
            leftVariantDrops: lhsCanonical.variantDrops,
            rightVariantDrops: rhsCanonical.variantDrops,
            belowJoinConfidenceCount: canonicalStage.belowThresholdCount,
            leftOnlyCount: remainingLHS.count,
            rightOnlyCount: remainingRHS.count,
            leftOnlySample: Array(remainingLHS.prefix(4).map(\.recordingTitle)),
            rightOnlySample: Array(remainingRHS.prefix(4).map(\.recordingTitle))
        )
    }

    private func canonicalizeRecordings(_ recordings: [ArtistRecordingRel]) -> CanonicalizationResult {
        guard !recordings.isEmpty else {
            return CanonicalizationResult(recordings: [], variantDrops: 0)
        }

        var buckets: [String: [ArtistRecordingRel]] = [:]
        for recording in recordings {
            let key = canonicalJoinKey(for: recording)
            let keyed = recordingWithCanonicalKey(recording, key: key)
            buckets[key, default: []].append(keyed)
        }

        var canonicalized: [ArtistRecordingRel] = []
        var variantDrops = 0

        for (key, bucket) in buckets {
            guard var selected = preferredRecording(from: bucket) else {
                continue
            }
            for variant in bucket where variant.recordingMBID != selected.recordingMBID {
                selected = mergeRecordings(lhs: selected, rhs: variant)
            }
            canonicalized.append(recordingWithCanonicalKey(selected, key: key))
            variantDrops += max(0, bucket.count - 1)
        }

        canonicalized.sort(by: recordingSort(lhs:rhs:))
        return CanonicalizationResult(recordings: canonicalized, variantDrops: variantDrops)
    }

    private func matchByISRC(lhs: [ArtistRecordingRel], rhs: [ArtistRecordingRel]) -> StageMatchResult {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return StageMatchResult(matches: [], matchedLeft: [], matchedRight: [], belowThresholdCount: 0)
        }

        var rhsByISRC: [String: [ArtistRecordingRel]] = [:]
        for recording in rhs {
            for isrc in normalizedISRCs(recording) {
                rhsByISRC[isrc, default: []].append(recording)
            }
        }

        var usedRightMBIDs = Set<String>()
        var matchedLeft = Set<String>()
        var matches: [CoCreditFallbackMatch] = []

        for left in lhs.sorted(by: recordingSort(lhs:rhs:)) {
            let leftISRCs = normalizedISRCs(left)
            guard !leftISRCs.isEmpty else {
                continue
            }

            var scoredCandidates: [(recording: ArtistRecordingRel, score: Double)] = []
            var seen = Set<String>()
            for isrc in leftISRCs {
                for candidate in rhsByISRC[isrc, default: []] where !usedRightMBIDs.contains(candidate.recordingMBID) {
                    if !seen.insert(candidate.recordingMBID).inserted {
                        continue
                    }
                    let shared = sharedISRCs(left: left, right: candidate).count
                    let titleSimilarity = CreditsTextSimilarity.jaccardSimilarity(
                        normalizedCoCreditTitle(left.recordingTitle),
                        normalizedCoCreditTitle(candidate.recordingTitle),
                        containsMatchScore: 0.95
                    )
                    let score = Double(shared) + (0.05 * titleSimilarity)
                    scoredCandidates.append((candidate, score))
                }
            }

            guard let best = scoredCandidates.max(by: { lhs, rhs in
                if lhs.score == rhs.score {
                    return recordingSort(lhs: rhs.recording, rhs: lhs.recording)
                }
                return lhs.score < rhs.score
            }) else {
                continue
            }

            matches.append(
                CoCreditFallbackMatch(
                    recording: mergeRecordings(lhs: left, rhs: best.recording),
                    leftMBID: left.recordingMBID,
                    rightMBID: best.recording.recordingMBID
                )
            )
            matchedLeft.insert(left.recordingMBID)
            usedRightMBIDs.insert(best.recording.recordingMBID)
        }

        return StageMatchResult(
            matches: matches,
            matchedLeft: matchedLeft,
            matchedRight: usedRightMBIDs,
            belowThresholdCount: 0
        )
    }

    private func matchByCanonicalKey(lhs: [ArtistRecordingRel], rhs: [ArtistRecordingRel]) -> StageMatchResult {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return StageMatchResult(matches: [], matchedLeft: [], matchedRight: [], belowThresholdCount: 0)
        }

        var rhsByCanonical: [String: [ArtistRecordingRel]] = [:]
        for recording in rhs {
            let key = recording.canonicalKey ?? canonicalJoinKey(for: recording)
            rhsByCanonical[key, default: []].append(recordingWithCanonicalKey(recording, key: key))
        }

        var usedRightMBIDs = Set<String>()
        var matchedLeft = Set<String>()
        var matches: [CoCreditFallbackMatch] = []
        var belowThresholdCount = 0

        for left in lhs.sorted(by: recordingSort(lhs:rhs:)) {
            let key = left.canonicalKey ?? canonicalJoinKey(for: left)
            let candidates = rhsByCanonical[key, default: []]
                .filter { !usedRightMBIDs.contains($0.recordingMBID) }
            guard !candidates.isEmpty else {
                continue
            }

            let scoredCandidates = candidates.compactMap { candidate -> (recording: ArtistRecordingRel, score: Double)? in
                guard let score = canonicalMatchScore(left: left, right: candidate) else {
                    return nil
                }
                return (candidate, score)
            }

            guard let best = scoredCandidates.max(by: { lhs, rhs in
                if lhs.score == rhs.score {
                    return recordingSort(lhs: rhs.recording, rhs: lhs.recording)
                }
                return lhs.score < rhs.score
            }) else {
                belowThresholdCount += 1
                continue
            }

            matches.append(
                CoCreditFallbackMatch(
                    recording: mergeRecordings(lhs: left, rhs: best.recording),
                    leftMBID: left.recordingMBID,
                    rightMBID: best.recording.recordingMBID
                )
            )
            matchedLeft.insert(left.recordingMBID)
            usedRightMBIDs.insert(best.recording.recordingMBID)
        }

        return StageMatchResult(
            matches: matches,
            matchedLeft: matchedLeft,
            matchedRight: usedRightMBIDs,
            belowThresholdCount: belowThresholdCount
        )
    }

    private func canonicalMatchScore(left: ArtistRecordingRel, right: ArtistRecordingRel) -> Double? {
        let titleSimilarity = CreditsTextSimilarity.jaccardSimilarity(
            normalizedCoCreditTitle(left.recordingTitle),
            normalizedCoCreditTitle(right.recordingTitle),
            containsMatchScore: 0.95
        )
        guard titleSimilarity >= 0.82 else {
            return nil
        }

        let artistOverlap = artistCreditOverlapRatio(left: left, right: right) ?? 0
        let isrcBonus = sharedISRCs(left: left, right: right).isEmpty ? 0 : 0.10
        let score: Double

        if artistOverlap > 0 {
            score = (0.72 * titleSimilarity) + (0.28 * artistOverlap) + isrcBonus
            guard score >= canonicalMatchThreshold else {
                return nil
            }
        } else {
            score = (0.90 * titleSimilarity) + isrcBonus
            guard score >= 0.88 else {
                return nil
            }
        }

        return score
    }

    private func upsertRecording(
        _ recording: ArtistRecordingRel,
        artistMBID: String,
        source: InvolvementSource,
        relationshipType: String,
        attributes: [String],
        confidence: Double,
        into table: inout [String: ArtistRecordingRel]
    ) {
        let evidence = RecordingInvolvementEvidence(
            artistMBID: artistMBID,
            source: source,
            relationshipType: relationshipType,
            attributes: attributes,
            confidence: confidence
        )

        let enriched = ArtistRecordingRel(
            recordingMBID: recording.recordingMBID,
            recordingTitle: recording.recordingTitle,
            relationshipType: recording.relationshipType,
            attributes: mergedUnique(recording.attributes, attributes),
            artistCredits: recording.artistCredits,
            isrcs: recording.isrcs,
            evidence: mergedEvidence(recording.evidence, [evidence]),
            canonicalKey: recording.canonicalKey
        )

        if let existing = table[recording.recordingMBID] {
            table[recording.recordingMBID] = mergeRecordings(lhs: existing, rhs: enriched)
        } else {
            table[recording.recordingMBID] = enriched
        }
    }

    private func mergeRecordings(lhs: ArtistRecordingRel, rhs: ArtistRecordingRel) -> ArtistRecordingRel {
        let preferred = choosePreferred(lhs: lhs, rhs: rhs)
        return ArtistRecordingRel(
            recordingMBID: preferred.recordingMBID,
            recordingTitle: preferred.recordingTitle,
            relationshipType: preferred.relationshipType,
            attributes: mergedUnique(lhs.attributes, rhs.attributes),
            artistCredits: mergedUnique(lhs.artistCredits, rhs.artistCredits),
            isrcs: mergedUnique(lhs.isrcs, rhs.isrcs),
            evidence: mergedEvidence(lhs.evidence, rhs.evidence),
            canonicalKey: preferred.canonicalKey ?? lhs.canonicalKey ?? rhs.canonicalKey
        )
    }

    private func recordingWithCanonicalKey(_ recording: ArtistRecordingRel, key: String) -> ArtistRecordingRel {
        ArtistRecordingRel(
            recordingMBID: recording.recordingMBID,
            recordingTitle: recording.recordingTitle,
            relationshipType: recording.relationshipType,
            attributes: recording.attributes,
            artistCredits: recording.artistCredits,
            isrcs: recording.isrcs,
            evidence: recording.evidence,
            canonicalKey: key
        )
    }

    private func canonicalJoinKey(for recording: ArtistRecordingRel) -> String {
        let normalizedISRC = normalizedISRCs(recording).sorted().first
        if let normalizedISRC {
            return "isrc:\(normalizedISRC)"
        }

        let title = normalizedCoCreditTitle(recording.recordingTitle)
        if title.isEmpty {
            return "mbid:\(recording.recordingMBID)"
        }

        let fingerprint = normalizedArtistFingerprint(recording.artistCredits)
        if fingerprint.isEmpty {
            return "title:\(title)"
        }
        return "title:\(title)|artists:\(fingerprint)"
    }

    private func normalizedArtistFingerprint(_ credits: [String]) -> String {
        let normalized = credits
            .map { CreditsTextNormalizer.normalize($0, options: coCreditArtistNormalization) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else {
            return ""
        }
        let uniqueSorted = Array(Set(normalized)).sorted()
        return uniqueSorted.prefix(3).joined(separator: "&")
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
        normalizedISRCs(left).intersection(normalizedISRCs(right))
    }

    private func normalizedISRCs(_ recording: ArtistRecordingRel) -> Set<String> {
        Set(recording.isrcs.map { $0.uppercased() })
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
        var total = recording.isrcs.count * 4
        total += recording.artistCredits.count * 2
        total += sourceConfidenceScore(recording.evidence)
        if recording.relationshipType == "main" {
            total += 2
        }
        return total
    }

    private func sourceConfidenceScore(_ evidence: [RecordingInvolvementEvidence]) -> Int {
        evidence.reduce(0) { partial, item in
            let sourceValue: Int
            switch item.source {
            case .recordingRel:
                sourceValue = 4
            case .browseMain:
                sourceValue = 3
            case .workRel:
                sourceValue = 2
            }
            return partial + sourceValue
        }
    }

    private func recordingSort(lhs: ArtistRecordingRel, rhs: ArtistRecordingRel) -> Bool {
        let lhsScore = score(lhs)
        let rhsScore = score(rhs)
        if lhsScore == rhsScore {
            return lhs.recordingTitle.localizedCaseInsensitiveCompare(rhs.recordingTitle) == .orderedAscending
        }
        return lhsScore > rhsScore
    }

    private func mergedUnique(_ lhs: [String], _ rhs: [String]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        for value in lhs + rhs {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                ordered.append(trimmed)
            }
        }
        return ordered
    }

    private func mergedEvidence(
        _ lhs: [RecordingInvolvementEvidence],
        _ rhs: [RecordingInvolvementEvidence]
    ) -> [RecordingInvolvementEvidence] {
        var ordered: [RecordingInvolvementEvidence] = []
        var seen = Set<String>()

        for evidence in lhs + rhs {
            let key = evidenceKey(evidence)
            if seen.insert(key).inserted {
                ordered.append(evidence)
            }
        }
        return ordered
    }

    private func evidenceKey(_ evidence: RecordingInvolvementEvidence) -> String {
        let attrs = evidence.attributes.map { $0.lowercased() }.sorted().joined(separator: "|")
        return "\(evidence.artistMBID.lowercased())|\(evidence.source.rawValue)|\(evidence.relationshipType.lowercased())|\(attrs)"
    }

    private struct CoCreditFallbackMatch {
        let recording: ArtistRecordingRel
        let leftMBID: String
        let rightMBID: String
    }

    private struct StageMatchResult {
        let matches: [CoCreditFallbackMatch]
        let matchedLeft: Set<String>
        let matchedRight: Set<String>
        let belowThresholdCount: Int
    }

    private struct CanonicalizationResult {
        let recordings: [ArtistRecordingRel]
        let variantDrops: Int
    }

    private struct CoCreditIntersectionResult {
        let recordings: [ArtistRecordingRel]
        let mbidMatches: Int
        let isrcMatches: Int
        let canonicalMatches: Int
        let leftCanonicalizedCount: Int
        let rightCanonicalizedCount: Int
        let leftVariantDrops: Int
        let rightVariantDrops: Int
        let belowJoinConfidenceCount: Int
        let leftOnlyCount: Int
        let rightOnlyCount: Int
        let leftOnlySample: [String]
        let rightOnlySample: [String]
    }

    private struct SourceCollectionStats {
        var recordingRels: Int = 0
        var browseRecordings: Int = 0
        var workRels: Int = 0
        var workHydrationAttempts: Int = 0
        var workHydratedRecordings: Int = 0
        var workHydrationFailures: Int = 0
    }
}
