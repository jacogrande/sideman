import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject var spotifyAuthState: SpotifyAuthState

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
                settingsCard
                diagnosticsCard
                footer
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 24)
        }
        .frame(width: 420)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sideman")
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

                            if let trackNumber = track.trackNumber {
                                Text("Track \(trackNumber)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

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

    @ViewBuilder
    private var settingsCard: some View {
        if viewModel.isSettingsVisible {
            GlassPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("Settings")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Spotify Account")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        spotifyAccountRow
                    }

                    Divider()
                        .overlay(.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Debug")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Button {
                            viewModel.captureDiagnostics()
                            viewModel.isDiagnosticsVisible = true
                        } label: {
                            Label("Run Diagnostics", systemImage: "gauge.with.dots.needle.33percent")
                        }
                        .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.58, green: 0.39, blue: 0.87), isPrimary: false))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var spotifyAccountRow: some View {
        switch spotifyAuthState.status {
        case .notAuthenticated:
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.secondary)
                Text("Not connected")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    Task { await spotifyAuthState.startLogin() }
                } label: {
                    Label("Connect Spotify", systemImage: "link")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.27, green: 0.78, blue: 0.55), isPrimary: true))
            }

        case .authenticating:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting…")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

        case .authenticated:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.27, green: 0.78, blue: 0.55))
                Text("Connected")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Spacer(minLength: 0)
                Button {
                    Task { await spotifyAuthState.logout() }
                } label: {
                    Label("Disconnect", systemImage: "person.crop.circle.badge.minus")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.66, green: 0.70, blue: 0.74), isPrimary: false))
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(red: 0.94, green: 0.36, blue: 0.41))
                    Text(message)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Button {
                    Task { await spotifyAuthState.startLogin() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.25, green: 0.63, blue: 0.94), isPrimary: true))
            }
        }
    }

    @ViewBuilder
    private var diagnosticsCard: some View {
        if viewModel.isSettingsVisible, viewModel.isDiagnosticsVisible, let snapshot = viewModel.resourceSnapshot {
            DiagnosticsCardView(snapshot: snapshot)
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
                    DebugLogger.log(.ui, "manual refresh requested")
                    Task {
                        await viewModel.refreshOnce(forceCreditsRefresh: true)
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

                Button {
                    viewModel.isSettingsVisible.toggle()
                    if !viewModel.isSettingsVisible {
                        viewModel.isDiagnosticsVisible = false
                    }
                } label: {
                    Label(
                        viewModel.isSettingsVisible ? "Hide Settings" : "Settings",
                        systemImage: "gearshape"
                    )
                }
                .buttonStyle(GlassActionButtonStyle(tint: Color(red: 0.58, green: 0.39, blue: 0.87), isPrimary: false))

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
            if viewModel.playlistVM.phase != .idle {
                PlaylistFlowView(viewModel: viewModel.playlistVM)
                    .transition(.push(from: .trailing))
            } else {
                creditsCardContent
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.playlistVM.phase != .idle)
    }

    @ViewBuilder
    private var creditsCardContent: some View {
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
                    LoadingCreditsView(message: "Resolving source page…")

                case .loadingCredits:
                    LoadingCreditsView(message: "Loading credits from Wikipedia…")

                case .notFound:
                    Text("No credits found for this track.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                case .ambiguous:
                    Text("Match was ambiguous. Credits were not auto-selected.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                case .rateLimited:
                    Text("Wikipedia rate limit reached. Try again in a moment.")
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

    @ViewBuilder
    private var loadedCreditsContent: some View {
        if let bundle = viewModel.creditsBundle, !bundle.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(CreditRoleGroup.displayOrder, id: \.rawValue) { group in
                        let rows = aggregatedRows(from: bundle.entries(for: group))
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.title)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)

                                ForEach(rows, id: \.id) { row in
                                    CreditPersonRow(row: row, hasMatchedTrack: bundle.matchedTrackNumber != nil) { tappedRow in
                                        viewModel.playlistVM.beginFlow(
                                            personName: tappedRow.personName,
                                            personMBID: tappedRow.personMBID,
                                            roles: tappedRow.roles,
                                            roleGroup: group
                                        )
                                    }
                                }
                            }
                        }
                    }

                    sourceMetadata(bundle: bundle)
                }
                .padding(.vertical, 1)
            }
            .frame(minHeight: 190, idealHeight: 280, maxHeight: 340, alignment: .top)
        } else {
            Text("No credits available for this recording.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func aggregatedRows(from entries: [CreditEntry]) -> [AggregatedCreditRow] {
        var byPerson: [String: AggregatedCreditBuilder] = [:]
        var order: [String] = []

        for entry in entries {
            let key = aggregationKey(for: entry)
            if byPerson[key] == nil {
                byPerson[key] = AggregatedCreditBuilder(personName: entry.personName)
                order.append(key)
            }

            byPerson[key]?.append(entry)
        }

        return order.compactMap { key in
            guard let builder = byPerson[key] else {
                return nil
            }
            return builder.build(id: key)
        }
    }

    private func aggregationKey(for entry: CreditEntry) -> String {
        if let personMBID = entry.personMBID, !personMBID.isEmpty {
            return personMBID.lowercased()
        }

        return entry.personName.lowercased()
    }

    @ViewBuilder
    private func sourceMetadata(bundle: CreditsBundle) -> some View {
        let hasSourceMetadata =
            bundle.sourceName != nil ||
            bundle.sourcePageTitle != nil ||
            bundle.sourcePageURL != nil ||
            bundle.sourceAttribution != nil ||
            bundle.matchedTrackNumber != nil

        if hasSourceMetadata {
            Divider()
                .overlay(.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 4) {
                Text(sourceHeaderText(bundle: bundle))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if let sourceURLString = bundle.sourcePageURL,
                   let sourceURL = URL(string: sourceURLString) {
                    Link(bundle.sourcePageTitle ?? "Open source page", destination: sourceURL)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.36, green: 0.72, blue: 0.96))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let sourcePageTitle = bundle.sourcePageTitle {
                    Text(sourcePageTitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }

                if let attribution = bundle.sourceAttribution {
                    Text(attribution)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func sourceHeaderText(bundle: CreditsBundle) -> String {
        let sourceName = bundle.sourceName ?? "Source"
        if let trackNumber = bundle.matchedTrackNumber {
            return "\(sourceName) • matched track \(trackNumber)"
        }

        return sourceName
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
            DebugLogger.log(.ui, "openSpotify track url=\(id)")
            return
        }

        if let appURL = URL(string: "spotify:") {
            _ = NSWorkspace.shared.open(appURL)
            DebugLogger.log(.ui, "openSpotify app url=spotify:")
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

private struct AggregatedCreditRow: Hashable {
    let id: String
    let personName: String
    let personMBID: String?
    let roles: [String]
    let scopeLabels: [String]
}

private struct AggregatedCreditBuilder {
    let personName: String
    private(set) var personMBID: String?
    private(set) var roles: [String] = []
    private(set) var roleSet: Set<String> = []
    private(set) var scopeLabels: [String] = []
    private(set) var scopeSet: Set<String> = []

    mutating func append(_ entry: CreditEntry) {
        let role = roleLabel(for: entry)
        if !roleSet.contains(role) {
            roleSet.insert(role)
            roles.append(role)
        }

        let scopeLabel = entry.scope.label
        if !scopeSet.contains(scopeLabel) {
            scopeSet.insert(scopeLabel)
            scopeLabels.append(scopeLabel)
        }

        if personMBID == nil, let mbid = entry.personMBID, !mbid.isEmpty {
            personMBID = mbid
        }
    }

    func build(id: String) -> AggregatedCreditRow {
        AggregatedCreditRow(
            id: id,
            personName: personName,
            personMBID: personMBID,
            roles: roles,
            scopeLabels: scopeLabels
        )
    }

    private func roleLabel(for entry: CreditEntry) -> String {
        if let instrument = entry.instrument, !instrument.isEmpty {
            if instrument.localizedCaseInsensitiveCompare(entry.roleRaw) == .orderedSame {
                return entry.roleRaw
            }
            return "\(entry.roleRaw) (\(instrument))"
        }

        return entry.roleRaw
    }
}

private struct CreditPersonRow: View {
    let row: AggregatedCreditRow
    var hasMatchedTrack: Bool = false
    var onPersonTapped: ((AggregatedCreditRow) -> Void)?

    @State private var isHovered = false

    private var isTappable: Bool {
        onPersonTapped != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isTappable {
                    Text(row.personName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .underline(isHovered)
                        .foregroundStyle(isHovered ? Color(red: 0.36, green: 0.72, blue: 0.96) : .primary)
                        .onHover { hovering in
                            isHovered = hovering
                            #if canImport(AppKit)
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                            #endif
                        }
                        .onTapGesture {
                            onPersonTapped?(row)
                        }
                } else {
                    Text(row.personName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .help(row.personMBID == nil ? "MusicBrainz profile not found" : "")
                }

                Spacer(minLength: 0)

                Text(scopeSummary)
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

            VStack(alignment: .leading, spacing: 2) {
                ForEach(row.roles, id: \.self) { role in
                    Text("• \(role)")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var scopeSummary: String {
        if hasMatchedTrack {
            let hasAlbumWide = row.scopeLabels.contains("Album-wide")
            let hasTrackSpecific = row.scopeLabels.contains(where: { $0 != "Album-wide" })
            if hasAlbumWide && hasTrackSpecific {
                return "This track + album"
            } else if hasAlbumWide {
                return "Album-wide"
            } else {
                return "This track"
            }
        }

        if row.scopeLabels.count <= 1 {
            return row.scopeLabels.first ?? "Album-wide"
        }

        return row.scopeLabels.joined(separator: ", ")
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

struct GlassPanel<Content: View>: View {
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
    return MenuBarContentView(viewModel: vm, spotifyAuthState: SpotifyAuthState())
}

private actor PreviewProvider: NowPlayingProvider {
    func fetchSnapshot() async -> PlaybackSnapshot {
        .notRunning
    }
}
