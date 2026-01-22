import Foundation
import Combine

@MainActor
final class MediaPlaybackController: ObservableObject {
    let speechService = SpeechService()
    let sherpaSpeechService = SherpaSpeechService()

    private let audioSession = AudioSessionCoordinator()
    private var cancellables = Set<AnyCancellable>()

    init() {
        relayEngineChanges()
    }

    func play(engine: SpeechEngineType) {
        let service = activeService(for: engine)
        guard !service.isPlaying else { return }

        if engine == .avSpeech {
            speechService.prepareForPlayback()
        }

        guard audioSession.activate(for: engine) else { return }
        DispatchQueue.main.async {
            service.play()
        }
    }

    func pause(engine: SpeechEngineType) {
        activeService(for: engine).pause()
    }

    func togglePlayPause(engine: SpeechEngineType) {
        let service = activeService(for: engine)
        if service.isPlaying {
            service.pause()
        } else {
            play(engine: engine)
        }
    }

    func stop(engine: SpeechEngineType) {
        activeService(for: engine).stop()
        audioSession.deactivate(reason: "stop")
    }

    func stopAll() {
        speechService.stop()
        sherpaSpeechService.stop()
        audioSession.deactivate(reason: "stop-all")
    }

    func skipForward(engine: SpeechEngineType) {
        activeService(for: engine).skipForward()
    }

    func skipBackward(engine: SpeechEngineType) {
        activeService(for: engine).skipBackward()
    }

    func seek(engine: SpeechEngineType, position: Int) {
        activeService(for: engine).seekTo(position: position)
    }

    func setRate(multiplier: Float) {
        speechService.setRate(multiplier: multiplier)
        sherpaSpeechService.setRate(multiplier: multiplier)
    }

    func loadContent(_ text: String) {
        speechService.loadContent(text)
        sherpaSpeechService.loadContent(text)
    }

    func setArticleURL(_ url: String?) {
        sherpaSpeechService.setArticleURL(url)
    }

    private func activeService(for engine: SpeechEngineType) -> PlaybackService {
        switch engine {
        case .avSpeech:
            return .avSpeech(speechService)
        case .sherpaOnnx:
            return .sherpa(sherpaSpeechService)
        }
    }

    private func relayEngineChanges() {
        speechService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        sherpaSpeechService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

private enum PlaybackService {
    case avSpeech(SpeechService)
    case sherpa(SherpaSpeechService)

    var isPlaying: Bool {
        switch self {
        case .avSpeech(let service):
            return service.isPlaying
        case .sherpa(let service):
            return service.isPlaying
        }
    }

    func play() {
        switch self {
        case .avSpeech(let service):
            service.play()
        case .sherpa(let service):
            service.play()
        }
    }

    func pause() {
        switch self {
        case .avSpeech(let service):
            service.pause()
        case .sherpa(let service):
            service.pause()
        }
    }

    func stop() {
        switch self {
        case .avSpeech(let service):
            service.stop()
        case .sherpa(let service):
            service.stop()
        }
    }

    func skipForward() {
        switch self {
        case .avSpeech(let service):
            service.skipForward()
        case .sherpa(let service):
            service.skipForward()
        }
    }

    func skipBackward() {
        switch self {
        case .avSpeech(let service):
            service.skipBackward()
        case .sherpa(let service):
            service.skipBackward()
        }
    }

    func seekTo(position: Int) {
        switch self {
        case .avSpeech(let service):
            service.seekTo(position: position)
        case .sherpa(let service):
            service.seekTo(position: position)
        }
    }
}
