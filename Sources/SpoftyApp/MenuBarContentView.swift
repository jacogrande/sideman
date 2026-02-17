import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    private var status: StatusPresentation {
        switch viewModel.snapshot.state {
        case .playing:
            return StatusPresentation(label: "Playing", icon: "waveform", tint: Color(red: 0.27, green: 0.78, blue: 0.55), isPulsing: true)
        case .paused:
            return StatusPresentation(label: "Paused", icon: "pause.fill", tint: Color(red: 0.98, green: 0.67, blue: 0.28), isPulsing: false)
        case .notRunning:
            return StatusPresentation(label: "Spotify Closed", icon: "xmark", tint: Color(red: 0.66, green: 0.70, blue: 0.74), isPulsing: false)
        case .unknown:
            return StatusPresentation(label: "Unavailable", icon: "exclamationmark", tint: Color(red: 0.94, green: 0.36, blue: 0.41), isPulsing: false)
        }
    }

    var body: some View {
        ZStack {
            AmbientGlassBackground()

            VStack(alignment: .leading, spacing: 14) {
                header
                contentCard
                creditsCard
                footer
            }
            .padding(14)
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Spofty")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Spotify now playing")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            StatusBadge(status: status)
        }
    }

    private var contentCard: some View {
        GlassPanel {
            switch viewModel.snapshot.state {
            case .playing:
                if let track = viewModel.snapshot.track {
                    HStack(alignment: .top, spacing: 12) {
                        TrackOrb()

                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .lineLimit(2)

                            Text(track.artist)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary.opacity(0.9))

                            Text(track.album)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            if !track.id.isEmpty {
                                Text(track.id)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.top, 2)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                } else {
                    PlaceholderStateView(
                        icon: "exclamationmark.triangle.fill",
                        title: "Track data was unavailable",
                        subtitle: "Spotify is playing, but metadata was not returned."
                    )
                }
            case .paused, .notRunning:
                PlaceholderStateView(
                    icon: "music.note",
                    title: "Nothing playing on Spotify",
                    subtitle: "Start playback in Spotify and this view updates automatically."
                )
            case .unknown:
                PlaceholderStateView(
                    icon: "exclamationmark.triangle.fill",
                    title: "Unable to read Spotify state",
                    subtitle: viewModel.snapshot.errorMessage ?? "Grant Automation permission and try again."
                )
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lastUpdated = viewModel.lastUpdated {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("Updated \(lastUpdated.formatted(date: .omitted, time: .standard))")
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        await viewModel.refreshOnce()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.25, green: 0.63, blue: 0.94), isPrimary: true))

                Button {
                    openSpotify()
                } label: {
                    Label("Open Spotify", systemImage: "play.fill")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.30, green: 0.72, blue: 0.55), isPrimary: false))

                Spacer(minLength: 0)

                #if canImport(AppKit)
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "xmark")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.83, green: 0.36, blue: 0.37), isPrimary: false))
                #endif
            }
        }
    }

    private var creditsCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Credits")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer(minLength: 0)
                    Text(creditsStateLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                switch viewModel.creditsState {
                case .idle:
                    Text("Credits load automatically when a track is playing.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                case .resolving:
                    LoadingCreditsView(message: "Resolving recording match…")

                case .loadingCredits:
                    LoadingCreditsView(message: "Loading credits from MusicBrainz…")

                case .notFound:
                    Text("No credits found for this track.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                case .ambiguous:
                    Text("Match was ambiguous. Credits were not auto-selected.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                case .rateLimited:
                    Text("MusicBrainz rate limit reached. Try again in a moment.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                case .error(let message):
                    Text(message)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                case .loaded:
                    loadedCreditsContent
                }
            }
        }
    }

    @ViewBuilder
    private var loadedCreditsContent: some View {
        if let bundle = viewModel.creditsBundle, !bundle.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(CreditRoleGroup.displayOrder, id: \.rawValue) { group in
                    let entries = bundle.entries(for: group)
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)

                            ForEach(entries, id: \.self) { entry in
                                CreditEntryRow(entry: entry)
                            }
                        }
                    }
                }
            }
        } else {
            Text("No credits available for this recording.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var creditsStateLabel: String {
        switch viewModel.creditsState {
        case .idle:
            return "Idle"
        case .resolving:
            return "Resolving"
        case .loadingCredits:
            return "Loading"
        case .loaded:
            return "Loaded"
        case .notFound:
            return "No Match"
        case .ambiguous:
            return "Ambiguous"
        case .rateLimited:
            return "Rate Limited"
        case .error:
            return "Error"
        }
    }

    private func openSpotify() {
        #if canImport(AppKit)
        if let id = viewModel.snapshot.track?.id, let trackURL = URL(string: id) {
            _ = NSWorkspace.shared.open(trackURL)
            return
        }

        if let appURL = URL(string: "spotify:") {
            _ = NSWorkspace.shared.open(appURL)
        }
        #endif
    }
}

