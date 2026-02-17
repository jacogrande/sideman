import Foundation

protocol MusicBrainzClient {
    func searchRecordings(query: RecordingQuery) async throws -> [RecordingCandidate]
    func getRecording(id: String) async throws -> MBRecordingDetail
    func getWork(id: String) async throws -> MBWorkDetail
    func getRelease(id: String) async throws -> MBReleaseDetail
}

protocol WikipediaAPIClient {
    func searchPages(query: String, limit: Int) async throws -> [WikipediaSearchResult]
    func fetchPage(pageID: Int) async throws -> WikipediaPageContent
}

protocol TrackResolver {
    func resolve(_ track: NowPlayingTrack) async -> Result<ResolutionResult, ResolverError>
}

protocol WikipediaPageResolver {
    func resolvePage(for track: NowPlayingTrack) async -> Result<WikipediaPageResolution, ResolverError>
}

protocol WikipediaWikitextParser {
    func parse(page: WikipediaPageContent, for track: NowPlayingTrack) -> WikipediaParsedCredits
}

protocol CreditsProvider {
    func lookupCredits(for track: NowPlayingTrack) async -> (CreditsLookupState, CreditsBundle?)
    func cacheLookupKey(for track: NowPlayingTrack) async -> String
    func invalidateCachedCredits(for track: NowPlayingTrack) async
}

extension CreditsProvider {
    func invalidateCachedCredits(for track: NowPlayingTrack) async {
        // Optional override for providers with cache invalidation support.
    }
}

protocol CreditsCache {
    func get(for key: String) async -> CachedCredits?
    func set(_ value: CachedCredits, for key: String) async
    func remove(for key: String) async
}
