import Foundation

protocol MusicBrainzClient {
    func searchRecordings(query: RecordingQuery) async throws -> [RecordingCandidate]
    func getRecording(id: String) async throws -> MBRecordingDetail
    func getWork(id: String) async throws -> MBWorkDetail
    func getRelease(id: String) async throws -> MBReleaseDetail
    func getArtistRecordingRels(id: String) async throws -> [ArtistRecordingRel]
    func getArtistWorkRels(id: String) async throws -> [ArtistWorkRel]
    func getWorkRecordings(id: String) async throws -> [WorkRecordingRel]
    func browseRecordings(artistID: String, offset: Int, limit: Int, includeISRCs: Bool) async throws -> MBBrowseRecordingsPage
    func getRecordingISRCs(id: String) async throws -> [String]
    func searchArtists(name: String) async throws -> [MBArtistSearchResult]
}

protocol DiscogsClient {
    func artistHintsForTrack(title: String, artistHints: [String], limit: Int) async throws -> [String]
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

protocol SpotifyWebAPI {
    var isAuthenticated: Bool { get async }
    func searchTrackByISRC(_ isrc: String) async throws -> [SpotifyTrack]
    func searchTracks(title: String, artist: String) async throws -> [SpotifyTrack]
    func createPlaylist(name: String, description: String, isPublic: Bool) async throws -> SpotifyPlaylist
    func addTracksToPlaylist(playlistID: String, trackURIs: [String]) async throws
}
