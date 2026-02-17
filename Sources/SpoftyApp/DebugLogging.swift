import Foundation
import Combine

enum DebugLogCategory: String, CaseIterable {
    case app
    case ui
    case nowPlaying
    case resolver
    case provider
    case network
    case cache

    var title: String {
        rawValue.uppercased()
    }
}

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: DebugLogCategory
    let message: String
}

extension Notification.Name {
    static let spoftyDebugLog = Notification.Name("spofty.debug.log")
}

enum DebugLogger {
    static func log(_ category: DebugLogCategory, _ message: String) {
        let entry = DebugLogEntry(timestamp: Date(), category: category, message: message)
        let timestamp = String(format: "%.3f", entry.timestamp.timeIntervalSince1970)
        fputs("[SPOFTY][\(category.title)][\(timestamp)] \(message)\n", stderr)
        NotificationCenter.default.post(name: .spoftyDebugLog, object: entry)
    }
}

@MainActor
final class DebugLogStore: ObservableObject {
    @Published private(set) var entries: [DebugLogEntry] = []
    @Published private(set) var isEnabled = false

    private let maxEntries: Int
    private var observerCancellable: AnyCancellable?

    init(maxEntries: Int = 350) {
        self.maxEntries = maxEntries
        observerCancellable = NotificationCenter.default.publisher(for: .spoftyDebugLog)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handle(notification: notification)
            }
    }

    deinit {
        observerCancellable?.cancel()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled

        if enabled {
            DebugLogger.log(.app, "Debug mode enabled")
        } else {
            entries.removeAll()
        }
    }

    func clear() {
        entries.removeAll()
        if isEnabled {
            DebugLogger.log(.ui, "Debug log cleared")
        }
    }

    private func handle(notification: Notification) {
        guard isEnabled else {
            return
        }

        guard let entry = notification.object as? DebugLogEntry else {
            return
        }

        entries.append(entry)

        if entries.count > maxEntries {
            let overflow = entries.count - maxEntries
            entries.removeFirst(overflow)
        }
    }
}
