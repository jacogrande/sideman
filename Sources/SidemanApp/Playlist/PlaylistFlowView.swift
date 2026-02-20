import SwiftUI

struct PlaylistFlowView: View {
    @ObservedObject var viewModel: PlaylistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch viewModel.phase {
            case .idle:
                EmptyView()
            case .confirming(let context):
                PlaylistConfirmationView(context: context, viewModel: viewModel)
            case .resolvingArtist:
                ArtistSearchView(viewModel: viewModel)
            case .authenticating:
                SpotifyAuthPromptView(viewModel: viewModel)
            case .building(let stage):
                PlaylistProgressView(stage: stage, viewModel: viewModel)
            case .completed(let result):
                PlaylistCompletionView(result: result, viewModel: viewModel)
            case .failed(let message):
                PlaylistErrorView(message: message, viewModel: viewModel)
            }
        }
    }
}

// MARK: - Confirmation

private struct PlaylistConfirmationView: View {
    let context: PersonContext
    @ObservedObject var viewModel: PlaylistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "music.note.list")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.27, green: 0.78, blue: 0.55))
                Text("Create Playlist")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Playlist mode")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    PlaylistModeCapsule(
                        label: PlaylistMode.singleArtist.title,
                        isSelected: viewModel.selectedPlaylistMode == .singleArtist
                    ) {
                        viewModel.selectedPlaylistMode = .singleArtist
                    }

                    PlaylistModeCapsule(
                        label: PlaylistMode.coCredit.title,
                        isSelected: viewModel.selectedPlaylistMode == .coCredit
                    ) {
                        viewModel.selectedPlaylistMode = .coCredit
                    }
                }
            }

            if viewModel.selectedPlaylistMode == .singleArtist {
                Text("Create a playlist featuring **\(context.personName)**?")
                    .font(.system(size: 12, weight: .regular, design: .rounded))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Role filter")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        RoleFilterCapsule(
                            label: "All roles",
                            isSelected: viewModel.selectedRoleFilter == nil
                        ) {
                            viewModel.selectedRoleFilter = nil
                        }

                        if let group = context.roleGroup {
                            RoleFilterCapsule(
                                label: group.filterLabel,
                                isSelected: viewModel.selectedRoleFilter == group
                            ) {
                                viewModel.selectedRoleFilter = group
                            }
                        }
                    }
                }
            } else {
                Text("Create a playlist where **both artists** are credited on the same tracks.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                coCreditArtistInputs
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tracks: \(Int(viewModel.targetTrackCount))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    Slider(
                        value: $viewModel.targetTrackCount,
                        in: 25...100,
                        step: 25
                    )
                    .controlSize(.mini)
                }

                HStack {
                    Text("25")
                    Spacer()
                    Text("50")
                    Spacer()
                    Text("75")
                    Spacer()
                    Text("100")
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
            }

            HStack {
                Toggle(isOn: $viewModel.isPublic) {
                    Text("Public playlist")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.confirmAndCreate()
                } label: {
                    Label("Create", systemImage: "plus.circle.fill")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.27, green: 0.78, blue: 0.55), isPrimary: true))

                Button {
                    viewModel.dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.66, green: 0.70, blue: 0.74), isPrimary: false))
            }
        }
    }

    @ViewBuilder
    private var coCreditArtistInputs: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Artist A")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField(
                    context.primaryArtistName ?? "Primary artist",
                    text: Binding(
                        get: { viewModel.coCreditArtistAName },
                        set: { newValue in
                            viewModel.coCreditArtistAName = newValue
                            viewModel.coCreditArtistAMBID = nil
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .regular, design: .rounded))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Artist B")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField(
                    context.personName,
                    text: Binding(
                        get: { viewModel.coCreditArtistBName },
                        set: { newValue in
                            viewModel.coCreditArtistBName = newValue
                            viewModel.coCreditArtistBMBID = nil
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .regular, design: .rounded))
            }
        }
    }
}

private struct RoleFilterCapsule: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color(red: 0.27, green: 0.78, blue: 0.55).opacity(0.25) : Color.clear)
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color(red: 0.27, green: 0.78, blue: 0.55) : .white.opacity(0.22),
                            lineWidth: 0.8
                        )
                )
                .foregroundStyle(isSelected ? Color(red: 0.27, green: 0.78, blue: 0.55) : .secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct PlaylistModeCapsule: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color(red: 0.25, green: 0.63, blue: 0.94).opacity(0.24) : Color.clear)
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color(red: 0.25, green: 0.63, blue: 0.94) : .white.opacity(0.22),
                            lineWidth: 0.8
                        )
                )
                .foregroundStyle(isSelected ? Color(red: 0.25, green: 0.63, blue: 0.94) : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Artist Search

private struct ArtistSearchView: View {
    @ObservedObject var viewModel: PlaylistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.27, green: 0.78, blue: 0.55))
                Text("Finding Artist")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Resolving artists on MusicBrainz…")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.cancel()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(GlassActionButtonStyle(tint: .gray, isPrimary: false))
        }
    }
}

