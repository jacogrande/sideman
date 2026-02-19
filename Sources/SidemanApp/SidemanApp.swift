import AppKit
import SwiftUI

@main
struct SidemanApp: App {
    @StateObject private var viewModel: MenuBarViewModel
    @StateObject private var spotifyAuthState: SpotifyAuthState
    private static func hasVisiblePixels(_ image: NSImage) -> Bool {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else {
            return false
        }

        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                    return true
                }
            }
        }
        return false
    }

    private static let toolbarIcon: NSImage? = {
        guard
            let url = Bundle.module.url(forResource: "ToolbarIconTemplate", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        guard hasVisiblePixels(image) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    init() {
        let nowPlayingProvider = SpotifyAppleScriptNowPlayingProvider()
        let creditsCache = MemoryDiskCreditsCache()
        let backend = CreditsBackend.fromEnvironment()
        let creditsProvider = CreditsProviderFactory.makeProvider(backend: backend, cache: creditsCache)

        DebugLogger.log(.app, "credits backend=\(backend.rawValue)")

        let spotifyAuth = SpotifyAuthState()
        let musicBrainzClient = MusicBrainzHTTPClient()
        let playlistBuilder = CreditsProviderFactory.makePlaylistBuilder(spotifyClient: spotifyAuth.client)

        let vm = MenuBarViewModel(
            provider: nowPlayingProvider,
            creditsProvider: creditsProvider
        )
        vm.playlistVM.configure(builder: playlistBuilder, authState: spotifyAuth, musicBrainzClient: musicBrainzClient)

        _viewModel = StateObject(wrappedValue: vm)
        _spotifyAuthState = StateObject(wrappedValue: spotifyAuth)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel, spotifyAuthState: spotifyAuthState)
                .task {
                    await spotifyAuthState.restoreSession()
                }
        } label: {
            if let icon = Self.toolbarIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "music.note")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
