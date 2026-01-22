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
            speechService.stop()
            sherpaSpeechService.stop()
            applyCurrentRateToEngines()
        }
    }
    @Published var selectedRateIndex: Int = 2 { // Default to 1x
        didSet {
            UserDefaults.standard.set(selectedRateIndex, forKey: "selectedRateIndex")
            sherpaSpeechService.setRate(multiplier: currentRateMultiplier)
        }
    }
    @Published var recentArticles: [RecentArticle] = []

    private static let rateIndexKey = "selectedRateIndex"
    private static let engineKey = "selectedSpeechEngine"

    // MARK: - Services

    let speechService = SpeechService()
    let sherpaSpeechService = SherpaSpeechService()
    private let contentExtractor = ContentExtractor()
    private let recentArticlesManager = RecentArticlesManager()
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

        // Observe rate changes
        $selectedRateIndex
            .dropFirst()
            .sink { [weak self] index in
                guard let self = self else { return }
                self.speechService.setRate(multiplier: self.currentRateMultiplier)
            }
            .store(in: &cancellables)

        // Relay speech service updates so SwiftUI refreshes when playback/voice changes.
        speechService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        sherpaSpeechService.objectWillChange
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
        speechService.stop()
        sherpaSpeechService.stop()
        article = nil

        do {
            let extractedArticle = try await contentExtractor.extract(from: urlInput)
            article = extractedArticle
            speechService.loadContent(extractedArticle.content)
            sherpaSpeechService.loadContent(extractedArticle.content)
            sherpaSpeechService.setArticleURL(extractedArticle.url.absoluteString)
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
        speechService.stop()
        sherpaSpeechService.stop()
        sherpaSpeechService.setArticleURL(nil)
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
            speechService.loadContent(cachedArticle.content)
            sherpaSpeechService.loadContent(cachedArticle.content)
            sherpaSpeechService.setArticleURL(cached.url)
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

    func clearSherpaCachedAudio() {
        sherpaSpeechService.clearCachedAudio()
    }

    func sherpaCachedAudioSizeBytes() -> Int {
        sherpaSpeechService.cachedAudioSizeBytes()
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

    func recentCachedAudioLabel(for recent: RecentArticle) -> String? {
        guard let cachedInfo = sherpaSpeechService.cachedAudioInfo(forArticleURL: recent.url) else {
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
        guard canUseSelectedEngine() else { return }
        if selectedSpeechEngine == .sherpaOnnx {
            sherpaSpeechService.togglePlayPause()
        } else {
            speechService.togglePlayPause()
        }
    }

    func skipForward() {
        guard canUseSelectedEngine() else { return }
        if selectedSpeechEngine == .sherpaOnnx {
            sherpaSpeechService.skipForward()
        } else {
            speechService.skipForward()
        }
    }

    func skipBackward() {
        guard canUseSelectedEngine() else { return }
        if selectedSpeechEngine == .sherpaOnnx {
            sherpaSpeechService.skipBackward()
        } else {
            speechService.skipBackward()
        }
    }

    func seekTo(position: Int) {
        guard canUseSelectedEngine() else { return }
        if selectedSpeechEngine == .sherpaOnnx {
            sherpaSpeechService.seekTo(position: position)
        } else {
            speechService.seekTo(position: position)
        }
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
        speechService.setRate(multiplier: currentRateMultiplier)
        sherpaSpeechService.setRate(multiplier: currentRateMultiplier)
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
