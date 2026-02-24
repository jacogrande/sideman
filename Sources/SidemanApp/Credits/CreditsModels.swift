import Foundation

enum CreditsLookupState: Equatable, Codable {
    case idle
    case resolving
    case loadingCredits
    case loaded
    case notFound
    case ambiguous
    case rateLimited
    case error(String)
}

enum CreditSource: String, Codable, Hashable {
    case wikipedia
    case musicBrainz

    var title: String {
        switch self {
        case .wikipedia:
            return "Wikipedia"
        case .musicBrainz:
            return "MusicBrainz"
        }
    }
}

enum CreditRoleGroup: String, CaseIterable, Hashable, Codable {
    case musicians
    case production
    case writing
    case engineering
    case misc

    var title: String {
        switch self {
        case .musicians:
            return "Musicians"
        case .production:
            return "Production"
        case .writing:
            return "Writing"
        case .engineering:
            return "Engineering"
        case .misc:
            return "Misc"
        }
    }

    var filterLabel: String {
        switch self {
        case .musicians: return "Musician"
        case .production: return "Producer"
        case .writing: return "Songwriter"
        case .engineering: return "Engineer"
        case .misc: return "Contributor"
        }
    }

    static var displayOrder: [CreditRoleGroup] {
        [.musicians, .production, .writing, .engineering, .misc]
    }
}

enum CreditScope: Hashable, Codable {
    case albumWide
    case trackSpecific([Int])
    case trackRange(Int, Int)
    case trackUnknown

    var label: String {
        switch self {
        case .albumWide:
            return "Album-wide"
        case .trackSpecific(let tracks):
            if tracks.count == 1, let first = tracks.first {
                return "Track \(first)"
            }
            return "Tracks \(Self.compactTrackList(tracks.sorted()))"
        case .trackRange(let start, let end):
            return "Tracks \(start)–\(end)"
        case .trackUnknown:
            return "Track-specific"
        }
    }

    /// Compresses a sorted list of track numbers into a compact string with ranges.
    /// e.g. [1, 3, 4, 5, 6, 7, 11, 12] → "1, 3–7, 11, 12"
    static func compactTrackList(_ sorted: [Int]) -> String {
        guard !sorted.isEmpty else { return "" }
        var parts: [String] = []
        var rangeStart = sorted[0]
        var rangeEnd = sorted[0]

        for i in 1..<sorted.count {
            if sorted[i] == rangeEnd + 1 {
                rangeEnd = sorted[i]
            } else {
                parts.append(rangeEnd > rangeStart ? "\(rangeStart)–\(rangeEnd)" : "\(rangeStart)")
                rangeStart = sorted[i]
                rangeEnd = sorted[i]
            }
        }
        parts.append(rangeEnd > rangeStart ? "\(rangeStart)–\(rangeEnd)" : "\(rangeStart)")
        return parts.joined(separator: ", ")
    }

    func applies(to trackNumber: Int?) -> Bool {
        switch self {
        case .albumWide, .trackUnknown:
            return true
        case .trackSpecific(let tracks):
            guard let trackNumber else {
                return true
            }
            return tracks.contains(trackNumber)
        case .trackRange(let start, let end):
            guard let trackNumber else {
                return true
            }
            return (start...end).contains(trackNumber)
        }
    }
}

enum CreditSourceLevel: String, Codable, Hashable {
    case recording
    case work
    case release

    var sortRank: Int {
        switch self {
        case .recording:
            return 0
        case .work:
            return 1
        case .release:
            return 2
        }
    }

    var badgeTitle: String {
        switch self {
        case .recording:
            return "Track"
        case .work:
            return "Work"
        case .release:
            return "Release"
        }
    }
}

struct CreditEntry: Equatable, Hashable, Codable {
    let personName: String
    let personMBID: String?
    let roleRaw: String
    let roleGroup: CreditRoleGroup
    let sourceLevel: CreditSourceLevel
    let instrument: String?
    let source: CreditSource
    let scope: CreditScope
    let sourceURL: String?
    let sourceAttribution: String?

    init(
        personName: String,
        personMBID: String? = nil,
        roleRaw: String,
        roleGroup: CreditRoleGroup,
        sourceLevel: CreditSourceLevel = .recording,
        instrument: String? = nil,
        source: CreditSource = .musicBrainz,
        scope: CreditScope = .albumWide,
        sourceURL: String? = nil,
        sourceAttribution: String? = nil
    ) {
        self.personName = personName
        self.personMBID = personMBID
        self.roleRaw = roleRaw
        self.roleGroup = roleGroup
        self.sourceLevel = sourceLevel
        self.instrument = instrument
        self.source = source
        self.scope = scope
        self.sourceURL = sourceURL
        self.sourceAttribution = sourceAttribution
    }
}

