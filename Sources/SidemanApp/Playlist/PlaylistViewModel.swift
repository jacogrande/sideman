import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct PersonContext: Equatable {
    let personName: String
    var personMBID: String?
    let roles: [String]
    let roleGroup: CreditRoleGroup?
}

enum PlaylistFlowPhase: Equatable {
    case idle
    case confirming(PersonContext)
    case resolvingArtist
    case authenticating
    case building(PlaylistBuildStage)
    case completed(PlaylistBuildResult)
    case failed(String)
}

@MainActor
final class PlaylistViewModel: ObservableObject {
    private static let artistSearchMinScore = 80
    @Published fileprivate(set) var phase: PlaylistFlowPhase = .idle
    @Published var selectedRoleFilter: CreditRoleGroup?
    @Published var isPublic: Bool = false

    private var buildTask: Task<Void, Never>?
    private var playlistBuilder: PlaylistBuilder?
    private var spotifyAuthState: SpotifyAuthState?
    private var musicBrainzClient: MusicBrainzClient?
    private var lastResult: PlaylistBuildResult?

    func configure(builder: PlaylistBuilder, authState: SpotifyAuthState, musicBrainzClient: MusicBrainzClient) {
        self.playlistBuilder = builder
        self.spotifyAuthState = authState
        self.musicBrainzClient = musicBrainzClient
    }

    func beginFlow(personName: String, personMBID: String? = nil, roles: [String], roleGroup: CreditRoleGroup?) {
        let context = PersonContext(
            personName: personName,
            personMBID: personMBID,
            roles: roles,
            roleGroup: roleGroup
        )
        selectedRoleFilter = roleGroup
        phase = .confirming(context)
        DebugLogger.log(.ui, "playlist flow started for \(personName)")
    }

    func confirmAndCreate() {
        guard case .confirming(var context) = phase, buildTask == nil else { return }

        guard let authState = spotifyAuthState, let builder = playlistBuilder else {
            phase = .failed("Playlist builder not configured")
            return
        }

        buildTask = Task { [weak self] in
            guard let self else { return }

            // Resolve MBID if not already known
            if context.personMBID == nil {
                self.phase = .resolvingArtist
                guard let mbClient = self.musicBrainzClient else {
                    self.phase = .failed("MusicBrainz client not configured")
                    return
                }

                do {
                    let results = try await mbClient.searchArtists(name: context.personName)
                    guard let best = results.first, best.score >= Self.artistSearchMinScore else {
                        self.phase = .failed("Could not find \"\(context.personName)\" on MusicBrainz.")
                        DebugLogger.log(.ui, "artist search no match for '\(context.personName)'")
                        self.buildTask = nil
                        return
                    }
                    context.personMBID = best.id
                    DebugLogger.log(.ui, "artist search resolved '\(context.personName)' → \(best.id) (score=\(best.score))")
                } catch {
                    self.phase = .failed("MusicBrainz search failed: \(error.localizedDescription)")
                    self.buildTask = nil
                    return
                }
            }

            guard let artistMBID = context.personMBID else {
                self.phase = .failed("No MusicBrainz ID found.")
                self.buildTask = nil
                return
            }

            // Check auth
            let isAuthed = await authState.client.isAuthenticated
            if !isAuthed {
                self.phase = .authenticating
                await authState.startLogin()

                let stillAuthed = await authState.client.isAuthenticated
                guard stillAuthed else {
                    if authState.status == .notAuthenticated {
                        self.phase = .idle
                    } else {
                        self.phase = .failed("Spotify authentication failed")
                    }
                    return
                }
            }

            let request = PlaylistBuildRequest(
                artistMBID: artistMBID,
                artistName: context.personName,
                roleFilter: self.selectedRoleFilter,
                isPublic: self.isPublic
            )

            do {
                let phaseUpdater = MainActorPhaseUpdater(viewModel: self)
                let result = try await builder.buildPlaylist(request: request) { stage in
                    await phaseUpdater.update(stage)
                }

                guard !Task.isCancelled else { return }
                self.lastResult = result
                self.phase = .completed(result)
                DebugLogger.log(.ui, "playlist flow completed: \(result.playlistName)")
            } catch is CancellationError {
                self.phase = .idle
            } catch let error as PlaylistBuilderError {
                self.phase = .failed(playlistErrorMessage(error))
                DebugLogger.log(.ui, "playlist flow failed: \(error)")
            } catch {
                self.phase = .failed(error.localizedDescription)
                DebugLogger.log(.ui, "playlist flow failed: \(error)")
            }
        }
    }

    func cancel() {
        buildTask?.cancel()
        buildTask = nil
        phase = .idle
        DebugLogger.log(.ui, "playlist flow cancelled")
    }

    func dismiss() {
        buildTask?.cancel()
        buildTask = nil
        phase = .idle
    }

    func openPlaylist() {
        #if canImport(AppKit)
        if let result = lastResult, let url = URL(string: result.playlistURI) {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private func playlistErrorMessage(_ error: PlaylistBuilderError) -> String {
        switch error {
        case .noRecordingsFound:
            return "No recordings found for this person in MusicBrainz."
        case .noTracksResolved:
            return "Could not find any matching tracks on Spotify."
        }
    }
}

@MainActor
private final class MainActorPhaseUpdater: Sendable {
    private let viewModel: PlaylistViewModel

    init(viewModel: PlaylistViewModel) {
        self.viewModel = viewModel
    }

    func update(_ stage: PlaylistBuildStage) {
        viewModel.phase = .building(stage)
    }
}
