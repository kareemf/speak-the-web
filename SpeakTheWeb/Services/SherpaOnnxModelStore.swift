import Foundation
import SWCompression

final class SherpaOnnxModelStore: NSObject, ObservableObject {
    enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double)
        case processing
        case failed(message: String)
    }

    @Published private(set) var models: [SherpaModel] = []
    @Published private(set) var downloadedRecords: [String: SherpaModelRecord] = [:]
    @Published var selectedModelId: String? {
        didSet {
            persistRegistry()
        }
    }

    @Published var downloadStates: [String: DownloadState] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false

    private var session: URLSession
    private let fileManager = FileManager.default
    private let appGroupId = "group.com.kareemf.SpeakTheWeb"
    private let baseDirectory: URL
    private let registryURL: URL

    override init() {
        let configuration = URLSessionConfiguration.default
        session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            baseDirectory = groupURL.appendingPathComponent("VoiceModels", isDirectory: true)
        } else {
            baseDirectory = appSupport.appendingPathComponent("SpeakTheWeb/VoiceModels", isDirectory: true)
        }

        registryURL = baseDirectory.appendingPathComponent("model-registry.json")

        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        ensureBaseDirectory()
        loadRegistry()
    }

    var selectedRecord: SherpaModelRecord? {
        guard let selectedModelId else { return nil }
        guard let record = downloadedRecords[selectedModelId] else { return nil }
        guard validateRecordPaths(record) else {
            invalidateRecord(id: selectedModelId, message: "Selected Sherpa model files are missing. Please re-download.")
            return nil
        }
        return record
    }

    func validateSelectedModelForPlayback() -> String? {
        guard let selectedId = selectedModelId else {
            return "Select a downloaded Sherpa-onnx model before playback."
        }
        guard let record = downloadedRecords[selectedId], validateRecordPaths(record) else {
            invalidateRecord(id: selectedId, message: "Selected Sherpa model files are missing. Please re-download.")
            return "Selected Sherpa model files are missing. Please re-download."
        }
        return nil
    }

    func refreshModels() async {
        await MainActor.run {
            isLoading = true
        }

        do {
            let releaseURL = URL(string: "https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/tts-models")!
            var request = URLRequest(url: releaseURL)
            request.setValue("SpeakTheWeb", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let filtered = release.assets.compactMap { asset -> SherpaModel? in
                guard asset.name.hasPrefix("vits-piper-"),
                      asset.name.hasSuffix("-medium.tar.bz2")
                else {
                    return nil
                }

                guard let model = Self.parseModel(from: asset) else {
                    return nil
                }
                return model
            }

            let sorted = filtered.sorted { lhs, rhs in
                if lhs.languageCode == rhs.languageCode {
                    return lhs.name < rhs.name
                }
                return lhs.languageCode < rhs.languageCode
            }

            await MainActor.run {
                self.models = sorted
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                self.showError = true
            }
        }
    }

    func download(model: SherpaModel) {
        if case .downloading = downloadStates[model.id] ?? .idle {
            return
        }

        let task = session.downloadTask(with: model.downloadURL)
        task.taskDescription = model.id
        downloadStates[model.id] = .downloading(progress: 0)
        task.resume()
    }

    func delete(model: SherpaModel) {
        guard let record = downloadedRecords[model.id] else { return }
        let directoryURL = URL(fileURLWithPath: record.localDirectory)
        try? fileManager.removeItem(at: directoryURL)
        downloadedRecords.removeValue(forKey: model.id)
        if selectedModelId == model.id {
            selectedModelId = nil
        }
        persistRegistry()
    }

    func select(model: SherpaModel) {
        guard let record = downloadedRecords[model.id] else { return }
        guard validateRecordPaths(record) else {
            invalidateRecord(id: model.id, message: "Selected Sherpa model files are missing. Please re-download.")
            return
        }
        selectedModelId = model.id
    }

    func downloadState(for model: SherpaModel) -> DownloadState {
        downloadStates[model.id] ?? .idle
    }

    func isDownloaded(_ model: SherpaModel) -> Bool {
        guard let record = downloadedRecords[model.id] else { return false }
        guard validateRecordPaths(record) else {
            downloadedRecords.removeValue(forKey: model.id)
            persistRegistry()
            return false
        }
        return true
    }

    func uncompressedSizeBytes(for model: SherpaModel) -> Int? {
        downloadedRecords[model.id]?.uncompressedSizeBytes
    }

    private func ensureBaseDirectory() {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func loadRegistry() {
        guard fileManager.fileExists(atPath: registryURL.path),
              let data = try? Data(contentsOf: registryURL)
        else {
            return
        }

        do {
            let registry = try JSONDecoder().decode(ModelRegistry.self, from: data)
            let validRecords = registry.downloaded.filter { validateRecordPaths($0) }
            downloadedRecords = Dictionary(uniqueKeysWithValues: validRecords.map { ($0.id, $0) })
            if let selectedId = registry.selectedModelId,
               downloadedRecords[selectedId] != nil
            {
                selectedModelId = selectedId
            } else {
                selectedModelId = nil
                if registry.selectedModelId != nil {
                    errorMessage = "Selected Sherpa model files are missing. Please re-download."
                    showError = true
                }
            }
        } catch {
            print("Failed to load model registry: \(error)")
        }
    }

    private func persistRegistry() {
        let registry = ModelRegistry(downloaded: Array(downloadedRecords.values), selectedModelId: selectedModelId)
        do {
            let data = try JSONEncoder().encode(registry)
            try data.write(to: registryURL, options: [.atomic])
        } catch {
            print("Failed to persist model registry: \(error)")
        }
    }

    private func completeDownload(for model: SherpaModel, archiveURL: URL) {
        Task.detached(priority: .userInitiated) {
            do {
                let record = try self.extractArchive(for: model, archiveURL: archiveURL)
                try? self.fileManager.removeItem(at: archiveURL)

                await MainActor.run {
                    self.downloadedRecords[model.id] = record
                    self.downloadStates[model.id] = .idle
                    self.persistRegistry()
                }
            } catch {
                await MainActor.run {
                    self.downloadStates[model.id] = .failed(message: error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

    private func extractArchive(for model: SherpaModel, archiveURL: URL) throws -> SherpaModelRecord {
        let modelDirectory = baseDirectory.appendingPathComponent(model.id, isDirectory: true)
        if fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.removeItem(at: modelDirectory)
        }
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let archiveData = try Data(contentsOf: archiveURL)
        let decompressedData = try BZip2.decompress(data: archiveData)
        let entries = try TarContainer.open(container: decompressedData)

        for entry in entries {
            guard let entryPath = sanitizedPath(from: entry.info.name) else { continue }
            let destinationURL = modelDirectory.appendingPathComponent(entryPath)

            switch entry.info.type {
            case .directory:
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            case .regular, .contiguous:
                let parent = destinationURL.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: parent.path) {
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                guard let data = entry.data else {
                    throw ModelStoreError.invalidArchiveEntry
                }
                try data.write(to: destinationURL, options: [.atomic])
            case .symbolicLink, .hardLink:
                guard let linkTarget = sanitizedPath(from: entry.info.linkName) else { continue }
                let parent = destinationURL.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: parent.path) {
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                let targetURL = modelDirectory.appendingPathComponent(linkTarget)
                try fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: targetURL)
            case .blockSpecial, .characterSpecial, .fifo, .socket, .unknown:
                continue
            }
        }

        applyFileProtection(to: modelDirectory)

        let uncompressedSize = directorySize(at: modelDirectory)
        let modelPath = findFirstFile(withExtension: "onnx", in: modelDirectory)
        let tokensPath = findFirstFile(named: "tokens.txt", in: modelDirectory)
        let configPath = findFirstFile(named: "config.json", in: modelDirectory)

        guard let modelPath else {
            throw ModelStoreError.missingModelFiles
        }

        return SherpaModelRecord(
            id: model.id,
            languageCode: model.languageCode,
            name: model.name,
            downloadURL: model.downloadURL,
            compressedSizeBytes: model.compressedSizeBytes,
            uncompressedSizeBytes: uncompressedSize,
            localDirectory: modelDirectory.path,
            modelPath: modelPath.path,
            tokensPath: tokensPath?.path,
            configPath: configPath?.path
        )
    }

    private func directorySize(at url: URL) -> Int {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var total = 0
        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += resourceValues?.fileSize ?? 0
        }
        return total
    }

    private func applyFileProtection(to directory: URL) {
        let protection = FileProtectionType.completeUntilFirstUserAuthentication
        let attributes: [FileAttributeKey: Any] = [.protectionKey: protection]
        try? fileManager.setAttributes(attributes, ofItemAtPath: directory.path)
        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                try? fileManager.setAttributes(attributes, ofItemAtPath: fileURL.path)
            }
        }
    }

    private func validateRecordPaths(_ record: SherpaModelRecord) -> Bool {
        guard fileManager.fileExists(atPath: record.localDirectory) else {
            return false
        }
        guard fileManager.fileExists(atPath: record.modelPath) else {
            return false
        }
        if let tokensPath = record.tokensPath,
           !fileManager.fileExists(atPath: tokensPath)
        {
            return false
        }
        return true
    }

    private func invalidateRecord(id: String, message: String) {
        downloadedRecords.removeValue(forKey: id)
        if selectedModelId == id {
            selectedModelId = nil
        }
        persistRegistry()
        errorMessage = message
        showError = true
    }

    private func findFirstFile(withExtension fileExtension: String, in directory: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let fileURL as URL in enumerator where fileURL.pathExtension == fileExtension {
            return fileURL
        }
        return nil
    }

    private func findFirstFile(named fileName: String, in directory: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == fileName {
            return fileURL
        }
        return nil
    }

    private func sanitizedPath(from path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = trimmed.split(separator: "/")
        guard !components.contains("..") else { return nil }
        let sanitized = components.filter { $0 != "." }.joined(separator: "/")
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func parseModel(from asset: GitHubAsset) -> SherpaModel? {
        let prefix = "vits-piper-"
        let suffix = "-medium.tar.bz2"
        guard asset.name.hasPrefix(prefix), asset.name.hasSuffix(suffix) else {
            return nil
        }

        let start = asset.name.index(asset.name.startIndex, offsetBy: prefix.count)
        let end = asset.name.index(asset.name.endIndex, offsetBy: -suffix.count)
        let trimmed = String(asset.name[start ..< end])
        let parts = trimmed.split(separator: "-")
        guard let language = parts.first else { return nil }
        let nameParts = parts.dropFirst()
        let name = nameParts.isEmpty ? String(language) : nameParts.joined(separator: "-")

        let id = asset.name.replacingOccurrences(of: ".tar.bz2", with: "")
        guard let url = URL(string: asset.browserDownloadURL) else { return nil }

        return SherpaModel(
            id: id,
            languageCode: String(language),
            name: name,
            downloadURL: url,
            compressedSizeBytes: asset.size
        )
    }
}

extension SherpaOnnxModelStore: URLSessionDownloadDelegate {
    func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
    {
        guard let modelId = downloadTask.taskDescription else { return }
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        DispatchQueue.main.async {
            self.downloadStates[modelId] = .downloading(progress: progress)
        }
    }

    func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let modelId = downloadTask.taskDescription else { return }

        guard let model = models.first(where: { $0.id == modelId }) else { return }

        ensureBaseDirectory()
        let tempURL = baseDirectory.appendingPathComponent("\(model.id).tar.bz2")
        try? fileManager.removeItem(at: tempURL)

        do {
            try fileManager.moveItem(at: location, to: tempURL)
            DispatchQueue.main.async {
                self.downloadStates[model.id] = .processing
            }
            completeDownload(for: model, archiveURL: tempURL)
        } catch {
            DispatchQueue.main.async {
                self.downloadStates[model.id] = .failed(message: error.localizedDescription)
                self.errorMessage = error.localizedDescription
                self.showError = true
            }
        }
    }
}

private struct GitHubRelease: Decodable {
    let assets: [GitHubAsset]
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    let size: Int

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

private struct ModelRegistry: Codable {
    let downloaded: [SherpaModelRecord]
    let selectedModelId: String?
}

private enum ModelStoreError: LocalizedError {
    case missingModelFiles
    case invalidArchiveEntry

    var errorDescription: String? {
        switch self {
        case .missingModelFiles:
            return "Downloaded model is missing required files."
        case .invalidArchiveEntry:
            return "Downloaded model archive contains an invalid entry."
        }
    }
}
