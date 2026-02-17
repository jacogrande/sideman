import SwiftUI

@main
struct SpoftyApp: App {
    @StateObject private var viewModel: MenuBarViewModel

    init() {
        let nowPlayingProvider = SpotifyAppleScriptNowPlayingProvider()
        let musicBrainzClient = MusicBrainzHTTPClient()
        let trackResolver = DefaultTrackResolver(client: musicBrainzClient)
        let creditsCache = MemoryDiskCreditsCache()
        let creditsProvider = DefaultCreditsProvider(
            resolver: trackResolver,
            client: musicBrainzClient,
            cache: creditsCache
        )

        _viewModel = StateObject(
            wrappedValue: MenuBarViewModel(
                provider: nowPlayingProvider,
                creditsProvider: creditsProvider
            )
        )
    }

    var body: some Scene {
        MenuBarExtra("Spofty", systemImage: "music.note") {
            MenuBarContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
