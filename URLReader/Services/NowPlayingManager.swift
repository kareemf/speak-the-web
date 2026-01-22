import Foundation
import MediaPlayer

final class NowPlayingManager {
    struct Info {
        let title: String
        let artist: String?
        let duration: TimeInterval
        let elapsed: TimeInterval
        let rate: Float
        let isPlaying: Bool
    }

    private let commandCenter = MPRemoteCommandCenter.shared()

    func configureCommands(play: @escaping () -> Void,
                           pause: @escaping () -> Void,
                           toggle: @escaping () -> Void,
                           skipForward: @escaping () -> Void,
                           skipBackward: @escaping () -> Void,
                           seek: @escaping (TimeInterval) -> Void) {
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true

        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.preferredIntervals = [15]

        commandCenter.playCommand.addTarget { _ in
            DispatchQueue.main.async {
                play()
            }
            return .success
        }
        commandCenter.pauseCommand.addTarget { _ in
            DispatchQueue.main.async {
                pause()
            }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            DispatchQueue.main.async {
                toggle()
            }
            return .success
        }
        commandCenter.skipForwardCommand.addTarget { _ in
            DispatchQueue.main.async {
                skipForward()
            }
            return .success
        }
        commandCenter.skipBackwardCommand.addTarget { _ in
            DispatchQueue.main.async {
                skipBackward()
            }
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            DispatchQueue.main.async {
                seek(event.positionTime)
            }
            return .success
        }
    }

    func updateNowPlaying(_ info: Info?) {
        guard let info else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }

        var nowPlaying: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.elapsed,
            MPMediaItemPropertyPlaybackDuration: info.duration,
            MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? info.rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: info.rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if let artist = info.artist {
            nowPlaying[MPMediaItemPropertyArtist] = artist
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
        MPNowPlayingInfoCenter.default().playbackState = info.isPlaying ? .playing : .paused
    }
}
