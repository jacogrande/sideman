import SwiftUI

@main
struct SpoftyApp: App {
    @StateObject private var viewModel: MenuBarViewModel
    @StateObject private var debugLogStore: DebugLogStore

    init() {
        let nowPlayingProvider = SpotifyAppleScriptNowPlayingProvider()
        let creditsCache = MemoryDiskCreditsCache()
        let backend = CreditsBackend.fromEnvironment()
        let creditsProvider = CreditsProviderFactory.makeProvider(backend: backend, cache: creditsCache)
        let debugStore = DebugLogStore()

        DebugLogger.log(.app, "credits backend=\(backend.rawValue)")

        _viewModel = StateObject(
            wrappedValue: MenuBarViewModel(
                provider: nowPlayingProvider,
                creditsProvider: creditsProvider
            )
        )
        _debugLogStore = StateObject(wrappedValue: debugStore)
    }

    var body: some Scene {
        MenuBarExtra("Spofty", systemImage: "music.note") {
            MenuBarContentView(viewModel: viewModel, debugLogStore: debugLogStore)
        }
        .menuBarExtraStyle(.window)
    }
}
