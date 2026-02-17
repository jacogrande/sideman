import Foundation

enum PlaybackState: Equatable {
    case playing
    case paused
    case notRunning
    case unknown
}

struct NowPlayingTrack: Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let trackNumber: Int?

    init(
        id: String,
        title: String,
        artist: String,
        album: String,
        trackNumber: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
    }
}

struct PlaybackSnapshot: Equatable {
    let state: PlaybackState
    let track: NowPlayingTrack?
    let errorMessage: String?

    static let paused = PlaybackSnapshot(state: .paused, track: nil, errorMessage: nil)
    static let notRunning = PlaybackSnapshot(state: .notRunning, track: nil, errorMessage: nil)

    static func unknown(_ message: String?) -> PlaybackSnapshot {
        PlaybackSnapshot(state: .unknown, track: nil, errorMessage: message)
    }

    static func playing(_ track: NowPlayingTrack) -> PlaybackSnapshot {
        PlaybackSnapshot(state: .playing, track: track, errorMessage: nil)
    }
}