// MARK: - Auth Prompt

private struct SpotifyAuthPromptView: View {
    @ObservedObject var viewModel: PlaylistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.30, green: 0.72, blue: 0.55))
                Text("Connect to Spotify")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for Spotify authorization…")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.cancel()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.66, green: 0.70, blue: 0.74), isPrimary: false))
        }
    }
}

// MARK: - Progress

private struct PlaylistProgressView: View {
    let stage: PlaylistBuildStage
    @ObservedObject var viewModel: PlaylistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.25, green: 0.63, blue: 0.94))
                Text("Building Playlist")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                StageIndicatorRow(label: "Fetching discography", state: stageState(for: .fetchingDiscography))
                StageIndicatorRow(label: "Ranking by popularity", state: stageState(for: .rankingByPopularity(total: 0)))
                StageIndicatorRow(label: resolvingLabel, state: stageState(for: .resolvingTracks(resolved: 0, total: 0)))
                StageIndicatorRow(label: "Creating playlist", state: stageState(for: .creatingPlaylist(trackCount: 0)))
            }

            if case .resolvingTracks(let resolved, let total) = stage, total > 0 {
                ProgressView(value: Double(resolved), total: Double(total))
                    .tint(Color(red: 0.25, green: 0.63, blue: 0.94))
                Text("\(resolved) of \(total)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.cancel()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.83, green: 0.36, blue: 0.37), isPrimary: false))
        }
    }

    private var resolvingLabel: String {
        if case .resolvingTracks(let resolved, let total) = stage {
            return "Resolving tracks (\(resolved)/\(total))"
        }
        return "Resolving tracks"
    }

    fileprivate func stageState(for targetStage: PlaylistBuildStage) -> BuildStageState {
        let currentOrdinal = stageOrdinal(stage)
        let targetOrdinal = stageOrdinal(targetStage)

        if currentOrdinal > targetOrdinal { return .completed }
        if currentOrdinal == targetOrdinal { return .active }
        return .pending
    }

    private func stageOrdinal(_ s: PlaylistBuildStage) -> Int {
        switch s {
        case .fetchingDiscography: return 0
        case .rankingByPopularity: return 1
        case .resolvingTracks: return 2
        case .creatingPlaylist: return 3
        case .complete: return 4
        case .failed: return -1
        }
    }
}

private enum BuildStageState {
    case completed, active, pending
}

private struct StageIndicatorRow: View {
    let label: String
    let state: BuildStageState

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch state {
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.27, green: 0.78, blue: 0.55))
                case .active:
                    ProgressView()
                        .controlSize(.mini)
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 14, height: 14)

            Text(label)
                .font(.system(size: 11, weight: state == .active ? .semibold : .regular, design: .rounded))
                .foregroundStyle(state == .pending ? .tertiary : .primary)
        }
    }
}

// MARK: - Completion

private struct PlaylistCompletionView: View {
    let result: PlaylistBuildResult
    @ObservedObject var viewModel: PlaylistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.27, green: 0.78, blue: 0.55))
                Text("Playlist Created")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }

            Text(result.playlistName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))

            HStack(spacing: 12) {
                Label("\(result.trackCount) tracks", systemImage: "music.note")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                if result.skippedCount > 0 {
                    Label("\(result.skippedCount) skipped", systemImage: "forward.end")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.openPlaylist()
                } label: {
                    Label("Open in Spotify", systemImage: "play.fill")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.30, green: 0.72, blue: 0.55), isPrimary: true))

                Button {
                    viewModel.dismiss()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.66, green: 0.70, blue: 0.74), isPrimary: false))
            }
        }
    }
}

// MARK: - Error

private struct PlaylistErrorView: View {
    let message: String
    @ObservedObject var viewModel: PlaylistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.94, green: 0.36, blue: 0.41))
                Text("Playlist Failed")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }

            Text(message)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Button {
                    viewModel.dismiss()
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.66, green: 0.70, blue: 0.74), isPrimary: false))
            }
        }
    }
}
