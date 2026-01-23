import Foundation
import AVFoundation
import SherpaOnnx

final class SherpaSpeechService: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentPosition: Int = 0
    @Published var progress: Double = 0.0
    @Published var isPreparing: Bool = false
    @Published var generationPhase: String?
    @Published var lastErrorMessage: String?

    var isFinished: Bool {
        progress >= 1.0 && !isPlaying && !isPaused
    }

    var duration: TimeInterval? {
        guard audioSampleRate > 0, totalFrames > 0 else { return nil }
        return Double(totalFrames) / audioSampleRate
    }

    var currentTime: TimeInterval? {
        guard audioSampleRate > 0, totalFrames > 0 else { return nil }
        if isPaused || !isPlaying {
            let frame = pausedFrame ?? startFrame
            return Double(frame) / audioSampleRate
        }
        return Double(currentFrame()) / audioSampleRate
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let instanceID = UUID()
    private let generationLock = NSLock()
    private var scheduleToken = UUID()
    private var generationInFlight = false
    private let audioCache = SherpaAudioCache(maxEntries: 10, maxBytes: 200 * 1024 * 1024)
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private var totalFrames: AVAudioFramePosition = 0
    private var audioSampleRate: Double = 0
    private var startFrame: AVAudioFramePosition = 0
    private var pausedFrame: AVAudioFramePosition?
    private var progressTimer: Timer?
    private let workQueue = DispatchQueue(label: "SherpaSpeechService")
    private let fileManager = FileManager.default

    private var text: String = ""
    private var textLength: Int = 0
    private var modelRecord: SherpaModelRecord?
    private var shouldAutoPlayAfterPrepare = false
    private var speed: Float = 1.0
    private var currentGenerationID: UUID?
    private var generationTimeoutWorkItem: DispatchWorkItem?
    private var audioIsCached = false
    private var currentArticleURL: String?

    init() {
        print("[Sherpa] Init service \(instanceID.uuidString)")
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.connect(playerNode, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
        timePitch.rate = speed
    }

    func updateModel(record: SherpaModelRecord?) {
        if record?.id != modelRecord?.id {
            stop()
            clearAudio()
        }
        modelRecord = record
    }

    func loadContent(_ text: String) {
        stop()
        self.text = text
        self.textLength = text.count
        currentPosition = 0
        progress = 0.0
        clearAudio()
    }

    func setArticleURL(_ url: String?) {
        currentArticleURL = url
    }

    func removeCachedAudio(for urlString: String) {
        audioCache.removeEntries(forArticleURL: urlString)
    }

    func clearCachedAudio() {
        audioCache.clear()
    }

    func cachedAudioSizeBytes() -> Int {
        audioCache.totalBytes()
    }

    func cachedAudioInfo(forArticleURL urlString: String) -> SherpaAudioCache.CachedAudioInfo? {
        audioCache.cachedInfo(forArticleURL: urlString)
    }

    func togglePlayPause() {
        print("[Sherpa] togglePlayPause (isPreparing=\(isPreparing), isPlaying=\(isPlaying), isPaused=\(isPaused))")
        if isPreparing {
            return
        }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        print("[Sherpa] play (isPreparing=\(isPreparing), isPlaying=\(isPlaying), isPaused=\(isPaused), hasAudio=\(audioFile != nil))")
        ensureEngineRunning()
        guard !isPreparing else { return }
        if isFinished {
            setPosition(0)
        }
        if isPaused {
            playerNode.play()
            isPaused = false
            isPlaying = true
            pausedFrame = nil
            startProgressTimer()
            return
        }

        guard !isPlaying else { return }

        if audioFile == nil {
            shouldAutoPlayAfterPrepare = true
            prepareAudio()
            return
        }

        startPlayback()
    }

    func pause() {
        guard isPlaying else { return }
        pausedFrame = currentFrame()
        playerNode.pause()
        isPlaying = false
        isPaused = true
        stopProgressTimer()
        if let pausedFrame {
            updateProgress(for: pausedFrame)
        }
    }

    func stop() {
        invalidateScheduleToken()
        playerNode.stop()
        isPlaying = false
        isPaused = false
        startFrame = 0
        pausedFrame = nil
        currentPosition = 0
        progress = 0.0
        resetGenerationState()
        stopProgressTimer()
    }

    func skipForward(characters: Int = 500) {
        seekTo(position: currentPosition + characters)
    }

    func skipBackward(characters: Int = 500) {
        seekTo(position: currentPosition - characters)
    }

    func seekTo(position: Int) {
        let clampedPosition = max(0, min(position, textLength))
        currentPosition = clampedPosition
        progress = textLength > 0 ? Double(clampedPosition) / Double(textLength) : 0

        guard audioFile != nil, totalFrames > 0 else { return }

        let targetFrame = AVAudioFramePosition(Double(totalFrames) * progress)
        startFrame = max(0, min(targetFrame, totalFrames))

        let wasPlaying = isPlaying
        playerNode.stop()
        scheduleFrom(startFrame)

        if wasPlaying {
            playerNode.play()
            pausedFrame = nil
        } else {
            pausedFrame = startFrame
        }
    }

    func setPosition(_ position: Int) {
        let clampedPosition = max(0, min(position, textLength))
        currentPosition = clampedPosition
        progress = textLength > 0 ? Double(clampedPosition) / Double(textLength) : 0

        guard totalFrames > 0 else { return }
        let targetFrame = AVAudioFramePosition(Double(totalFrames) * progress)
        startFrame = max(0, min(targetFrame, totalFrames))
        pausedFrame = startFrame
    }

    func setRate(multiplier: Float) {
        guard multiplier != speed else { return }
        speed = multiplier
        timePitch.rate = multiplier
    }

    private func prepareAudio() {
        guard !isPreparing else {
            print("[Sherpa] prepareAudio ignored: already preparing")
            return
        }
        guard currentGenerationID == nil else {
            print("[Sherpa] prepareAudio ignored: generation in progress")
            return
        }
        guard let record = modelRecord else {
            lastErrorMessage = "Select a Sherpa model before playback."
            return
        }
        guard let tokensPath = record.tokensPath else {
            lastErrorMessage = "Selected model is missing tokens.txt."
            return
        }
        guard !text.isEmpty else { return }
        guard beginGeneration() else {
            print("[Sherpa] prepareAudio ignored: in-flight gate")
            return
        }

        isPreparing = true
        generationPhase = "Starting"
        let startTime = Date()
        let generationSpeed: Float = 1.0
        let articleURL = currentArticleURL
        let generationID = UUID()
        let textSnapshot = text
        let textCount = textLength
        currentGenerationID = generationID
        print("[Sherpa] Generation ID \(generationID.uuidString)")
        startGenerationWatchdog(for: generationID, timeout: generationTimeout(for: textCount))
        print("[Sherpa] Starting generation for \(textCount) chars")

        workQueue.async { [weak self] in
            guard let self else { return }
            let cacheKey = self.audioCache.cacheKey(
                text: textSnapshot,
                modelId: record.id,
                generationSpeed: generationSpeed
            )
            do {
                self.logPhase("Checking cache", uiMessage: "Checking cache…", generationID: generationID)
                if let cachedURL = self.audioCache.cachedFileURL(for: cacheKey) {
                    do {
                        let cachedFile = try AVAudioFile(forReading: cachedURL)
                        DispatchQueue.main.async {
                            guard self.currentGenerationID == generationID else { return }
                            self.cancelGenerationWatchdog()
                            let pendingPosition = self.currentPosition
                            self.audioFile = cachedFile
                            self.audioFileURL = cachedURL
                            self.totalFrames = cachedFile.length
                            self.audioSampleRate = cachedFile.processingFormat.sampleRate
                            self.setPosition(pendingPosition)
                            self.audioIsCached = true
                            self.isPreparing = false
                            self.generationPhase = nil
                            self.currentGenerationID = nil
                            self.endGeneration(reason: "cache-hit")
                            print("[Sherpa] Loaded cached audio")

                            if self.shouldAutoPlayAfterPrepare {
                                self.shouldAutoPlayAfterPrepare = false
                                self.startPlayback()
                            }
                        }
                        return
                    } catch {
                        self.audioCache.removeEntry(forKey: cacheKey)
                    }
                }

                self.logPhase("Initializing model config", uiMessage: "Initializing model…", generationID: generationID)
                print("[Sherpa] Checking model files")
                guard fileManager.fileExists(atPath: record.modelPath) else {
                    print("[Sherpa] Missing model file at \(record.modelPath)")
                    throw SherpaSpeechError.missingModelFile("model")
                }
                guard fileManager.fileExists(atPath: tokensPath) else {
                    print("[Sherpa] Missing tokens file at \(tokensPath)")
                    throw SherpaSpeechError.missingModelFile("tokens")
                }

                print("[Sherpa] Resolving data dir")
                let dataDir = self.dataDirPath(for: record)
                let vitsConfig = sherpaOnnxOfflineTtsVitsModelConfig(
                    model: record.modelPath,
                    tokens: tokensPath,
                    dataDir: dataDir
                )
                let modelConfig = sherpaOnnxOfflineTtsModelConfig(
                    vits: vitsConfig,
                    numThreads: 2,
                    provider: "cpu"
                )
                var config = sherpaOnnxOfflineTtsConfig(model: modelConfig)

                self.logPhase("Creating TTS instance", uiMessage: "Loading model…", generationID: generationID)
                guard let tts = SherpaOnnxOfflineTtsWrapper(config: &config) else {
                    throw SherpaSpeechError.invalidModelConfig
                }
                self.logPhase("Generating audio", uiMessage: "Generating audio…", generationID: generationID)
                let generateStart = Date()
                let audio = tts.generate(text: textSnapshot, speed: generationSpeed)
                let generateDuration = Date().timeIntervalSince(generateStart)
                print("[Sherpa] Generated audio in \(String(format: "%.2f", generateDuration))s")
                let samples = audio.samples

                if samples.isEmpty {
                    throw SherpaSpeechError.emptyAudio
                }

                self.logPhase("Writing audio", uiMessage: "Writing audio…", generationID: generationID)
                let writeStart = Date()
                let shouldCache = !(articleURL ?? "").isEmpty
                let destinationURL = shouldCache ? self.audioCache.destinationURL(for: cacheKey) : nil
                let prepared = try self.writeAudio(
                    samples: samples,
                    sampleRate: Double(audio.sampleRate),
                    destinationURL: destinationURL
                )
                let writeDuration = Date().timeIntervalSince(writeStart)
                print("[Sherpa] Wrote audio in \(String(format: "%.2f", writeDuration))s")
                if shouldCache {
                    self.audioCache.store(
                        fileURL: prepared.url,
                        key: cacheKey,
                        articleURL: articleURL ?? "",
                        modelId: record.id,
                        voiceName: record.displayName,
                        generationSpeed: generationSpeed
                    )
                }

                DispatchQueue.main.async {
                    guard self.currentGenerationID == generationID else { return }
                    self.cancelGenerationWatchdog()
                    let pendingPosition = self.currentPosition
                    self.audioFile = prepared.file
                    self.audioFileURL = prepared.url
                    self.totalFrames = prepared.file.length
                    self.audioSampleRate = Double(audio.sampleRate)
                    self.setPosition(pendingPosition)
                    self.isPreparing = false
                    self.generationPhase = nil
                    self.currentGenerationID = nil
                    self.audioIsCached = shouldCache
                    self.endGeneration(reason: "prepare-complete")

                    let totalDuration = Date().timeIntervalSince(startTime)
                    print("[Sherpa] Preparation finished in \(String(format: "%.2f", totalDuration))s")

                    if self.shouldAutoPlayAfterPrepare {
                        self.shouldAutoPlayAfterPrepare = false
                        self.startPlayback()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.currentGenerationID == generationID else { return }
                    self.cancelGenerationWatchdog()
                    self.isPreparing = false
                    self.generationPhase = nil
                    self.currentGenerationID = nil
                    self.endGeneration(reason: "prepare-error")
                    print("[Sherpa] Generation error: \(error.localizedDescription)")
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startPlayback() {
        guard audioFile != nil else { return }
        scheduleFrom(startFrame)
        playerNode.play()
        isPlaying = true
        isPaused = false
        pausedFrame = nil
        startProgressTimer()
    }

    private func scheduleFrom(_ frame: AVAudioFramePosition) {
        guard let audioFile else { return }
        let clampedFrame = max(0, min(frame, audioFile.length))
        if clampedFrame != frame {
            startFrame = clampedFrame
        }
        let token = invalidateScheduleToken()
        playerNode.stop()
        let remainingFrames = audioFile.length - clampedFrame
        guard remainingFrames > 0 else {
            print("[Sherpa] scheduleFrom ignored: no remaining frames")
            finishPlayback()
            return
        }
        let frameCount = AVAudioFrameCount(remainingFrames)
        print("[Sherpa] Scheduling playback from frame \(clampedFrame)")
        playerNode.scheduleSegment(audioFile, startingFrame: clampedFrame, frameCount: frameCount, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.scheduleToken == token else { return }
                self.finishPlayback()
            }
        }
    }

    private func finishPlayback() {
        stopProgressTimer()
        isPlaying = false
        isPaused = false
        startFrame = totalFrames
        pausedFrame = nil
        currentPosition = textLength
        progress = 1.0
    }

    private func currentFrame() -> AVAudioFramePosition {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return startFrame
        }
        return startFrame + AVAudioFramePosition(playerTime.sampleTime)
    }

    private func updateProgress(for frame: AVAudioFramePosition) {
        guard totalFrames > 0 else {
            progress = 0.0
            currentPosition = 0
            return
        }
        let clampedFrame = max(0, min(frame, totalFrames))
        progress = Double(clampedFrame) / Double(totalFrames)
        currentPosition = Int(Double(textLength) * progress)
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateProgress(for: self.currentFrame())
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func clearAudio() {
        if let url = audioFileURL, !audioIsCached {
            try? FileManager.default.removeItem(at: url)
        }
        audioFile = nil
        audioFileURL = nil
        totalFrames = 0
        audioSampleRate = 0
        startFrame = 0
        pausedFrame = nil
        audioIsCached = false
    }

    private func generationTimeout(for textCount: Int) -> TimeInterval {
        let estimated = Double(textCount) * 0.03
        return max(30.0, min(300.0, estimated))
    }

    private func startGenerationWatchdog(for generationID: UUID, timeout: TimeInterval) {
        generationTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.currentGenerationID == generationID else { return }
            print("[Sherpa] Generation timed out")
            self.isPreparing = false
            self.generationPhase = nil
            self.shouldAutoPlayAfterPrepare = false
            self.currentGenerationID = nil
            self.endGeneration(reason: "prepare-timeout")
            self.lastErrorMessage = "Sherpa-onnx generation timed out. Try again with a shorter selection."
        }
        generationTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func cancelGenerationWatchdog() {
        generationTimeoutWorkItem?.cancel()
        generationTimeoutWorkItem = nil
    }

    private func resetGenerationState() {
        endGeneration(reason: "reset")
        currentGenerationID = nil
        generationPhase = nil
        isPreparing = false
        cancelGenerationWatchdog()
    }

    private func logPhase(_ message: String, uiMessage: String, generationID: UUID) {
        print("[Sherpa] \(message)")
        DispatchQueue.main.async {
            guard self.currentGenerationID == generationID else { return }
            self.generationPhase = uiMessage
        }
    }

    @discardableResult
    private func invalidateScheduleToken() -> UUID {
        let token = UUID()
        scheduleToken = token
        return token
    }

    private func beginGeneration() -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        if generationInFlight {
            return false
        }
        generationInFlight = true
        return true
    }

    private func endGeneration(reason: String) {
        generationLock.lock()
        generationInFlight = false
        generationLock.unlock()
        print("[Sherpa] Generation cleared (\(reason))")
    }

    private func writeAudio(samples: [Float], sampleRate: Double, destinationURL: URL? = nil) throws -> (file: AVAudioFile, url: URL) {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData?.pointee {
            samples.withUnsafeBufferPointer { bufferPointer in
                channelData.update(from: bufferPointer.baseAddress!, count: samples.count)
            }
        }

        let fileURL: URL
        if let destinationURL {
            fileURL = destinationURL
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
        } else {
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            fileURL = cacheDir.appendingPathComponent("sherpa-tts-\(UUID().uuidString).caf")
        }
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        try file.write(from: buffer)

        let readFile = try AVAudioFile(forReading: fileURL)
        return (file: readFile, url: fileURL)
    }

    private func ensureEngineRunning() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            print("[Sherpa] Audio engine restarted")
        } catch {
            print("[Sherpa] Failed to restart audio engine: \(error)")
            lastErrorMessage = "Audio engine failed to start. Try again."
        }
    }

    private func dataDirPath(for record: SherpaModelRecord) -> String {
        let root = URL(fileURLWithPath: record.localDirectory, isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return ""
        }
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "phontab" {
            return fileURL.deletingLastPathComponent().path
        }
        return ""
    }
}

private enum SherpaSpeechError: LocalizedError {
    case emptyAudio
    case missingModelFile(String)
    case invalidModelConfig

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "Sherpa-onnx returned empty audio."
        case .missingModelFile(let name):
            return "Sherpa-onnx model is missing \(name) file. Re-download the model in Settings."
        case .invalidModelConfig:
            return "Sherpa-onnx failed to initialize with the selected model."
        }
    }
}