private struct LoadingCreditsView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

private struct CreditEntryRow: View {
    let entry: CreditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.personName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(entry.sourceLevel.badgeTitle)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                    )
            }

            Text(subtitle)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var subtitle: String {
        if let instrument = entry.instrument, !instrument.isEmpty {
            return "\(entry.roleRaw) • \(instrument)"
        }

        return entry.roleRaw
    }
}

private struct StatusPresentation {
    let label: String
    let icon: String
    let tint: Color
    let isPulsing: Bool
}

private struct StatusBadge: View {
    let status: StatusPresentation
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(status.tint)
                .frame(width: 8, height: 8)
                .scaleEffect(status.isPulsing ? (pulse ? 1 : 0.65) : 1)
                .animation(
                    status.isPulsing ? .easeInOut(duration: 0.95).repeatForever(autoreverses: true) : .default,
                    value: pulse
                )

            Image(systemName: status.icon)
                .font(.system(size: 9, weight: .bold, design: .rounded))

            Text(status.label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.26), lineWidth: 0.85)
        )
        .onAppear {
            pulse = true
        }
    }
}

private struct TrackOrb: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.84, blue: 0.71),
                            Color(red: 0.19, green: 0.56, blue: 0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.black.opacity(0.16))
                .frame(width: 20, height: 20)

            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(width: 56, height: 56)
        .overlay(
            Circle()
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.9)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 12, x: 0, y: 8)
    }
}

private struct PlaceholderStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.24), lineWidth: 0.8)
                    )
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct GlassPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.42),
                                .white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            )
            .shadow(color: Color.black.opacity(0.16), radius: 22, x: 0, y: 10)
    }
}

private struct GlassActionButtonStyle: ButtonStyle {
    let tint: Color
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background(configuration: configuration), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
            )
            .foregroundStyle(.white.opacity(isPrimary ? 0.98 : 0.9))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private func background(configuration: Configuration) -> some ShapeStyle {
        if isPrimary {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        tint.opacity(configuration.isPressed ? 0.72 : 0.94),
                        tint.opacity(configuration.isPressed ? 0.58 : 0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    tint.opacity(configuration.isPressed ? 0.34 : 0.44),
                    tint.opacity(configuration.isPressed ? 0.18 : 0.27)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct AmbientGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            baseGradient

            Circle()
                .fill(Color(red: 0.12, green: 0.76, blue: 0.69).opacity(colorScheme == .dark ? 0.42 : 0.34))
                .frame(width: 250, height: 250)
                .blur(radius: 46)
                .offset(x: -130, y: -112)

            Circle()
                .fill(Color(red: 0.99, green: 0.61, blue: 0.31).opacity(colorScheme == .dark ? 0.28 : 0.22))
                .frame(width: 200, height: 200)
                .blur(radius: 44)
                .offset(x: 125, y: 110)

            Circle()
                .fill(Color(red: 0.32, green: 0.66, blue: 0.98).opacity(colorScheme == .dark ? 0.25 : 0.20))
                .frame(width: 200, height: 200)
                .blur(radius: 42)
                .offset(x: 135, y: -95)
        }
        .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
    }

    private var baseGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.05, green: 0.10, blue: 0.16),
                    Color(red: 0.03, green: 0.07, blue: 0.10)
                ]
                : [
                    Color(red: 0.94, green: 0.96, blue: 0.98),
                    Color(red: 0.87, green: 0.91, blue: 0.95)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    let vm = MenuBarViewModel(provider: PreviewProvider(), autoStart: false)
    vm.apply(
        snapshot: .playing(
            NowPlayingTrack(
                id: "spotify:track:1234567890",
                title: "A Future Classic with a Very Long Name",
                artist: "The Midnight Ensemble",
                album: "Studio Sessions Vol. 1"
            )
        ),
        at: Date()
    )
    return MenuBarContentView(viewModel: vm)
}

private actor PreviewProvider: NowPlayingProvider {
    func fetchSnapshot() async -> PlaybackSnapshot {
        .notRunning
    }
}