struct CreditsBundle: Equatable, Codable {
    let entriesByGroup: [CreditRoleGroup: [CreditEntry]]
    let provenance: [CreditSourceLevel]
    let resolvedRecordingMBID: String
    let sourceID: String?
    let sourceName: String?
    let sourcePageTitle: String?
    let sourcePageURL: String?
    let sourceAttribution: String?
    let matchedTrackNumber: Int?

    init(
        entriesByGroup: [CreditRoleGroup: [CreditEntry]],
        provenance: [CreditSourceLevel],
        resolvedRecordingMBID: String,
        sourceID: String? = nil,
        sourceName: String? = nil,
        sourcePageTitle: String? = nil,
        sourcePageURL: String? = nil,
        sourceAttribution: String? = nil,
        matchedTrackNumber: Int? = nil
    ) {
        self.entriesByGroup = entriesByGroup
        self.provenance = provenance
        self.resolvedRecordingMBID = resolvedRecordingMBID
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.sourcePageTitle = sourcePageTitle
        self.sourcePageURL = sourcePageURL
        self.sourceAttribution = sourceAttribution
        self.matchedTrackNumber = matchedTrackNumber
    }

    var isEmpty: Bool {
        entriesByGroup.values.allSatisfy { $0.isEmpty }
    }

    var resolvedSourceID: String {
        sourceID ?? resolvedRecordingMBID
    }

    func entries(for group: CreditRoleGroup) -> [CreditEntry] {
        entriesByGroup[group] ?? []
    }
}

struct ResolutionResult: Equatable, Codable {
    let recordingMBID: String
    let releaseMBID: String?
    let workMBIDs: [String]
    let confidence: Double
}

struct RecordingQuery: Equatable {
    let title: String
    let artist: String
    let album: String
}

struct RecordingCandidate: Equatable {
    let recordingMBID: String
    let title: String
    let artistNames: [String]
    let releaseTitles: [String]
    let releaseIDs: [String]
    let musicBrainzScore: Int
}

enum ResolverError: Error, Equatable {
    case notFound
    case ambiguous
    case rateLimited
    case network(String)
}

enum MusicBrainzClientError: Error, Equatable {
    case notFound
    case rateLimited
    case httpStatus(Int)
    case decoding(String)
    case network(String)
}

enum WikipediaClientError: Error, Equatable {
    case notFound
    case rateLimited
    case httpStatus(Int)
    case decoding(String)
    case network(String)
}

enum DiscogsClientError: Error, Equatable {
    case unauthorized
    case rateLimited
    case httpStatus(Int)
    case decoding(String)
    case network(String)
}

struct WikipediaSearchResult: Equatable {
    let pageID: Int
    let title: String
    let snippet: String
}

struct WikipediaPageResolution: Equatable {
    let pageID: Int
    let title: String
    let confidence: Double
}

struct WikipediaPageContent: Equatable {
    let pageID: Int
    let title: String
    let fullURL: String
    let wikitext: String
}

struct WikipediaParsedCredits: Equatable {
    let entries: [CreditEntry]
    let matchedTrackNumber: Int?
}

struct MBRecordingDetail: Equatable {
    let id: String
    let title: String
    let relations: [MBRelationship]
    let releases: [MBReleaseSummary]
}

struct MBWorkDetail: Equatable {
    let id: String
    let title: String
    let relations: [MBRelationship]
}

struct MBReleaseDetail: Equatable {
    let id: String
    let title: String
    let relations: [MBRelationship]
}

struct MBReleaseSummary: Equatable {
    let id: String
    let title: String
}

struct MBRelationship: Equatable {
    let type: String
    let targetType: String?
    let attributes: [String]
    let artist: MBArtist?
    let work: MBWorkReference?
}

struct MBArtist: Equatable {
    let id: String?
    let name: String
}

struct MBWorkReference: Equatable {
    let id: String
    let title: String
    let relations: [MBRelationship]

    init(id: String, title: String, relations: [MBRelationship] = []) {
        self.id = id
        self.title = title
        self.relations = relations
    }
}

