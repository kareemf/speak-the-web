import Foundation
import Combine

@MainActor
final class MediaPlaybackController: ObservableObject {
    private var speechService: SpeechService?
    private var sherpaSpeechService: SherpaSpeechService?

    private let audioSession = AudioSessionCoordinator()
    private let nowPlaying = NowPlayingManager()

    private var cancellables = Set<AnyCancellable>()
    private var nowPlayingTimer: Timer?

    private var currentText: String = ""
    private var currentTextLength: Int = 0
    private var currentArticleURL: String?
    private var nowPlayingTitle: String?
    private var nowPlayingArtist: String?
    private var nowPlayingWordCount: Int = 0
    private var lastKnownPosition: Int = 0
    private var rateMultiplier: Float = 1.0
    private var selectedEngine: SpeechEngineType = .avSpeech
    private var pendingSherpaModel: SherpaModelRecord?

    @Published var lastErrorMessage: String?
    var canUseEngine: ((SpeechEngineType) -> Bool)?

    init() {
        configureNowPlayingCommands()
    }

    func selectEngine(_ engine: SpeechEngineType) {
        guard selectedEngine != engine else { return }
        stop(engine: selectedEngine)
        selectedEngine = engine
        _ = service(for: engine, createIfNeeded: true)
        updateNowPlayingInfo()
    }

    func preload(engine: SpeechEngineType) {
        _ = service(for: engine, createIfNeeded: true)
    }

    func activateSession(for engine: SpeechEngineType, reason: String) -> Bool {
        audioSession.activate(for: engine, reason: reason)
    }

    func playSelectedEngine() {
        guard canUse(engine: selectedEngine) else { return }
        play(engine: selectedEngine)
    }

    func pauseSelectedEngine() {
        pause(engine: selectedEngine)
    }

    func togglePlayPauseSelectedEngine() {
        guard canUse(engine: selectedEngine) else { return }
        togglePlayPause(engine: selectedEngine)
    }

    func skipForwardSelectedEngine() {
        guard canUse(engine: selectedEngine) else { return }
        skipForward(engine: selectedEngine)
    }

    func skipBackwardSelectedEngine() {
        guard canUse(engine: selectedEngine) else { return }
        skipBackward(engine: selectedEngine)
    }

    func seekSelectedEngine(to time: TimeInterval) {
        guard canUse(engine: selectedEngine) else { return }
        guard let duration = playbackDuration(for: selectedEngine), duration > 0 else { return }
        let progress = max(0, min(1, time / duration))
        let position = Int(Double(currentTextLength) * progress)
        seek(engine: selectedEngine, position: position)
    }

    func play(engine: SpeechEngineType) {
        selectedEngine = engine
        guard let service = service(for: engine, createIfNeeded: true) else { return }
        guard !service.isPlaying else { return }

        guard audioSession.activate(for: engine) else { return }
        if engine == .avSpeech {
            speechService?.prepareForPlayback()
        }
        service.play()
        startNowPlayingTimer()
        updateNowPlayingInfo()
    }

    func pause(engine: SpeechEngineType) {
        service(for: engine, createIfNeeded: false)?.pause()
        stopNowPlayingTimer()
        updateNowPlayingInfo()
    }

    func togglePlayPause(engine: SpeechEngineType) {
        guard let service = service(for: engine, createIfNeeded: true) else { return }
        if service.isPlaying {
            pause(engine: engine)
        } else {
            play(engine: engine)
        }
    }

    func stop(engine: SpeechEngineType) {
        service(for: engine, createIfNeeded: false)?.stop()
        audioSession.deactivate(reason: "stop")
        stopNowPlayingTimer()
        updateNowPlayingInfo()
    }

    func stopAll() {
        speechService?.stop()
        sherpaSpeechService?.stop()
        audioSession.deactivate(reason: "stop-all")
        stopNowPlayingTimer()
        updateNowPlayingInfo()
    }

    func skipForward(engine: SpeechEngineType) {
        service(for: engine, createIfNeeded: true)?.skipForward()
        updateNowPlayingInfo()
    }

    func skipBackward(engine: SpeechEngineType) {
        service(for: engine, createIfNeeded: true)?.skipBackward()
        updateNowPlayingInfo()
    }

    func seek(engine: SpeechEngineType, position: Int) {
        service(for: engine, createIfNeeded: true)?.seekTo(position: position)
        lastKnownPosition = position
        updateNowPlayingInfo()
    }

