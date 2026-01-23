import Foundation
import MediaPlayer

final class NowPlayingManager {
    struct Info {
        let title: String
        let artist: String?
        let duration: TimeInterval?
        let elapsed: TimeInterval?
        let rate: Float
        let isPlaying: Bool
    }

    private let commandCenter = MPRemoteCommandCenter.shared()
    private let logNowPlayingDebug = false
    private let supportedRates: [NSNumber] = [
        0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0
    ]

    func configureCommands(play: @escaping () -> Bool,
                           pause: @escaping () -> Bool,
                           toggle: @escaping () -> Bool,
                           skipForward: @escaping () -> Bool,
                           skipBackward: @escaping () -> Bool,
                           seek: @escaping (TimeInterval) -> Bool,
                           changeRate: @escaping (Float) -> Bool) {
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.changePlaybackRateCommand.removeTarget(nil)

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackRateCommand.isEnabled = true
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = supportedRates

        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.preferredIntervals = [15]

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.logCommand("play")
            let scheduled = self.runOnMain { play() }
            self.logCommand("play", result: scheduled)
            return self.status(for: scheduled)
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.logCommand("pause")
            let scheduled = self.runOnMain { pause() }
            self.logCommand("pause", result: scheduled)
            return self.status(for: scheduled)
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.logCommand("toggle")
            let scheduled = self.runOnMain { toggle() }
            self.logCommand("toggle", result: scheduled)
            return self.status(for: scheduled)
        }
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.logCommand("skipForward")
            let scheduled = self.runOnMain { skipForward() }
            self.logCommand("skipForward", result: scheduled)
            return self.status(for: scheduled)
        }
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.logCommand("skipBackward")
            let scheduled = self.runOnMain { skipBackward() }
            self.logCommand("skipBackward", result: scheduled)
            return self.status(for: scheduled)
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.logCommand("seek", detail: "position=\(event.positionTime)")
            let scheduled = self.runOnMain { seek(event.positionTime) }
            self.logCommand("seek", result: scheduled)
            return self.status(for: scheduled)
        }
        commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            guard let event = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            self.logCommand("rate", detail: "rate=\(event.playbackRate)")
            let scheduled = self.runOnMain { changeRate(event.playbackRate) }
            self.logCommand("rate", result: scheduled)
            return self.status(for: scheduled)
        }
    }

    func updateNowPlaying(_ info: Info?) {
        guard let info else {
            if logNowPlayingDebug {
                print("[NowPlaying][debug] cleared")
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var nowPlaying: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? info.rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: info.rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if let elapsed = info.elapsed {
            nowPlaying[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }

        if let duration = info.duration {
            nowPlaying[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let artist = info.artist {
            nowPlaying[MPMediaItemPropertyArtist] = artist
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
        if logNowPlayingDebug {
            print("[NowPlaying][debug] updated title=\(info.title) playing=\(info.isPlaying) rate=\(info.rate) elapsed=\(info.elapsed ?? -1) duration=\(info.duration ?? -1)")
        }
    }

    func updateCommandAvailability(isPlaying: Bool, canSeek: Bool) {
        commandCenter.playCommand.isEnabled = !isPlaying
        commandCenter.pauseCommand.isEnabled = isPlaying
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = canSeek
    }

    private func runOnMain<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        }
        var result: T!
        DispatchQueue.main.sync {
            result = block()
        }
        return result
    }

    private func status(for scheduled: Bool) -> MPRemoteCommandHandlerStatus {
        scheduled ? .success : .noSuchContent
    }

    private func logCommand(_ name: String, result: Bool? = nil, detail: String? = nil) {
        var parts = ["[RemoteCommand]", "cmd=\(name)"]
        if let detail {
            parts.append(detail)
        }
        if let result {
            parts.append("scheduled=\(result)")
        }
        print(parts.joined(separator: " "))
    }
}