struct CachedCredits: Equatable, Codable {
    let key: String
    let state: CreditsLookupState
    let bundle: CreditsBundle?
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

// MARK: - Discography

struct ArtistRecordingRel: Equatable, Codable {
    let recordingMBID: String
    let recordingTitle: String
    let relationshipType: String
    let attributes: [String]
    let artistCredits: [String]
    let isrcs: [String]

    /// Optional metadata describing how this recording was discovered for a
    /// given artist (recording rel, browse main credit, or work-level link).
    let evidence: [RecordingInvolvementEvidence]

    /// Normalized identifier used to collapse remix/remaster/version variants.
    let canonicalKey: String?

    init(
        recordingMBID: String,
        recordingTitle: String,
        relationshipType: String,
        attributes: [String],
        artistCredits: [String],
        isrcs: [String],
        evidence: [RecordingInvolvementEvidence] = [],
        canonicalKey: String? = nil
    ) {
        self.recordingMBID = recordingMBID
        self.recordingTitle = recordingTitle
        self.relationshipType = relationshipType
        self.attributes = attributes
        self.artistCredits = artistCredits
        self.isrcs = isrcs
        self.evidence = evidence
        self.canonicalKey = canonicalKey
    }

    enum CodingKeys: String, CodingKey {
        case recordingMBID
        case recordingTitle
        case relationshipType
        case attributes
        case artistCredits
        case isrcs
        case evidence
        case canonicalKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordingMBID = try container.decode(String.self, forKey: .recordingMBID)
        recordingTitle = try container.decode(String.self, forKey: .recordingTitle)
        relationshipType = try container.decode(String.self, forKey: .relationshipType)
        attributes = try container.decodeIfPresent([String].self, forKey: .attributes) ?? []
        artistCredits = try container.decodeIfPresent([String].self, forKey: .artistCredits) ?? []
        isrcs = try container.decodeIfPresent([String].self, forKey: .isrcs) ?? []
        evidence = try container.decodeIfPresent([RecordingInvolvementEvidence].self, forKey: .evidence) ?? []
        canonicalKey = try container.decodeIfPresent(String.self, forKey: .canonicalKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recordingMBID, forKey: .recordingMBID)
        try container.encode(recordingTitle, forKey: .recordingTitle)
        try container.encode(relationshipType, forKey: .relationshipType)
        try container.encode(attributes, forKey: .attributes)
        try container.encode(artistCredits, forKey: .artistCredits)
        try container.encode(isrcs, forKey: .isrcs)
        try container.encode(evidence, forKey: .evidence)
        try container.encodeIfPresent(canonicalKey, forKey: .canonicalKey)
    }
}

enum InvolvementSource: String, Equatable, Codable, CaseIterable {
    case recordingRel
    case browseMain
    case workRel
}

struct RecordingInvolvementEvidence: Equatable, Codable {
    let artistMBID: String
    let source: InvolvementSource
    let relationshipType: String
    let attributes: [String]
    let confidence: Double

    init(
        artistMBID: String,
        source: InvolvementSource,
        relationshipType: String,
        attributes: [String],
        confidence: Double
    ) {
        self.artistMBID = artistMBID
        self.source = source
        self.relationshipType = relationshipType
        self.attributes = attributes
        self.confidence = confidence
    }
}

struct ArtistWorkRel: Equatable, Codable {
    let workMBID: String
    let workTitle: String
    let relationshipType: String
    let attributes: [String]
}

struct WorkRecordingRel: Equatable, Codable {
    let recordingMBID: String
    let recordingTitle: String
    let artistCredits: [String]
    let isrcs: [String]
}

struct DiscographyResult: Equatable, Codable {
    let artistMBID: String
    let artistName: String
    let recordings: [ArtistRecordingRel]
    let fetchedAt: Date
    let wasTruncated: Bool

