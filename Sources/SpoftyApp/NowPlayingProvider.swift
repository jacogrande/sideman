import Foundation

protocol NowPlayingProvider {
    func fetchSnapshot() async -> PlaybackSnapshot
}
