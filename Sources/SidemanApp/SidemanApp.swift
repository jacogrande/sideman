import SwiftUI

@main
struct SidemanApp: App {
    @StateObject private var viewModel: MenuBarViewModel

    init() {
        let nowPlayingProvider = SpotifyAppleScriptNowPlayingProvider()
        let creditsCache = MemoryDiskCreditsCache()
        let backend = CreditsBackend.fromEnvironment()
        let creditsProvider = CreditsProviderFactory.makeProvider(backend: backend, cache: creditsCache)

        DebugLogger.log(.app, "credits backend=\(backend.rawValue)")

        _viewModel = StateObject(
            wrappedValue: MenuBarViewModel(
                provider: nowPlayingProvider,
                creditsProvider: creditsProvider
            )
        )
    }

    var body: some Scene {
        MenuBarExtra("Sideman", systemImage: "music.note") {
            MenuBarContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
