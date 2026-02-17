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
