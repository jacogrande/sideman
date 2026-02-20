import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct PersonContext: Equatable {
    let personName: String
    var personMBID: String?
    let roles: [String]
    let roleGroup: CreditRoleGroup?
    let primaryArtistName: String?
    var primaryArtistMBID: String?
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
    @Published var selectedPlaylistMode: PlaylistMode = .singleArtist
    @Published var selectedRoleFilter: CreditRoleGroup?
    @Published var isPublic: Bool = false
    @Published var targetTrackCount: Double = 50
    @Published var coCreditArtistAName: String = ""
    @Published var coCreditArtistAMBID: String?
    @Published var coCreditArtistBName: String = ""
    @Published var coCreditArtistBMBID: String?

    private var buildTask: Task<Void, Never>?
    private var playlistBuilder: PlaylistBuilder?
    private var spotifyAuthState: SpotifyAuthState?
    private var musicBrainzClient: MusicBrainzClient?
    private var lastResult: PlaylistBuildResult?
    private let coCreditMatchMode: CoCreditMatchMode = .anyInvolvement

    func configure(builder: PlaylistBuilder, authState: SpotifyAuthState, musicBrainzClient: MusicBrainzClient) {
        self.playlistBuilder = builder
        self.spotifyAuthState = authState
        self.musicBrainzClient = musicBrainzClient
    }

    func beginFlow(
        personName: String,
        personMBID: String? = nil,
        roles: [String],
        roleGroup: CreditRoleGroup?,
        primaryArtistName: String? = nil,
        primaryArtistMBID: String? = nil
    ) {
        let normalizedPrimaryArtist = normalizeArtistName(primaryArtistName)
        let context = PersonContext(
            personName: personName,
            personMBID: personMBID,
            roles: roles,
            roleGroup: roleGroup,
            primaryArtistName: normalizedPrimaryArtist.isEmpty ? nil : normalizedPrimaryArtist,
            primaryArtistMBID: primaryArtistMBID
        )
        selectedPlaylistMode = .singleArtist
        selectedRoleFilter = roleGroup
        coCreditArtistAName = normalizedPrimaryArtist
        coCreditArtistAMBID = primaryArtistMBID
        coCreditArtistBName = personName
        coCreditArtistBMBID = personMBID
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

            guard let mbClient = self.musicBrainzClient else {
                self.phase = .failed("MusicBrainz client not configured")
                self.buildTask = nil
                return
            }

            let target = Int(self.targetTrackCount)
            let request: PlaylistBuildRequest

            do {
                switch self.selectedPlaylistMode {
                case .singleArtist:
                    // Resolve MBID if not already known
                    if context.personMBID == nil {
                        self.phase = .resolvingArtist
                        let resolved = try await self.resolveArtist(
                            name: context.personName,
                            existingMBID: nil,
                            client: mbClient
                        )
                        context.personMBID = resolved.mbid
                        self.coCreditArtistBMBID = resolved.mbid
                        DebugLogger.log(.ui, "artist search resolved '\(context.personName)' → \(resolved.mbid)")
                    }

                    guard let artistMBID = context.personMBID else {
                        throw PlaylistBuilderError.artistResolutionFailed("No MusicBrainz ID found.")
                    }

                    request = PlaylistBuildRequest(
                        artistMBID: artistMBID,
                        artistName: context.personName,
                        roleFilter: self.selectedRoleFilter,
                        isPublic: self.isPublic,
                        maxTracks: target
                    )

                case .coCredit:
                    let artistAName = normalizeArtistName(self.coCreditArtistAName)
                    let artistBName = normalizeArtistName(self.coCreditArtistBName)

                    guard !artistAName.isEmpty, !artistBName.isEmpty else {
                        throw PlaylistBuilderError.artistResolutionFailed("Enter two artist names for co-credit mode.")
                    }

                    self.phase = .resolvingArtist

                    let resolvedArtistA = try await self.resolveArtist(
                        name: artistAName,
                        existingMBID: self.coCreditArtistAMBID,
                        client: mbClient
                    )
                    let resolvedArtistB = try await self.resolveArtist(
                        name: artistBName,
                        existingMBID: self.coCreditArtistBMBID,
                        client: mbClient
                    )

                    if resolvedArtistA.mbid == resolvedArtistB.mbid ||
                        resolvedArtistA.name.localizedCaseInsensitiveCompare(resolvedArtistB.name) == .orderedSame {
                        throw PlaylistBuilderError.artistResolutionFailed("Pick two different artists for co-credit mode.")
                    }

                    self.coCreditArtistAName = resolvedArtistA.name
                    self.coCreditArtistAMBID = resolvedArtistA.mbid
                    self.coCreditArtistBName = resolvedArtistB.name
                    self.coCreditArtistBMBID = resolvedArtistB.mbid

                    let coCredit = CoCreditConfig(
                        artistA: CoCreditArtist(name: resolvedArtistA.name, mbid: resolvedArtistA.mbid),
                        artistB: CoCreditArtist(name: resolvedArtistB.name, mbid: resolvedArtistB.mbid),
                        matchMode: self.coCreditMatchMode
                    )

                    request = PlaylistBuildRequest(
                        coCredit: coCredit,
                        isPublic: self.isPublic,
                        maxTracks: target
                    )
                }
            } catch let error as PlaylistBuilderError {
                self.phase = .failed(self.playlistErrorMessage(error))
                self.buildTask = nil
                return
            } catch {
                self.phase = .failed(error.localizedDescription)
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
        case .noIntersectionFound:
            return "No shared recordings found where both artists are credited."
        case .noTracksResolved:
            return "Could not find any matching tracks on Spotify."
        case .artistResolutionFailed(let message):
            return message
        }
    }

    private func resolveArtist(name: String, existingMBID: String?, client: MusicBrainzClient) async throws -> CoCreditArtist {
        let trimmedName = normalizeArtistName(name)
        guard !trimmedName.isEmpty else {
            throw PlaylistBuilderError.artistResolutionFailed("Artist name cannot be empty.")
        }

        if let existingMBID, !existingMBID.isEmpty {
            return CoCreditArtist(name: trimmedName, mbid: existingMBID)
        }

        do {
            let results = try await client.searchArtists(name: trimmedName)
            guard let best = results.first, best.score >= Self.artistSearchMinScore else {
                throw PlaylistBuilderError.artistResolutionFailed("Could not find \"\(trimmedName)\" on MusicBrainz.")
            }
            return CoCreditArtist(name: best.name, mbid: best.id)
        } catch let error as PlaylistBuilderError {
            throw error
        } catch {
            throw PlaylistBuilderError.artistResolutionFailed("MusicBrainz search failed for \"\(trimmedName)\": \(error.localizedDescription)")
        }
    }

    private func normalizeArtistName(_ name: String?) -> String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
