import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Spofty")
                .font(.headline)

            Group {
                switch viewModel.snapshot.state {
                case .playing:
                    if let track = viewModel.snapshot.track {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.body.weight(.semibold))
                                .lineLimit(2)
                            Text(track.artist)
                                .font(.subheadline)
                            Text(track.album)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } else {
                        Text("Unable to read Spotify state")
                            .font(.subheadline)
                    }
                case .paused, .notRunning:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nothing playing on Spotify")
                            .font(.subheadline.weight(.semibold))
                        Text("Start playback in Spotify.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .unknown:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unable to read Spotify state")
                            .font(.subheadline.weight(.semibold))
                        if let error = viewModel.snapshot.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
            }

            if let lastUpdated = viewModel.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            HStack {
                Button("Refresh") {
                    Task {
                        await viewModel.refreshOnce()
                    }
                }

                Spacer()

                #if canImport(AppKit)
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                #endif
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}

#Preview {
    let vm = MenuBarViewModel(provider: PreviewProvider(), autoStart: false)
    vm.apply(
        snapshot: .playing(NowPlayingTrack(id: "spotify:track:123", title: "Track Name", artist: "Artist", album: "Album")),
        at: Date()
    )
    return MenuBarContentView(viewModel: vm)
}

private actor PreviewProvider: NowPlayingProvider {
    func fetchSnapshot() async -> PlaybackSnapshot {
        .notRunning
    }
}
