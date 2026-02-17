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
}

struct CreditsBundle: Equatable, Codable {
    let entriesByGroup: [CreditRoleGroup: [CreditEntry]]
    let provenance: [CreditSourceLevel]
    let resolvedRecordingMBID: String

    var isEmpty: Bool {
        entriesByGroup.values.allSatisfy { $0.isEmpty }
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
