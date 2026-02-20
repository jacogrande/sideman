import Foundation

actor ArtistDiscographyService {
    private let musicBrainzClient: MusicBrainzClient
    private let cache: DiscographyCache

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

        let intersected: [ArtistRecordingRel]
        switch matchMode {
        case .anyInvolvement:
            intersected = intersectRecordings(lhs: discographyA.recordings, rhs: discographyB.recordings)
        }

        guard !intersected.isEmpty else {
            throw PlaylistBuilderError.noIntersectionFound
        }

        let result = DiscographyResult(
            artistMBID: pairKey,
            artistName: "\(artistA.name) × \(artistB.name)",
            recordings: intersected,
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

    private func intersectRecordings(lhs: [ArtistRecordingRel], rhs: [ArtistRecordingRel]) -> [ArtistRecordingRel] {
        let lhsByMBID = Dictionary(grouping: lhs, by: \.recordingMBID)
        let rhsByMBID = Dictionary(grouping: rhs, by: \.recordingMBID)
        let sharedIDs = Set(lhsByMBID.keys).intersection(rhsByMBID.keys)

        return sharedIDs.compactMap { recordingID in
            guard
                let lhsBest = lhsByMBID[recordingID].flatMap(preferredRecording(from:)),
                let rhsBest = rhsByMBID[recordingID].flatMap(preferredRecording(from:))
            else {
                return nil
            }

            let preferred = choosePreferred(lhs: lhsBest, rhs: rhsBest)
            return ArtistRecordingRel(
                recordingMBID: preferred.recordingMBID,
                recordingTitle: preferred.recordingTitle,
                relationshipType: preferred.relationshipType,
                attributes: mergedUnique(lhsBest.attributes, rhsBest.attributes),
                artistCredits: mergedUnique(lhsBest.artistCredits, rhsBest.artistCredits),
                isrcs: mergedUnique(lhsBest.isrcs, rhsBest.isrcs)
            )
        }
        .sorted { lhs, rhs in
            lhs.recordingTitle.localizedCaseInsensitiveCompare(rhs.recordingTitle) == .orderedAscending
        }
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
