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

    @MainActor
    func testForceRefreshInvalidatesAndReloadsCreditsForSameTrack() async {
        let track = NowPlayingTrack(id: "spotify:track:force", title: "Song", artist: "Artist", album: "Album")
        let nowPlaying = SequentialNowPlayingProvider(
            snapshots: [
                .playing(track),
                .playing(track)
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
            resolvedRecordingMBID: "rec-force"
        )

        let creditsProvider = SpyCreditsProvider(response: (.loaded, bundle))
        let viewModel = MenuBarViewModel(
            provider: nowPlaying,
            creditsProvider: creditsProvider,
            autoStart: false
        )

        await viewModel.refreshOnce()
        try? await Task.sleep(nanoseconds: 80_000_000)

        await viewModel.refreshOnce(forceCreditsRefresh: true)
        try? await Task.sleep(nanoseconds: 80_000_000)

        let lookups = await creditsProvider.lookupCount
        let invalidations = await creditsProvider.invalidationCount
        XCTAssertEqual(lookups, 2)
        XCTAssertEqual(invalidations, 1)
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

    func cacheLookupKey(for track: NowPlayingTrack) async -> String {
        "static:\(track.id.lowercased())"
    }
}

private actor SpyCreditsProvider: CreditsProvider {
    let response: (CreditsLookupState, CreditsBundle?)
    private(set) var lookupCount = 0
    private(set) var invalidationCount = 0

    init(response: (CreditsLookupState, CreditsBundle?)) {
        self.response = response
    }

    func lookupCredits(for track: NowPlayingTrack) async -> (CreditsLookupState, CreditsBundle?) {
        lookupCount += 1
        return response
    }

    func cacheLookupKey(for track: NowPlayingTrack) async -> String {
        "spy:\(track.id.lowercased())"
    }

    func invalidateCachedCredits(for track: NowPlayingTrack) async {
        invalidationCount += 1
    }
}
