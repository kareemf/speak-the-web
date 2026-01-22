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
            guard !isInitializing else { return }
            playbackController.selectEngine(selectedSpeechEngine)
            bindPositionUpdates(for: selectedSpeechEngine)
            applyCurrentRateToEngines()
        }
    }
    @Published var selectedRateIndex: Int = 2 { // Default to 1x
        didSet {
            UserDefaults.standard.set(selectedRateIndex, forKey: Self.rateIndexKey)
            guard !isInitializing else { return }
            playbackController.setRate(multiplier: currentRateMultiplier)
        }
    }
    @Published var recentArticles: [RecentArticle] = []

    private static let rateIndexKey = "selectedRateIndex"
    private static let engineKey = "selectedSpeechEngine"

    // MARK: - Services

    private let playbackController = MediaPlaybackController()
    private let contentExtractor = ContentExtractor()
    private let recentArticlesManager = RecentArticlesManager()
    let sherpaModelStore = SherpaOnnxModelStore()

    // MARK: - Computed Properties

    var speechService: SpeechService {
        playbackController.avSpeechService()
    }

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
        playbackController.progress(for: selectedSpeechEngine)
    }

    var playbackIsPlaying: Bool {
        playbackController.isPlaying(for: selectedSpeechEngine)
    }

    var playbackIsFinished: Bool {
        playbackController.isFinished(for: selectedSpeechEngine)
    }

    var isGeneratingAudio: Bool {
        selectedSpeechEngine == .sherpaOnnx && playbackController.isPreparing(for: .sherpaOnnx)
    }

    var sherpaGenerationPhase: String? {
        selectedSpeechEngine == .sherpaOnnx
            ? playbackController.generationPhase(for: .sherpaOnnx)
            : nil
    }

    var playbackCurrentWord: String {
        selectedSpeechEngine == .sherpaOnnx ? "" : playbackController.currentWord(for: .avSpeech)
    }

    var shouldShowCurrentWord: Bool {
        selectedSpeechEngine == .avSpeech && playbackController.isPlaying(for: .avSpeech)
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

        playbackController.canUseEngine = { [weak self] engine in
            guard let self else { return false }
            return self.canUseEngine(engine)
        }

        playbackController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        playbackController.$lastErrorMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.presentError(message)
            }
            .store(in: &cancellables)

        isInitializing = false
        bindPositionUpdates(for: selectedSpeechEngine)
        playbackController.selectEngine(selectedSpeechEngine)
        applyCurrentRateToEngines()

        sherpaModelStore.$selectedModelId
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.playbackController.updateSherpaModel(record: self.sherpaModelStore.selectedRecord)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
    private var positionCancellable: AnyCancellable?
    private var isInitializing = true

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
            playbackController.updateSherpaModel(record: sherpaModelStore.selectedRecord)
            updateNowPlayingMetadata(for: extractedArticle)

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
        persistCurrentPosition()
        playbackController.stopAll()
        playbackController.loadContent("")
        playbackController.setArticleURL(nil)
        playbackController.clearNowPlaying()
        article = nil
        urlInput = ""
        errorMessage = nil
        showError = false
        showArticle = false
    }

    /// Navigates to a specific section
    func navigateToSection(_ section: ArticleSection) {
        playbackController.seekToSection(section, engine: selectedSpeechEngine)
        persistCurrentPosition()
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
            playbackController.updateSherpaModel(record: sherpaModelStore.selectedRecord)
            updateNowPlayingMetadata(for: cachedArticle)
            if cached.lastPosition > 0 {
                playbackController.setPosition(cached.lastPosition)
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
        playbackController.clearSherpaCachedAudio()
    }

    func clearSherpaCachedAudio() {
        playbackController.clearSherpaCachedAudio()
    }

    func sherpaCachedAudioSizeBytes() -> Int {
        playbackController.sherpaCachedAudioSizeBytes()
    }

    /// Removes a recent article and clears its cached payload
    func removeRecentArticle(_ recent: RecentArticle) {
        recentArticles = recentArticlesManager.remove(urlString: recent.url)
        playbackController.removeSherpaCachedAudio(for: recent.url)
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

    func recentCachedAudioLabel(for recent: RecentArticle) -> String? {
        guard let cachedInfo = playbackController.sherpaCachedAudioInfo(forArticleURL: recent.url) else {
            return nil
        }
        let voiceName = cachedInfo.voiceName
            ?? sherpaModelStore.downloadedRecords[cachedInfo.modelId]?.displayName
            ?? cachedInfo.modelId
        return "Cached: \(voiceName)"
    }

    func setReaderMode(_ mode: ReaderMode) {
        readerMode = mode
    }

    func togglePlayPause() {
        print("[ReaderViewModel] togglePlayPause (engine=\(selectedSpeechEngine.rawValue))")
        guard canUseEngine(selectedSpeechEngine) else { return }
        playbackController.togglePlayPause(engine: selectedSpeechEngine)
    }

    func skipForward() {
        guard canUseEngine(selectedSpeechEngine) else { return }
        playbackController.skipForward(engine: selectedSpeechEngine)
        persistCurrentPosition()
    }

    func skipBackward() {
        guard canUseEngine(selectedSpeechEngine) else { return }
        playbackController.skipBackward(engine: selectedSpeechEngine)
        persistCurrentPosition()
    }

    func seekTo(position: Int) {
        guard canUseEngine(selectedSpeechEngine) else { return }
        playbackController.seek(engine: selectedSpeechEngine, position: position)
        persistCurrentPosition()
    }

    func activateVoicePreviewSession() {
        _ = playbackController.activateSession(for: .avSpeech, reason: "voice-preview")
    }

    private func canUseEngine(_ engine: SpeechEngineType) -> Bool {
        guard engine == .sherpaOnnx else { return true }
        print("[ReaderViewModel] canUseEngine check (Sherpa)")

        guard SherpaOnnxRuntime.isAvailable else {
            presentError("Sherpa-onnx is not linked in this build yet.")
            return false
        }

        if let issue = sherpaModelStore.validateSelectedModelForPlayback() {
            presentError(issue)
            return false
        }

        print("[ReaderViewModel] canUseEngine passed")
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

    private func persistCurrentPosition() {
        guard let article else { return }
        let position = playbackController.currentPosition(for: selectedSpeechEngine)
        recentArticles = recentArticlesManager.updateProgress(
            urlString: article.url.absoluteString,
            position: position,
            contentLength: article.content.count,
            wordCount: article.wordCount
        )
    }

    private func bindPositionUpdates(for engine: SpeechEngineType) {
        positionCancellable?.cancel()
        positionCancellable = playbackController.positionPublisher(for: engine)
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
    }

    private func updateNowPlayingMetadata(for article: Article?) {
        guard let article else {
            playbackController.clearNowPlaying()
            return
        }
        playbackController.updateNowPlayingMetadata(
            title: article.title,
            artist: article.url.host,
            wordCount: article.wordCount
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
