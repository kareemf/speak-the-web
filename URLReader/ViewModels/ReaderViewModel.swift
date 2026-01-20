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
    @Published var selectedRateIndex: Int = 2 // Default to 1x

    // MARK: - Services

    let speechService = SpeechService()
    private let contentExtractor = ContentExtractor()

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
        let percentage = Int(speechService.progress * 100)
        return "\(percentage)% • \(article.wordCount) words"
    }

    var estimatedTimeRemaining: String {
        guard let article = article else { return "" }
        let remainingProgress = 1.0 - speechService.progress
        let totalSeconds = Double(article.wordCount) / (200.0 / 60.0) / Double(currentRateMultiplier)
        let remainingSeconds = Int(totalSeconds * remainingProgress)
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d remaining", minutes, seconds)
    }

    // MARK: - Initialization

    init() {
        // Observe rate changes
        $selectedRateIndex
            .dropFirst()
            .sink { [weak self] index in
                guard let self = self else { return }
                self.speechService.setRate(multiplier: self.currentRateMultiplier)
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
        article = nil

        do {
            let extractedArticle = try await contentExtractor.extract(from: urlInput)
            article = extractedArticle
            speechService.loadContent(extractedArticle.content)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    /// Clears the current content and resets the state
    func clearContent() {
        speechService.stop()
        article = nil
        urlInput = ""
        errorMessage = nil
        showError = false
    }

    /// Navigates to a specific section
    func navigateToSection(_ section: ArticleSection) {
        speechService.seekToSection(section)
        showTableOfContents = false
    }

    /// Loads a sample URL for testing
    func loadSampleURL() {
        urlInput = "https://en.wikipedia.org/wiki/Text-to-speech"
    }
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
