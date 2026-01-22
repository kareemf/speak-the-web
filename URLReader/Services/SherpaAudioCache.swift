import Foundation
import CryptoKit

final class SherpaAudioCache {
    struct Entry: Codable {
        let key: String
        let articleURL: String
        let modelId: String
        let voiceName: String?
        let generationSpeed: Float
        let fileName: String
        var fileSizeBytes: Int
        var lastUsed: Date
        let createdAt: Date
    }

    struct CachedAudioInfo {
        let modelId: String
        let voiceName: String?
    }

    private struct CacheIndex: Codable {
        let entries: [Entry]
    }

    private let fileManager: FileManager
    private let directoryURL: URL
    private let indexURL: URL
    private let maxEntries: Int
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "SherpaAudioCache")
    private var entries: [String: Entry] = [:]

    init(maxEntries: Int, maxBytes: Int, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.maxEntries = maxEntries
        self.maxBytes = maxBytes
        let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directoryURL = baseURL.appendingPathComponent("URLReader", isDirectory: true)
            .appendingPathComponent("SherpaAudioCache", isDirectory: true)
        indexURL = directoryURL.appendingPathComponent("cache-index.json")
        createDirectoryIfNeeded()
        loadIndex()
    }

    func cacheKey(text: String, modelId: String, generationSpeed: Float) -> String {
        let payload = "\(modelId)|\(generationSpeed)|\(text)"
        let data = Data(payload.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func destinationURL(for key: String) -> URL {
        directoryURL.appendingPathComponent("\(key).caf")
    }

    func cachedFileURL(for key: String) -> URL? {
        queue.sync {
            guard var entry = entries[key] else { return nil }
            let url = directoryURL.appendingPathComponent(entry.fileName)
            guard fileManager.fileExists(atPath: url.path) else {
                entries.removeValue(forKey: key)
                persistIndex()
                return nil
            }
            entry.lastUsed = Date()
            entries[key] = entry
            persistIndex()
            return url
        }
    }

    func store(fileURL: URL, key: String, articleURL: String, modelId: String, voiceName: String?, generationSpeed: Float) {
        queue.sync {
            let fileName = fileURL.lastPathComponent
            let fileSize = fileSizeBytes(for: fileURL)
            let entry = Entry(
                key: key,
                articleURL: articleURL,
                modelId: modelId,
                voiceName: voiceName,
                generationSpeed: generationSpeed,
                fileName: fileName,
                fileSizeBytes: fileSize,
                lastUsed: Date(),
                createdAt: Date()
            )
            entries[key] = entry
            pruneIfNeeded(allowOversizedKey: key)
            persistIndex()
            print("[SherpaCache] Stored \(fileName) (\(fileSize) bytes)")
        }
    }

    func cachedInfo(forArticleURL urlString: String) -> CachedAudioInfo? {
        queue.sync {
            let matches = entries.values.filter { $0.articleURL == urlString }
            guard let entry = matches.max(by: { $0.lastUsed < $1.lastUsed }) else { return nil }
            return CachedAudioInfo(modelId: entry.modelId, voiceName: entry.voiceName)
        }
    }

    func removeEntry(forKey key: String) {
        queue.sync {
            guard let entry = entries.removeValue(forKey: key) else { return }
            let url = directoryURL.appendingPathComponent(entry.fileName)
            try? fileManager.removeItem(at: url)
            persistIndex()
        }
    }

    func removeEntries(forArticleURL urlString: String) {
        queue.sync {
            let keysToRemove = entries.values
                .filter { $0.articleURL == urlString }
                .map { $0.key }
            for key in keysToRemove {
                if let entry = entries.removeValue(forKey: key) {
                    let url = directoryURL.appendingPathComponent(entry.fileName)
                    try? fileManager.removeItem(at: url)
                }
            }
            persistIndex()
        }
    }

    func clear() {
        queue.sync {
            entries.removeAll()
            persistIndex()
            do {
                let files = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
                for file in files where file.lastPathComponent != indexURL.lastPathComponent {
                    try fileManager.removeItem(at: file)
                }
            } catch {
                print("Failed to clear Sherpa audio cache: \(error)")
            }
        }
    }

    func totalBytes() -> Int {
        queue.sync {
            entries.values.reduce(0) { $0 + $1.fileSizeBytes }
        }
    }

    private func loadIndex() {
        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL) else {
            return
        }
        do {
            let index = try JSONDecoder().decode(CacheIndex.self, from: data)
            entries = Dictionary(uniqueKeysWithValues: index.entries.map { ($0.key, $0) })
        } catch {
            print("Failed to load Sherpa audio cache index: \(error)")
        }
    }

    private func persistIndex() {
        let index = CacheIndex(entries: Array(entries.values))
        do {
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexURL, options: [.atomic])
        } catch {
            print("Failed to persist Sherpa audio cache index: \(error)")
        }
    }

    private func pruneIfNeeded(allowOversizedKey: String? = nil) {
        var totalBytes = entries.values.reduce(0) { $0 + $1.fileSizeBytes }
        if let key = allowOversizedKey,
           let oversizedEntry = entries[key],
           oversizedEntry.fileSizeBytes > maxBytes {
            let entriesToRemove = entries.values
                .filter { $0.key != key }
                .sorted { $0.lastUsed < $1.lastUsed }
            for entry in entriesToRemove {
                entries.removeValue(forKey: entry.key)
                let url = directoryURL.appendingPathComponent(entry.fileName)
                try? fileManager.removeItem(at: url)
                totalBytes -= entry.fileSizeBytes
            }
            return
        }
        var sorted = entries.values.sorted { $0.lastUsed < $1.lastUsed }

        while entries.count > maxEntries || totalBytes > maxBytes {
            guard let entry = sorted.first else { break }
            sorted.removeFirst()
            entries.removeValue(forKey: entry.key)
            let url = directoryURL.appendingPathComponent(entry.fileName)
            try? fileManager.removeItem(at: url)
            totalBytes -= entry.fileSizeBytes
        }
    }

    private func createDirectoryIfNeeded() {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create Sherpa audio cache directory: \(error)")
        }
    }

    private func fileSizeBytes(for url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
