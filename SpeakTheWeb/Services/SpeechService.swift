import AVFoundation
import Combine
import Foundation

/// Service for text-to-speech functionality
class SpeechService: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var isPlaying: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentPosition: Int = 0 // Character position
    @Published var progress: Double = 0.0
    @Published var currentWord: String = ""
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedVoice: AVSpeechSynthesisVoice?

    /// Returns true when playback has finished (at 100%)
    var isFinished: Bool {
        progress >= 1.0 && !isPlaying && !isPaused
    }

    // MARK: - Properties

    private var synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var textToSpeak: String = ""
    private var textLength: Int = 0
    private let userDefaults = UserDefaults.standard

    // MARK: - Persistence Keys

    private static let selectedVoiceKey = "selectedVoiceIdentifier"

    /// Speech rate (0.0 to 1.0, default 0.5)
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate {
        didSet {
            // If currently playing, restart with new rate
            if isPlaying && !isPaused {
                let currentPos = currentPosition
                stop()
                speak(from: currentPos)
            }
        }
    }

    /// Available rate presets
    static let ratePresets: [(name: String, value: Float)] = [
        ("0.5x", AVSpeechUtteranceDefaultSpeechRate * 0.5),
        ("0.75x", AVSpeechUtteranceDefaultSpeechRate * 0.75),
        ("1x", AVSpeechUtteranceDefaultSpeechRate),
        ("1.25x", AVSpeechUtteranceDefaultSpeechRate * 1.25),
        ("1.5x", AVSpeechUtteranceDefaultSpeechRate * 1.5),
        ("1.75x", AVSpeechUtteranceDefaultSpeechRate * 1.75),
        ("2x", AVSpeechUtteranceDefaultSpeechRate * 2.0),
    ]

    // MARK: - Initialization

    override init() {
        super.init()
        synthesizer.delegate = self
        loadAvailableVoices()
    }

    // MARK: - Public Methods

    /// Loads the text content to be spoken
    func loadContent(_ text: String) {
        stop()
        textToSpeak = text
        textLength = text.count
        currentPosition = 0
        progress = 0.0
    }

    /// Starts or resumes playback
    func play() {
        if isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
            isPlaying = true
        } else if !isPlaying {
            // If finished (at 100%), restart from beginning
            if isFinished {
                currentPosition = 0
                progress = 0.0
            }
            speak(from: currentPosition)
        }
    }

    /// Prepares the synthesizer after an audio session activation.
    func prepareForPlayback() {
        guard !isPlaying, !isPaused else { return }
        guard !synthesizer.isSpeaking else { return }
        resetSynthesizer()
    }

    /// Pauses playback
    func pause() {
        if isPlaying, !isPaused {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
            isPlaying = false
        }
    }

    /// Toggles between play and pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Stops playback completely
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false
        currentPosition = 0
        progress = 0.0
        currentWord = ""
        utterance = nil
    }

    /// Skips forward by the specified number of characters
    func skipForward(characters: Int = 500) {
        let newPosition = min(currentPosition + characters, textLength)
        seekTo(position: newPosition)
    }

    /// Skips backward by the specified number of characters
    func skipBackward(characters: Int = 500) {
        let newPosition = max(currentPosition - characters, 0)
        seekTo(position: newPosition)
    }

    /// Seeks to a specific character position
    func seekTo(position: Int) {
        let wasPlaying = isPlaying
        stop()
        currentPosition = max(0, min(position, textLength))
        updateProgress()
        if wasPlaying {
            speak(from: currentPosition)
        }
    }

    /// Sets the position without starting playback
    func setPosition(_ position: Int) {
        currentPosition = max(0, min(position, textLength))
        updateProgress()
        currentWord = ""
    }

    /// Seeks to a specific section
    func seekToSection(_ section: ArticleSection) {
        seekTo(position: section.startIndex)
    }

    /// Sets the speech rate using a multiplier (e.g., 1.0 = normal, 1.5 = 50% faster)
    func setRate(multiplier: Float) {
        rate = AVSpeechUtteranceDefaultSpeechRate * multiplier
    }

    /// Sets the voice to use for speech
    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoice = voice
        // Persist the selection
        userDefaults.set(voice.identifier, forKey: Self.selectedVoiceKey)

        if isPlaying || isPaused {
            let currentPos = currentPosition
            stop()
            speak(from: currentPos)
        }
    }

    // MARK: - Private Methods

    private func speak(from position: Int) {
        guard position < textLength else {
            stop()
            return
        }

        let startIndex = textToSpeak.index(textToSpeak.startIndex, offsetBy: position)
        let textToRead = String(textToSpeak[startIndex...])

        let newUtterance = AVSpeechUtterance(string: textToRead)
        newUtterance.rate = rate
        newUtterance.pitchMultiplier = 1.0
        newUtterance.volume = 1.0

        if let voice = selectedVoice {
            newUtterance.voice = voice
        } else if let defaultVoice = AVSpeechSynthesisVoice(language: "en-US") {
            newUtterance.voice = defaultVoice
        }

        utterance = newUtterance
        currentPosition = position
        isPlaying = true
        isPaused = false

        synthesizer.speak(newUtterance)
    }

    private func updateProgress() {
        if textLength > 0 {
            progress = Double(currentPosition) / Double(textLength)
        } else {
            progress = 0.0
        }
    }

    private func resetSynthesizer() {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.delegate = nil
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
    }

    private func loadAvailableVoices() {
        // Get all available voices, prioritizing English voices
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        // Sort voices: English first, then by quality, then alphabetically
        availableVoices = allVoices.sorted { v1, v2 in
            let isEnglish1 = v1.language.hasPrefix("en")
            let isEnglish2 = v2.language.hasPrefix("en")

            if isEnglish1 != isEnglish2 {
                return isEnglish1
            }

            // Higher quality first
            if v1.quality != v2.quality {
                return v1.quality.rawValue > v2.quality.rawValue
            }

            return v1.name < v2.name
        }

        // Check for previously selected voice
        if let savedIdentifier = userDefaults.string(forKey: Self.selectedVoiceKey),
           let savedVoice = availableVoices.first(where: { $0.identifier == savedIdentifier })
        {
            selectedVoice = savedVoice
            return
        }

        // Default voice - prefer Samantha (en-US)
        selectedVoice = availableVoices.first { $0.name == "Samantha" && $0.language == "en-US" }
            ?? availableVoices.first { $0.name == "Samantha" }
            ?? availableVoices.first { $0.language == "en-US" && $0.quality == .enhanced }
            ?? availableVoices.first { $0.language == "en-US" }
            ?? availableVoices.first { $0.language.hasPrefix("en") }
            ?? availableVoices.first
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard utterance === self.utterance else { return }
        DispatchQueue.main.async {
            self.isPlaying = true
            self.isPaused = false
        }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === self.utterance else { return }
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = false
            self.currentPosition = self.textLength
            self.progress = 1.0
        }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        guard utterance === self.utterance else { return }
        DispatchQueue.main.async {
            self.isPaused = true
            self.isPlaying = false
        }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        guard utterance === self.utterance else { return }
        DispatchQueue.main.async {
            self.isPaused = false
            self.isPlaying = true
        }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard utterance === self.utterance else { return }
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = false
        }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard utterance === self.utterance else { return }
        DispatchQueue.main.async {
            // Update current position based on the range being spoken
            let utteranceText = utterance.speechString
            let basePosition = self.textLength - utteranceText.count
            self.currentPosition = basePosition + characterRange.location
            self.updateProgress()

            // Extract current word
            if let range = Range(characterRange, in: utteranceText) {
                self.currentWord = String(utteranceText[range])
            }
        }
    }
}
