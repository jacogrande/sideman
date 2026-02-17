import Foundation

protocol MusicBrainzClient {
    func searchRecordings(query: RecordingQuery) async throws -> [RecordingCandidate]
    func getRecording(id: String) async throws -> MBRecordingDetail
    func getWork(id: String) async throws -> MBWorkDetail
    func getRelease(id: String) async throws -> MBReleaseDetail
}

protocol TrackResolver {
    func resolve(_ track: NowPlayingTrack) async -> Result<ResolutionResult, ResolverError>
}

protocol CreditsProvider {
    func lookupCredits(for track: NowPlayingTrack) async -> (CreditsLookupState, CreditsBundle?)
}

protocol CreditsCache {
    func get(for key: String) async -> CachedCredits?
    func set(_ value: CachedCredits, for key: String) async
}