    init(artistMBID: String, artistName: String, recordings: [ArtistRecordingRel], fetchedAt: Date, wasTruncated: Bool = false) {
        self.artistMBID = artistMBID
        self.artistName = artistName
        self.recordings = recordings
        self.fetchedAt = fetchedAt
        self.wasTruncated = wasTruncated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artistMBID = try container.decode(String.self, forKey: .artistMBID)
        artistName = try container.decode(String.self, forKey: .artistName)
        recordings = try container.decode([ArtistRecordingRel].self, forKey: .recordings)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        wasTruncated = try container.decodeIfPresent(Bool.self, forKey: .wasTruncated) ?? false
    }
}

struct MBBrowseRecordingsPage: Equatable {
    let recordings: [ArtistRecordingRel]
    let totalCount: Int
    let offset: Int
}

struct MBArtistSearchResult: Equatable {
    let id: String
    let name: String
    let score: Int
}

// MARK: - Popularity

struct RecordingPopularity: Equatable, Codable {
    let recordingMBID: String
    let listenCount: Int?
}

// MARK: - Track Matching

struct ResolvedTrack: Equatable {
    let recordingMBID: String
    let recordingTitle: String
    let spotifyURI: String
    let spotifyPopularity: Int?
    let matchStrategy: TrackMatchStrategy
}

enum TrackMatchStrategy: String, Equatable, Codable {
    case isrc
    case textSearch
}

enum TrackResolutionDropReason: String, Equatable, Codable {
    case missingArtistCredits
    case noSpotifyMatch
}

struct UnresolvedTrack: Equatable {
    let recordingMBID: String
    let recordingTitle: String
    let reason: TrackResolutionDropReason
}

struct TrackResolutionSummary: Equatable {
    let resolved: [ResolvedTrack]
    let unresolved: [UnresolvedTrack]
}

// MARK: - Spotify Domain Models

struct SpotifyTrack: Equatable {
    let id: String
    let name: String
    let uri: String
    let artistNames: [String]
    let albumName: String
    let isrc: String?
    let popularity: Int?
}

struct SpotifyPlaylist: Equatable {
    let id: String
    let name: String
    let url: String?
}

// MARK: - Spotify Auth

struct SpotifyTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var isExpiringSoon: Bool {
        Date() >= expiresAt.addingTimeInterval(-300)
    }
}

// MARK: - Playlist Building

enum PlaylistMode: String, Equatable, Codable, CaseIterable {
    case singleArtist
    case coCredit

    var title: String {
        switch self {
        case .singleArtist:
            return "Single Artist"
        case .coCredit:
            return "Co-Credit (AND)"
        }
    }
}

/// Determines how two artist discographies are intersected.
/// `.anyInvolvement` matches recordings where both artists appear in any role.
/// Future modes (e.g. role-specific matching) can be added here.
enum CoCreditMatchMode: String, Equatable, Codable {
    case anyInvolvement

    var title: String {
        switch self {
        case .anyInvolvement:
            return "Any involvement"
        }
    }
}

struct CoCreditArtist: Equatable, Codable {
    let name: String
    let mbid: String
}

struct CoCreditConfig: Equatable, Codable {
    let artistA: CoCreditArtist
    let artistB: CoCreditArtist
    let matchMode: CoCreditMatchMode
}

struct PlaylistBuildRequest {
    let artistMBID: String
    let artistName: String
    let roleFilter: CreditRoleGroup?
    let isPublic: Bool
    let maxTracks: Int
    let mode: PlaylistMode
    let coCredit: CoCreditConfig?

    init(
        artistMBID: String,
        artistName: String,
        roleFilter: CreditRoleGroup? = nil,
        isPublic: Bool = false,
        maxTracks: Int = 100,
        mode: PlaylistMode = .singleArtist,
        coCredit: CoCreditConfig? = nil
    ) {
        self.artistMBID = artistMBID
        self.artistName = artistName
        self.roleFilter = roleFilter
        self.isPublic = isPublic
        self.maxTracks = maxTracks
        self.mode = mode
        self.coCredit = coCredit
    }

    init(coCredit: CoCreditConfig, roleFilter: CreditRoleGroup? = nil, isPublic: Bool = false, maxTracks: Int = 100) {
        self.artistMBID = coCredit.artistA.mbid
        self.artistName = coCredit.artistA.name
        self.roleFilter = roleFilter
        self.isPublic = isPublic
        self.maxTracks = maxTracks
        self.mode = .coCredit
        self.coCredit = coCredit
    }
}

struct PlaylistBuildResult: Equatable {
    let playlistName: String
    let playlistURI: String
    let trackCount: Int
    let skippedCount: Int
}

// MARK: - Playlist Errors

enum SpotifyClientError: Error, Equatable {
    case notAuthenticated
    case authenticationFailed(String)
    case authenticationCancelled
    case rateLimited
    case notFound
    case httpStatus(Int)
    case decoding(String)
    case network(String)
    case tokenRefreshFailed(String)
    case keychainError(String)
}

enum PlaylistBuilderError: Error, Equatable {
    case noRecordingsFound
    case noIntersectionFound
    case noTracksResolved
    case artistResolutionFailed(String)
}
