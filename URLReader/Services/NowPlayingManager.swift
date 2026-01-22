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
            play()
            return .success
        }
        commandCenter.pauseCommand.addTarget { _ in
            pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            toggle()
            return .success
        }
        commandCenter.skipForwardCommand.addTarget { _ in
            skipForward()
            return .success
        }
        commandCenter.skipBackwardCommand.addTarget { _ in
            skipBackward()
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            seek(event.positionTime)
            return .success
        }
    }

    func updateNowPlaying(_ info: Info?) {
        guard let info else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
    }
}
