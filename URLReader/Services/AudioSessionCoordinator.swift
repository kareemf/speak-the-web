import Foundation
import AVFoundation

final class AudioSessionCoordinator {
    private let session = AVAudioSession.sharedInstance()
    private var observers: [NSObjectProtocol] = []
    private var activeEngine: SpeechEngineType?

    init() {
        registerNotifications()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func activate(for engine: SpeechEngineType, reason: String = "play") {
        let category: AVAudioSession.Category = .playback
        let mode: AVAudioSession.Mode = .spokenAudio
        let options: AVAudioSession.CategoryOptions = [.duckOthers]

        do {
            try session.setCategory(category, mode: mode, options: options)
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
            activeEngine = engine
            log(action: "activate", engine: engine, reason: reason, category: category, mode: mode, options: options, error: nil)
        } catch {
            log(action: "activate", engine: engine, reason: reason, category: category, mode: mode, options: options, error: error)
        }
    }

    func deactivate(reason: String = "stop") {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            log(action: "deactivate", engine: activeEngine, reason: reason, category: nil, mode: nil, options: nil, error: nil)
        } catch {
            log(action: "deactivate", engine: activeEngine, reason: reason, category: nil, mode: nil, options: nil, error: error)
        }
        activeEngine = nil
    }

    private func registerNotifications() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
            self?.handleInterruption(notification)
        })

        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] notification in
            self?.handleRouteChange(notification)
        })

        observers.append(center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: session, queue: .main) { [weak self] notification in
            self?.handleSilenceHint(notification)
        })
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        let reasonText: String
        if let reasonValue = info[AVAudioSessionInterruptionReasonKey] as? UInt,
           let reason = AVAudioSession.InterruptionReason(rawValue: reasonValue) {
            reasonText = String(describing: reason)
        } else {
            reasonText = "unknown"
        }

        log(action: "interruption-\(type)", engine: activeEngine, reason: reasonText, category: nil, mode: nil, options: nil, error: nil)
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        log(action: "route-change", engine: activeEngine, reason: String(describing: reason), category: nil, mode: nil, options: nil, error: nil)
    }

    private func handleSilenceHint(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeValue) else {
            return
        }

        log(action: "silence-hint", engine: activeEngine, reason: String(describing: type), category: nil, mode: nil, options: nil, error: nil)
    }

    private func log(action: String,
                     engine: SpeechEngineType?,
                     reason: String?,
                     category: AVAudioSession.Category?,
                     mode: AVAudioSession.Mode?,
                     options: AVAudioSession.CategoryOptions?,
                     error: Error?) {
        var parts: [String] = ["[AudioSession]", "action=\(action)"]

        if let engine {
            parts.append("engine=\(engine.rawValue)")
        } else {
            parts.append("engine=none")
        }

        if let reason {
            parts.append("reason=\(reason)")
        }

        if let category {
            parts.append("category=\(category.rawValue)")
        }

        if let mode {
            parts.append("mode=\(mode.rawValue)")
        }

        if let options {
            parts.append("options=\(describe(options: options))")
        }

        parts.append("otherAudio=\(session.isOtherAudioPlaying)")
        parts.append("silenceHint=\(session.secondaryAudioShouldBeSilencedHint)")
        parts.append("route=\(describe(route: session.currentRoute))")

        if let error {
            parts.append("error=\(error)")
        }

        print(parts.joined(separator: " "))
    }

    private func describe(options: AVAudioSession.CategoryOptions) -> String {
        if options.isEmpty {
            return "[]"
        }
        let all: [(AVAudioSession.CategoryOptions, String)] = [
            (.mixWithOthers, "mixWithOthers"),
            (.duckOthers, "duckOthers"),
            (.interruptSpokenAudioAndMixWithOthers, "interruptSpokenAudioAndMixWithOthers"),
            (.allowBluetooth, "allowBluetooth"),
            (.allowBluetoothA2DP, "allowBluetoothA2DP"),
            (.allowAirPlay, "allowAirPlay"),
            (.defaultToSpeaker, "defaultToSpeaker")
        ]
        let enabled = all.compactMap { options.contains($0.0) ? $0.1 : nil }
        return "[\(enabled.joined(separator: ","))]"
    }

    private func describe(route: AVAudioSessionRouteDescription) -> String {
        let outputs = route.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        let inputs = route.inputs.map { $0.portType.rawValue }.joined(separator: ",")
        return "out=[\(outputs)] in=[\(inputs)]"
    }
}