    func seekToSection(_ section: ArticleSection, engine: SpeechEngineType) {
        switch engine {
        case .avSpeech:
            ensureSpeechService().seekToSection(section)
        case .sherpaOnnx:
            ensureSherpaService().seekTo(position: section.startIndex)
        }
        lastKnownPosition = section.startIndex
        updateNowPlayingInfo()
    }

    func setPosition(_ position: Int) {
        lastKnownPosition = position
        speechService?.setPosition(position)
        sherpaSpeechService?.setPosition(position)
        updateNowPlayingInfo()
    }

    func setRate(multiplier: Float) {
        rateMultiplier = multiplier
        speechService?.setRate(multiplier: multiplier)
        sherpaSpeechService?.setRate(multiplier: multiplier)
        updateNowPlayingInfo()
    }

    func loadContent(_ text: String) {
        currentText = text
        currentTextLength = text.count
        lastKnownPosition = 0
        speechService?.loadContent(text)
        sherpaSpeechService?.loadContent(text)
    }

    func setArticleURL(_ url: String?) {
        currentArticleURL = url
        sherpaSpeechService?.setArticleURL(url)
    }

    func updateSherpaModel(record: SherpaModelRecord?) {
        pendingSherpaModel = record
        sherpaSpeechService?.updateModel(record: record)
    }

    func updateNowPlayingMetadata(title: String, artist: String?, wordCount: Int) {
        nowPlayingTitle = title
        nowPlayingArtist = artist
        nowPlayingWordCount = wordCount
        updateNowPlayingInfo()
    }

    func clearNowPlaying() {
        nowPlayingTitle = nil
        nowPlayingArtist = nil
        nowPlayingWordCount = 0
        nowPlaying.updateNowPlaying(nil)
    }

    func avSpeechService() -> SpeechService {
        ensureSpeechService()
    }

    func clearSherpaCachedAudio() {
        ensureSherpaService().clearCachedAudio()
    }

    func sherpaCachedAudioSizeBytes() -> Int {
        ensureSherpaService().cachedAudioSizeBytes()
    }

    func sherpaCachedAudioInfo(forArticleURL urlString: String) -> SherpaAudioCache.CachedAudioInfo? {
        ensureSherpaService().cachedAudioInfo(forArticleURL: urlString)
    }

    func removeSherpaCachedAudio(for urlString: String) {
        ensureSherpaService().removeCachedAudio(for: urlString)
    }

    func progress(for engine: SpeechEngineType) -> Double {
        service(for: engine, createIfNeeded: true)?.progress ?? 0.0
    }

    func isPlaying(for engine: SpeechEngineType) -> Bool {
        service(for: engine, createIfNeeded: true)?.isPlaying ?? false
    }

    func isFinished(for engine: SpeechEngineType) -> Bool {
        service(for: engine, createIfNeeded: true)?.isFinished ?? false
    }

    func isPreparing(for engine: SpeechEngineType) -> Bool {
        service(for: engine, createIfNeeded: true)?.isPreparing ?? false
    }

    func generationPhase(for engine: SpeechEngineType) -> String? {
        service(for: engine, createIfNeeded: true)?.generationPhase
    }

    func currentWord(for engine: SpeechEngineType) -> String {
        service(for: engine, createIfNeeded: true)?.currentWord ?? ""
    }

    func positionPublisher(for engine: SpeechEngineType) -> AnyPublisher<Int, Never> {
        switch engine {
        case .avSpeech:
            return ensureSpeechService().$currentPosition.eraseToAnyPublisher()
        case .sherpaOnnx:
            return ensureSherpaService().$currentPosition.eraseToAnyPublisher()
        }
    }

    private func configureNowPlayingCommands() {
        nowPlaying.configureCommands(
            play: { [weak self] in
                self?.playSelectedEngine()
            },
            pause: { [weak self] in
                self?.pauseSelectedEngine()
            },
            toggle: { [weak self] in
                self?.togglePlayPauseSelectedEngine()
            },
            skipForward: { [weak self] in
                self?.skipForwardSelectedEngine()
            },
            skipBackward: { [weak self] in
                self?.skipBackwardSelectedEngine()
            },
            seek: { [weak self] time in
                self?.seekSelectedEngine(to: time)
            }
        )
    }

