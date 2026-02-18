import Foundation

actor ArtistDiscographyService {
    private let musicBrainzClient: MusicBrainzClient
    private let cache: DiscographyCache

    init(musicBrainzClient: MusicBrainzClient, cache: DiscographyCache) {
        self.musicBrainzClient = musicBrainzClient
        self.cache = cache
    }

    func fetchDiscography(artistMBID: String, artistName: String, roleFilter: CreditRoleGroup?) async throws -> DiscographyResult {
        if let cached = await cache.get(for: artistMBID) {
            let filtered = applyRoleFilter(cached.recordings, roleFilter: roleFilter)
            return DiscographyResult(
                artistMBID: cached.artistMBID,
                artistName: cached.artistName,
                recordings: filtered,
                fetchedAt: cached.fetchedAt
            )
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

        let filtered = applyRoleFilter(allRecordings, roleFilter: roleFilter)
        return DiscographyResult(
            artistMBID: artistMBID,
            artistName: artistName,
            recordings: filtered,
            fetchedAt: result.fetchedAt
        )
    }

    private func applyRoleFilter(_ recordings: [ArtistRecordingRel], roleFilter: CreditRoleGroup?) -> [ArtistRecordingRel] {
        guard let filter = roleFilter else { return recordings }

        return recordings.filter { rec in
            let roleText = ([rec.relationshipType] + rec.attributes).joined(separator: " ")
            return CreditsMapper.roleGroup(forRoleText: roleText) == filter
        }
    }
}
