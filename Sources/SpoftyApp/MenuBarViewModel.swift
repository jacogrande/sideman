import Foundation
import Combine

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var snapshot: PlaybackSnapshot = .notRunning
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var creditsState: CreditsLookupState = .idle
    @Published private(set) var creditsBundle: CreditsBundle?

    private let provider: NowPlayingProvider
    private let creditsProvider: CreditsProvider?
    private let pollingIntervalNanos: UInt64
    private var pollingTask: Task<Void, Never>?
    private var creditsTask: Task<Void, Never>?
    private var lastCreditsTrackKey: String?

    init(
        provider: NowPlayingProvider,
        creditsProvider: CreditsProvider? = nil,
        pollingInterval: TimeInterval = 1.0,
        autoStart: Bool = true
    ) {
        self.provider = provider
        self.creditsProvider = creditsProvider
        self.pollingIntervalNanos = UInt64((pollingInterval * 1_000_000_000).rounded())

        if autoStart {
            start()
        }
    }

    deinit {
        pollingTask?.cancel()
        creditsTask?.cancel()
    }

    func start() {
        guard pollingTask == nil else {
            return
        }

        DebugLogger.log(.nowPlaying, "polling started interval=\(Double(pollingIntervalNanos) / 1_000_000_000.0)s")

        pollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                await self.refreshOnce()
                try? await Task.sleep(nanoseconds: self.pollingIntervalNanos)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        DebugLogger.log(.nowPlaying, "polling stopped")
    }

    func refreshOnce(forceCreditsRefresh: Bool = false) async {
        isLoading = true
        let latest = await provider.fetchSnapshot()
        _ = apply(snapshot: latest, at: Date())
        DebugLogger.log(.nowPlaying, "snapshot updated state=\(snapshotStateLabel(latest.state))")
        await refreshCreditsIfNeeded(for: latest, forceRefresh: forceCreditsRefresh)
    }

    @discardableResult
    func apply(snapshot next: PlaybackSnapshot, at date: Date) -> Bool {
        let changed = snapshot != next

        if changed {
            snapshot = next
        }

        lastUpdated = date
        isLoading = false
        return changed
    }

    private func refreshCreditsIfNeeded(for latestSnapshot: PlaybackSnapshot, forceRefresh: Bool) async {
        guard let creditsProvider else {
            DebugLogger.log(.provider, "credits provider unavailable")
            return
        }

        guard latestSnapshot.state == .playing, let track = latestSnapshot.track else {
            DebugLogger.log(.provider, "credits reset: playback not active")
            resetCreditsState()
            return
        }

        let trackKey = await creditsProvider.cacheLookupKey(for: track)
        if !forceRefresh, lastCreditsTrackKey == trackKey {
            DebugLogger.log(.provider, "credits skip: unchanged track key=\(trackKey)")
            return
        }

        if forceRefresh {
            await creditsProvider.invalidateCachedCredits(for: track)
            DebugLogger.log(.provider, "credits cache invalidated key=\(trackKey)")
        }

        DebugLogger.log(.provider, "credits lookup start key=\(trackKey)")
        lastCreditsTrackKey = trackKey
        creditsTask?.cancel()
        creditsState = .resolving
        creditsBundle = nil

        creditsTask = Task { [weak self] in
            guard let self else {
                return
            }

            self.creditsState = .loadingCredits
            let (state, bundle) = await creditsProvider.lookupCredits(for: track)

            guard !Task.isCancelled else {
                return
            }

            guard self.lastCreditsTrackKey == trackKey else {
                DebugLogger.log(.provider, "credits discard stale key=\(trackKey)")
                return
            }

            DebugLogger.log(.provider, "credits lookup complete state=\(state)")
            self.creditsState = state
            self.creditsBundle = bundle
        }
    }

    private func resetCreditsState() {
        creditsTask?.cancel()
        creditsTask = nil
        lastCreditsTrackKey = nil
        creditsState = .idle
        creditsBundle = nil
    }

    private func snapshotStateLabel(_ state: PlaybackState) -> String {
        switch state {
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .notRunning:
            return "not_running"
        case .unknown:
            return "unknown"
        }
    }
}