    private func updateNowPlayingInfo() {
        guard let title = nowPlayingTitle else {
            nowPlaying.updateNowPlaying(nil)
            return
        }

        let engine = selectedEngine
        let duration = playbackDuration(for: engine)
        let elapsed = playbackElapsed(for: engine, duration: duration)
        let info = NowPlayingManager.Info(
            title: title,
            artist: nowPlayingArtist,
            duration: duration,
            elapsed: elapsed,
            rate: rateMultiplier,
            isPlaying: isPlaying(for: engine)
        )
        nowPlaying.updateNowPlaying(info)
    }

    private func playbackDuration(for engine: SpeechEngineType) -> TimeInterval? {
        if engine == .sherpaOnnx, let duration = sherpaSpeechService?.duration {
            return duration
        }
        guard nowPlayingWordCount > 0 else { return nil }
        let wordsPerMinute = 200.0
        let adjustedRate = max(0.1, Double(rateMultiplier))
        return (Double(nowPlayingWordCount) / (wordsPerMinute / 60.0)) / adjustedRate
    }

    private func playbackElapsed(for engine: SpeechEngineType, duration: TimeInterval?) -> TimeInterval? {
        if engine == .sherpaOnnx, let elapsed = sherpaSpeechService?.currentTime {
            return elapsed
        }
        guard let duration else { return nil }
        return duration * progress(for: engine)
    }

    private func startNowPlayingTimer() {
        stopNowPlayingTimer()
        nowPlayingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateNowPlayingInfo()
            }
        }
    }

    private func stopNowPlayingTimer() {
        nowPlayingTimer?.invalidate()
        nowPlayingTimer = nil
    }

    private func canUse(engine: SpeechEngineType) -> Bool {
        canUseEngine?(engine) ?? true
    }

    private func ensureSpeechService() -> SpeechService {
        if let speechService {
            return speechService
        }

        let service = SpeechService()
        speechService = service
        service.setRate(multiplier: rateMultiplier)
        if !currentText.isEmpty {
            service.loadContent(currentText)
        }
        if lastKnownPosition > 0 {
            service.setPosition(lastKnownPosition)
        }
        observeSpeechService(service)
        return service
    }

    private func ensureSherpaService() -> SherpaSpeechService {
        if let sherpaSpeechService {
            return sherpaSpeechService
        }

        let service = SherpaSpeechService()
        sherpaSpeechService = service
        service.setRate(multiplier: rateMultiplier)
        if !currentText.isEmpty {
            service.loadContent(currentText)
        }
        service.setArticleURL(currentArticleURL)
        service.updateModel(record: pendingSherpaModel)
        if lastKnownPosition > 0 {
            service.setPosition(lastKnownPosition)
        }
        observeSherpaService(service)
        return service
    }

    private func service(for engine: SpeechEngineType, createIfNeeded: Bool) -> PlaybackService? {
        switch engine {
        case .avSpeech:
            if createIfNeeded {
                return .avSpeech(ensureSpeechService())
            }
            guard let speechService else { return nil }
            return .avSpeech(speechService)
        case .sherpaOnnx:
            if createIfNeeded {
                return .sherpa(ensureSherpaService())
            }
            guard let sherpaSpeechService else { return nil }
            return .sherpa(sherpaSpeechService)
        }
    }

    private func observeSpeechService(_ service: SpeechService) {
        service.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        service.$currentPosition
            .sink { [weak self] position in
                guard let self else { return }
                if self.selectedEngine == .avSpeech {
                    self.lastKnownPosition = position
                }
            }
            .store(in: &cancellables)
    }

    private func observeSherpaService(_ service: SherpaSpeechService) {
        service.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        service.$currentPosition
            .sink { [weak self] position in
                guard let self else { return }
                if self.selectedEngine == .sherpaOnnx {
                    self.lastKnownPosition = position
                }
            }
            .store(in: &cancellables)

        service.$lastErrorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.lastErrorMessage = message
            }
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

    var isFinished: Bool {
        switch self {
        case .avSpeech(let service):
            return service.isFinished
        case .sherpa(let service):
            return service.isFinished
        }
    }

    var isPreparing: Bool {
        switch self {
        case .avSpeech:
            return false
        case .sherpa(let service):
            return service.isPreparing
        }
    }

    var generationPhase: String? {
        switch self {
        case .avSpeech:
            return nil
        case .sherpa(let service):
            return service.generationPhase
        }
    }

    var progress: Double {
        switch self {
        case .avSpeech(let service):
            return service.progress
        case .sherpa(let service):
            return service.progress
        }
    }

    var currentWord: String {
        switch self {
        case .avSpeech(let service):
            return service.currentWord
        case .sherpa:
            return ""
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
