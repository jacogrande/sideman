import SwiftUI

@main
struct SidemanApp: App {
    @StateObject private var viewModel: MenuBarViewModel
    @StateObject private var spotifyAuthState: SpotifyAuthState

    init() {
        let nowPlayingProvider = SpotifyAppleScriptNowPlayingProvider()
        let creditsCache = MemoryDiskCreditsCache()
        let backend = CreditsBackend.fromEnvironment()
        let creditsProvider = CreditsProviderFactory.makeProvider(backend: backend, cache: creditsCache)

        DebugLogger.log(.app, "credits backend=\(backend.rawValue)")

        let spotifyAuth = SpotifyAuthState()
        let playlistBuilder = CreditsProviderFactory.makePlaylistBuilder(spotifyClient: spotifyAuth.client)

        let vm = MenuBarViewModel(
            provider: nowPlayingProvider,
            creditsProvider: creditsProvider
        )
        vm.playlistVM.configure(builder: playlistBuilder, authState: spotifyAuth)

        _viewModel = StateObject(wrappedValue: vm)
        _spotifyAuthState = StateObject(wrappedValue: spotifyAuth)
    }

    var body: some Scene {
        MenuBarExtra("Sideman", systemImage: "music.note") {
            MenuBarContentView(viewModel: viewModel)
                .task {
                    await spotifyAuthState.restoreSession()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
