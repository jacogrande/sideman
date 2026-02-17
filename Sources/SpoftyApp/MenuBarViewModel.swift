import Foundation
import Combine

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var snapshot: PlaybackSnapshot = .notRunning
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false

    private let provider: NowPlayingProvider
    private let pollingIntervalNanos: UInt64
    private var pollingTask: Task<Void, Never>?

    init(provider: NowPlayingProvider, pollingInterval: TimeInterval = 1.0, autoStart: Bool = true) {
        self.provider = provider
        self.pollingIntervalNanos = UInt64((pollingInterval * 1_000_000_000).rounded())

        if autoStart {
            start()
        }
    }

    deinit {
        pollingTask?.cancel()
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
}
