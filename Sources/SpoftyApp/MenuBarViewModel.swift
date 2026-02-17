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
    }

    func refreshOnce() async {
        isLoading = true
        let latest = await provider.fetchSnapshot()
        _ = apply(snapshot: latest, at: Date())
        await refreshCreditsIfNeeded(for: latest)
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

    private func refreshCreditsIfNeeded(for latestSnapshot: PlaybackSnapshot) async {
        guard let creditsProvider else {
            return
        }

        guard latestSnapshot.state == .playing, let track = latestSnapshot.track else {
            resetCreditsState()
            return
        }

        let trackKey = DefaultCreditsProvider.cacheKey(for: track)
        if lastCreditsTrackKey == trackKey {
            return
        }

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
                return
            }

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
}
