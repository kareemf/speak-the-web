import AVFoundation
import Foundation

final class AudioSessionCoordinator {
    private let session = AVAudioSession.sharedInstance()
    private var observers: [NSObjectProtocol] = []
    private var activeEngine: SpeechEngineType?
    private var isActive = false
    var onInterruptionBegan: ((AVAudioSession.InterruptionReason?) -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?
    var onRouteChange: ((AVAudioSession.RouteChangeReason) -> Void)?

    init() {
        registerNotifications()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @discardableResult
    func activate(for engine: SpeechEngineType, reason: String = "play") -> Bool {
        let category: AVAudioSession.Category = .playback
        let mode: AVAudioSession.Mode = .spokenAudio
        let options: AVAudioSession.CategoryOptions = []

        log(
            action: "activate-pre",
            engine: engine,
            reason: reason,
            category: session.category,
            mode: session.mode,
            options: session.categoryOptions,
            error: nil
        )

        do {
            if session.category != category || session.mode != mode || session.categoryOptions != options {
                try session.setCategory(category, mode: mode, options: options)
            }
        } catch {
            log(
                action: "set-category-failed",
                engine: engine,
                reason: reason,
                category: category,
                mode: mode,
                options: options,
                error: error
            )
            return false
        }

        do {
            try session.setActive(true)
            activeEngine = engine
            isActive = true
            log(action: "activate", engine: engine, reason: reason, category: category, mode: mode, options: options, error: nil)
            return true
        } catch {
            log(
                action: "set-active-failed",
                engine: engine,
                reason: reason,
                category: category,
                mode: mode,
                options: options,
                error: error
            )
            return false
        }
    }

    func deactivate(reason: String = "stop") {
        guard isActive else {
            log(action: "deactivate", engine: activeEngine, reason: reason, category: nil, mode: nil, options: nil, error: nil)
            activeEngine = nil
            return
        }
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            log(action: "deactivate", engine: activeEngine, reason: reason, category: nil, mode: nil, options: nil, error: nil)
        } catch {
            log(action: "deactivate", engine: activeEngine, reason: reason, category: nil, mode: nil, options: nil, error: error)
        }
        isActive = false
        activeEngine = nil
    }

    private func registerNotifications() {
        let center = NotificationCenter.default

        observers
            .append(center
                .addObserver(
                    forName: AVAudioSession.interruptionNotification,
                    object: session,
                    queue: .main
                ) { [weak self] notification in
                    self?.handleInterruption(notification)
                })

        observers
            .append(center
                .addObserver(
                    forName: AVAudioSession.routeChangeNotification,
                    object: session,
                    queue: .main
                ) { [weak self] notification in
                    self?.handleRouteChange(notification)
                })

        observers.append(center.addObserver(
            forName: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleSilenceHint(notification)
        })
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        let reason: AVAudioSession.InterruptionReason? = if let reasonValue = info[AVAudioSessionInterruptionReasonKey] as? UInt {
            AVAudioSession.InterruptionReason(rawValue: reasonValue)
        } else {
            nil
        }

        var reasonText = reason.map { String(describing: $0) } ?? "unknown"
        if type == .began {
            isActive = false
            onInterruptionBegan?(reason)
        } else if type == .ended {
            let optionValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionValue)
            let shouldResume = options.contains(.shouldResume)
            reasonText += " shouldResume=\(shouldResume)"
            onInterruptionEnded?(shouldResume)
        }

        log(
            action: "interruption-\(type)",
            engine: activeEngine,
            reason: reasonText,
            category: nil,
            mode: nil,
            options: nil,
            error: nil
        )
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
            return
        }

        onRouteChange?(reason)
        log(
            action: "route-change",
            engine: activeEngine,
            reason: String(describing: reason),
            category: nil,
            mode: nil,
            options: nil,
            error: nil
        )
    }

    private func handleSilenceHint(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeValue)
        else {
            return
        }

        log(
            action: "silence-hint",
            engine: activeEngine,
            reason: String(describing: type),
            category: nil,
            mode: nil,
            options: nil,
            error: nil
        )
    }

    private func log(
        action: String,
        engine: SpeechEngineType?,
        reason: String?,
        category: AVAudioSession.Category?,
        mode: AVAudioSession.Mode?,
        options: AVAudioSession.CategoryOptions?,
        error: Error?
    ) {
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
            (.allowBluetoothHFP, "allowBluetoothHFP"),
            (.allowBluetoothA2DP, "allowBluetoothA2DP"),
            (.allowAirPlay, "allowAirPlay"),
            (.defaultToSpeaker, "defaultToSpeaker"),
        ]
        let enabled = all.compactMap { options.contains($0.0) ? $0.1 : nil }
        return "[\(enabled.joined(separator: ","))]"
    }

    private func describe(route: AVAudioSessionRouteDescription) -> String {
        let outputs = route.outputs.map(\.portType.rawValue).joined(separator: ",")
        let inputs = route.inputs.map(\.portType.rawValue).joined(separator: ",")
        return "out=[\(outputs)] in=[\(inputs)]"
    }
}
