import Foundation
import SwiftUI
import Combine

/// Main view model for the URL Reader app
@MainActor
class ReaderViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var urlInput: String = ""
    @Published var article: Article?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var showTableOfContents: Bool = false
    @Published var showVoiceSettings: Bool = false
    @Published var showArticle: Bool = false
    @Published var readerMode: ReaderMode = .text
    @Published var selectedSpeechEngine: SpeechEngineType = .avSpeech {
        didSet {
            UserDefaults.standard.set(selectedSpeechEngine.rawValue, forKey: Self.engineKey)
            playbackController.stopAll()
            applyCurrentRateToEngines()
        }
    }
    @Published var selectedRateIndex: Int = 2 { // Default to 1x
        didSet {
            UserDefaults.standard.set(selectedRateIndex, forKey: "selectedRateIndex")
            playbackController.setRate(multiplier: currentRateMultiplier)
        }
    }
    @Published var recentArticles: [RecentArticle] = []

    private static let rateIndexKey = "selectedRateIndex"
    private static let engineKey = "selectedSpeechEngine"

    // MARK: - Services

    private let playbackController = MediaPlaybackController()
    var speechService: SpeechService { playbackController.speechService }
    var sherpaSpeechService: SherpaSpeechService { playbackController.sherpaSpeechService }
    private let contentExtractor = ContentExtractor()
    private let recentArticlesManager = RecentArticlesManager()
    private let nowPlayingManager = NowPlayingManager()
    let sherpaModelStore = SherpaOnnxModelStore()

    // MARK: - Computed Properties

    var hasContent: Bool {
        article != nil
    }

    var canFetch: Bool {
        !urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var currentRateMultiplier: Float {
        let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        guard selectedRateIndex >= 0 && selectedRateIndex < rates.count else { return 1.0 }
        return rates[selectedRateIndex]
    }

    var currentRateName: String {
        SpeechService.ratePresets[safe: selectedRateIndex]?.name ?? "1x"
    }

    var progressText: String {
        guard let article = article else { return "" }
        let percentage = Int(playbackProgress * 100)
        return "\(percentage)% • \(article.wordCount) words"
    }

    var estimatedTimeRemaining: String {
        guard let article = article else { return "" }
        let remainingProgress = 1.0 - playbackProgress
        let totalSeconds = Double(article.wordCount) / (200.0 / 60.0) / Double(currentRateMultiplier)
        let remainingSeconds = Int(totalSeconds * remainingProgress)
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d remaining", minutes, seconds)
    }

    var playbackProgress: Double {
        selectedSpeechEngine == .sherpaOnnx ? sherpaSpeechService.progress : speechService.progress
    }

    var playbackIsPlaying: Bool {
        selectedSpeechEngine == .sherpaOnnx ? sherpaSpeechService.isPlaying : speechService.isPlaying
    }

    var playbackIsFinished: Bool {
        selectedSpeechEngine == .sherpaOnnx ? sherpaSpeechService.isFinished : speechService.isFinished
    }

    var isGeneratingAudio: Bool {
        selectedSpeechEngine == .sherpaOnnx && sherpaSpeechService.isPreparing
    }

    var sherpaGenerationPhase: String? {
        selectedSpeechEngine == .sherpaOnnx ? sherpaSpeechService.generationPhase : nil
    }

    var playbackCurrentWord: String {
        selectedSpeechEngine == .sherpaOnnx ? "" : speechService.currentWord
    }

    var shouldShowCurrentWord: Bool {
        selectedSpeechEngine == .avSpeech && speechService.isPlaying
    }

    // MARK: - Initialization

    init() {
        // Load recent articles
        recentArticles = recentArticlesManager.load()

        // Load persisted rate index
        let savedRateIndex = UserDefaults.standard.integer(forKey: Self.rateIndexKey)
        if savedRateIndex > 0 && savedRateIndex < SpeechService.ratePresets.count {
            selectedRateIndex = savedRateIndex
        }

        // Load persisted engine
        if let savedEngine = UserDefaults.standard.string(forKey: Self.engineKey),
           let engine = SpeechEngineType(rawValue: savedEngine) {
            selectedSpeechEngine = engine
        }

        // Apply the rate immediately
        applyCurrentRateToEngines()

        playbackController.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        speechService.$currentPosition
            .removeDuplicates()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] position in
                guard let self = self, let article = self.article else { return }
                self.recentArticles = self.recentArticlesManager.updateProgress(
                    urlString: article.url.absoluteString,
                    position: position,
                    contentLength: article.content.count,
                    wordCount: article.wordCount
                )
            }
            .store(in: &cancellables)

        sherpaSpeechService.$currentPosition
            .removeDuplicates()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] position in
                guard let self = self, let article = self.article else { return }
                self.recentArticles = self.recentArticlesManager.updateProgress(
                    urlString: article.url.absoluteString,
                    position: position,
                    contentLength: article.content.count,
                    wordCount: article.wordCount
                )
            }
            .store(in: &cancellables)

        sherpaModelStore.$selectedModelId
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sherpaSpeechService.updateModel(record: self.sherpaModelStore.selectedRecord)
            }
            .store(in: &cancellables)

        sherpaSpeechService.$lastErrorMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.presentError(message)
            }
            .store(in: &cancellables)

        let nowPlayingPublishers: [AnyPublisher<Void, Never>] = [
            $article.map { _ in () }.eraseToAnyPublisher(),
            $selectedSpeechEngine.map { _ in () }.eraseToAnyPublisher(),
            speechService.$currentPosition.map { _ in () }.eraseToAnyPublisher(),
            sherpaSpeechService.$currentPosition.map { _ in () }.eraseToAnyPublisher(),
            speechService.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            sherpaSpeechService.$isPlaying.map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(nowPlayingPublishers)
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)

        configureNowPlayingCommands()

    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Public Methods

    /// Fetches and loads content from the entered URL
    func fetchContent() async {
        guard canFetch else { return }

        isLoading = true
        errorMessage = nil
        showError = false

        // Stop any current playback
        playbackController.stopAll()
        article = nil

        do {
            let extractedArticle = try await contentExtractor.extract(from: urlInput)
            article = extractedArticle
            playbackController.loadContent(extractedArticle.content)
            playbackController.setArticleURL(extractedArticle.url.absoluteString)
            sherpaSpeechService.updateModel(record: sherpaModelStore.selectedRecord)

            // Save to recent articles
            recentArticlesManager.save(extractedArticle)
            recentArticles = recentArticlesManager.load()
            showArticle = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    /// Clears the current content and resets the state
    func clearContent() {
        playbackController.stopAll()
        playbackController.setArticleURL(nil)
        article = nil
        urlInput = ""
        errorMessage = nil
        showError = false
        showArticle = false
    }

    /// Navigates to a specific section
    func navigateToSection(_ section: ArticleSection) {
        if selectedSpeechEngine == .sherpaOnnx {
            sherpaSpeechService.seekTo(position: section.startIndex)
        } else {
            speechService.seekToSection(section)
        }
        showTableOfContents = false
    }

    /// Loads a sample URL for testing
    func loadSampleURL() {
        urlInput = "https://en.wikipedia.org/wiki/Text-to-speech"
    }

    /// Loads a URL directly (used when receiving shared URLs)
    func loadURL(_ urlString: String) {
        urlInput = urlString
        Task {
            await fetchContent()
        }
    }

    /// Loads a recent article
    func loadRecentArticle(_ recent: RecentArticle) {
        if let cached = recentArticlesManager.loadCachedArticle(for: recent.url) {
            let cachedArticle = Article(cached: cached)
            article = cachedArticle
            playbackController.loadContent(cachedArticle.content)
            playbackController.setArticleURL(cached.url)
            sherpaSpeechService.updateModel(record: sherpaModelStore.selectedRecord)
            if cached.lastPosition > 0 {
                speechService.setPosition(cached.lastPosition)
                sherpaSpeechService.setPosition(cached.lastPosition)
            }
            showArticle = true
            return
        }

        loadURL(recent.url)
    }

    /// Clears all recent articles
    func clearRecentArticles() {
        recentArticlesManager.clear()
        recentArticles = []
        sherpaSpeechService.clearCachedAudio()
    }

    /// Removes a recent article and clears its cached payload
    func removeRecentArticle(_ recent: RecentArticle) {
        recentArticles = recentArticlesManager.remove(urlString: recent.url)
        sherpaSpeechService.removeCachedAudio(for: recent.url)
    }

    func recentProgress(for recent: RecentArticle) -> Double {
        guard recent.contentLength > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(recent.lastPosition) / Double(recent.contentLength)))
    }

    func recentRemainingText(for recent: RecentArticle) -> String {
        guard recent.wordCount > 0 else { return "—" }
        let remainingProgress = 1.0 - recentProgress(for: recent)
        let totalSeconds = Double(recent.wordCount) / (200.0 / 60.0) / Double(currentRateMultiplier)
        let remainingSeconds = Int(totalSeconds * remainingProgress)
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d remaining", minutes, seconds)
    }

    func setReaderMode(_ mode: ReaderMode) {
        readerMode = mode
    }

    func togglePlayPause() {
        print("[ReaderViewModel] togglePlayPause (engine=\(selectedSpeechEngine.rawValue))")
        guard canUseSelectedEngine() else { return }
        playbackController.togglePlayPause(engine: selectedSpeechEngine)
    }

    func play() {
        guard canUseSelectedEngine() else { return }
        playbackController.play(engine: selectedSpeechEngine)
    }

    func pause() {
        playbackController.pause(engine: selectedSpeechEngine)
    }

    func skipForward() {
        guard canUseSelectedEngine() else { return }
        playbackController.skipForward(engine: selectedSpeechEngine)
    }

    func skipBackward() {
        guard canUseSelectedEngine() else { return }
        playbackController.skipBackward(engine: selectedSpeechEngine)
    }

    func seekTo(position: Int) {
        guard canUseSelectedEngine() else { return }
        playbackController.seek(engine: selectedSpeechEngine, position: position)
    }

    private func canUseSelectedEngine() -> Bool {
        guard selectedSpeechEngine == .sherpaOnnx else { return true }
        print("[ReaderViewModel] canUseSelectedEngine check (Sherpa)")

        guard SherpaOnnxRuntime.isAvailable else {
            presentError("Sherpa-onnx is not linked in this build yet.")
            return false
        }

        if let issue = sherpaModelStore.validateSelectedModelForPlayback() {
            presentError(issue)
            return false
        }

        print("[ReaderViewModel] canUseSelectedEngine passed")
        return true
    }

    private func presentError(_ message: String) {
        print("[ReaderViewModel] Error: \(message)")
        errorMessage = message
        showError = false
        Task { @MainActor in
            self.showError = true
        }
    }

    private func applyCurrentRateToEngines() {
        playbackController.setRate(multiplier: currentRateMultiplier)
    }

    private func configureNowPlayingCommands() {
        nowPlayingManager.configureCommands(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.togglePlayPause() },
            skipForward: { [weak self] in self?.skipForward() },
            skipBackward: { [weak self] in self?.skipBackward() },
            seek: { [weak self] time in self?.seekToTime(time) }
        )
    }

    private func seekToTime(_ time: TimeInterval) {
        guard let article else { return }
        let duration = effectiveDuration()
        guard duration > 0 else { return }
        let clamped = max(0, min(time, duration))
        let progress = clamped / duration
        let position = Int(Double(article.content.count) * progress)
        seekTo(position: position)
    }

    private func effectiveDuration() -> TimeInterval {
        if selectedSpeechEngine == .sherpaOnnx,
           let duration = sherpaSpeechService.duration {
            return duration
        }
        return estimatedTotalDuration()
    }

    private func estimatedTotalDuration() -> TimeInterval {
        guard let article else { return 0 }
        return Double(article.wordCount) / (200.0 / 60.0) / Double(currentRateMultiplier)
    }

    private func updateNowPlayingInfo() {
        guard let article, showArticle else {
            nowPlayingManager.updateNowPlaying(nil)
            return
        }

        let duration = effectiveDuration()
        let elapsed: TimeInterval
        if selectedSpeechEngine == .sherpaOnnx, let current = sherpaSpeechService.currentTime {
            elapsed = current
        } else {
            elapsed = duration * playbackProgress
        }

        nowPlayingManager.updateNowPlaying(
            NowPlayingManager.Info(
                title: article.title,
                artist: article.url.host,
                duration: duration,
                elapsed: elapsed,
                rate: currentRateMultiplier,
                isPlaying: playbackIsPlaying
            )
        )
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
