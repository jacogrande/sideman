import XCTest
@testable import SpoftyApp

final class MenuBarCreditsStateTests: XCTestCase {
    @MainActor
    func testCreditsLoadForPlayingTrackAndResetWhenPlaybackStops() async {
        let track = NowPlayingTrack(id: "spotify:track:1", title: "Song", artist: "Artist", album: "Album")
        let nowPlaying = SequentialNowPlayingProvider(
            snapshots: [
                .playing(track),
                .paused
            ]
        )

        let bundle = CreditsBundle(
            entriesByGroup: [.production: [
                CreditEntry(
                    personName: "Producer",
                    personMBID: "p1",
                    roleRaw: "producer",
                    roleGroup: .production,
                    sourceLevel: .recording,
                    instrument: nil
                )
            ]],
            provenance: [.recording],
            resolvedRecordingMBID: "rec-1"
        )

        let creditsProvider = StaticCreditsProvider(response: (.loaded, bundle))
        let viewModel = MenuBarViewModel(
            provider: nowPlaying,
            creditsProvider: creditsProvider,
            autoStart: false
        )

        await viewModel.refreshOnce()
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(viewModel.creditsState, .loaded)
        XCTAssertEqual(viewModel.creditsBundle?.resolvedRecordingMBID, "rec-1")

        await viewModel.refreshOnce()

        XCTAssertEqual(viewModel.creditsState, .idle)
        XCTAssertNil(viewModel.creditsBundle)
    }
}

private actor SequentialNowPlayingProvider: NowPlayingProvider {
    private var snapshots: [PlaybackSnapshot]
    private var index = 0

    init(snapshots: [PlaybackSnapshot]) {
        self.snapshots = snapshots
    }

    func fetchSnapshot() async -> PlaybackSnapshot {
        guard !snapshots.isEmpty else {
            return .notRunning
        }

        let snapshot = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return snapshot
    }
}

private actor StaticCreditsProvider: CreditsProvider {
    let response: (CreditsLookupState, CreditsBundle?)

    init(response: (CreditsLookupState, CreditsBundle?)) {
        self.response = response
    }

    func lookupCredits(for track: NowPlayingTrack) async -> (CreditsLookupState, CreditsBundle?) {
        response
    }
}
