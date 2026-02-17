import SwiftUI

@main
struct SpoftyApp: App {
    @StateObject private var viewModel = MenuBarViewModel(provider: SpotifyAppleScriptNowPlayingProvider())

    var body: some Scene {
        MenuBarExtra("Spofty", systemImage: "music.note") {
            MenuBarContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
