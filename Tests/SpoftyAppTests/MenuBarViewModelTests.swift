import XCTest
@testable import SpoftyApp

final class MenuBarViewModelTests: XCTestCase {
    @MainActor
    func testApplyReturnsFalseWhenSnapshotUnchanged() {
        let vm = MenuBarViewModel(provider: StaticProvider(snapshot: .notRunning), autoStart: false)

        let changed = vm.apply(snapshot: .notRunning, at: Date(timeIntervalSince1970: 100))

        XCTAssertFalse(changed)
        XCTAssertEqual(vm.snapshot.state, .notRunning)
        XCTAssertEqual(vm.lastUpdated, Date(timeIntervalSince1970: 100))
    }

    @MainActor
    func testApplyReturnsTrueWhenSnapshotChanged() {
        let vm = MenuBarViewModel(provider: StaticProvider(snapshot: .notRunning), autoStart: false)
        let track = NowPlayingTrack(id: "spotify:track:abc", title: "Song", artist: "Artist", album: "Album")

        let changed = vm.apply(snapshot: .playing(track), at: Date(timeIntervalSince1970: 200))

        XCTAssertTrue(changed)
        XCTAssertEqual(vm.snapshot.state, .playing)
        XCTAssertEqual(vm.snapshot.track?.title, "Song")
        XCTAssertEqual(vm.lastUpdated, Date(timeIntervalSince1970: 200))
    }

    @MainActor
    func testRefreshOnceAppliesProviderSnapshot() async {
        let track = NowPlayingTrack(id: "spotify:track:def", title: "Another Song", artist: "Another Artist", album: "Another Album")
        let vm = MenuBarViewModel(provider: StaticProvider(snapshot: .playing(track)), autoStart: false)

        await vm.refreshOnce()

        XCTAssertEqual(vm.snapshot.state, .playing)
        XCTAssertEqual(vm.snapshot.track?.id, "spotify:track:def")
        XCTAssertNotNil(vm.lastUpdated)
        XCTAssertFalse(vm.isLoading)
    }
}

private actor StaticProvider: NowPlayingProvider {
    let snapshot: PlaybackSnapshot

    init(snapshot: PlaybackSnapshot) {
        self.snapshot = snapshot
    }

    func fetchSnapshot() async -> PlaybackSnapshot {
        snapshot
    }
}
