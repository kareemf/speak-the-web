import CryptoKit
import Foundation

/// Represents a recently read article for persistence
struct RecentArticle: Identifiable, Codable {
    let id: UUID
    let url: String
    let title: String
    let host: String
    let readAt: Date
    let lastPosition: Int
    let contentLength: Int
    let wordCount: Int
    let cachedBytes: Int

    init(id: UUID = UUID(), url: String, title: String, host: String, readAt: Date = Date(), lastPosition: Int = 0, contentLength: Int = 0, wordCount: Int = 0, cachedBytes: Int = 0) {
        self.id = id
        self.url = url
        self.title = title
        self.host = host
        self.readAt = readAt
        self.lastPosition = lastPosition
        self.contentLength = contentLength
        self.wordCount = wordCount
        self.cachedBytes = cachedBytes
    }

    init(from article: Article, cachedBytes: Int = 0) {
        self.init(
            id: UUID(),
            url: article.url.absoluteString,
            title: article.title,
            host: article.url.host ?? "Unknown",
            readAt: Date(),
            lastPosition: 0,
            contentLength: article.content.count,
            wordCount: article.wordCount,
            cachedBytes: cachedBytes
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        host = try container.decode(String.self, forKey: .host)
        readAt = try container.decode(Date.self, forKey: .readAt)
        lastPosition = try container.decodeIfPresent(Int.self, forKey: .lastPosition) ?? 0
        contentLength = try container.decodeIfPresent(Int.self, forKey: .contentLength) ?? 0
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount) ?? 0
        cachedBytes = try container.decodeIfPresent(Int.self, forKey: .cachedBytes) ?? 0
    }

    /// Returns a human-readable time ago string
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: readAt, relativeTo: Date())
    }
}

/// Manager for persisting recent articles to UserDefaults
class RecentArticlesManager {
    private let userDefaults: UserDefaults
    private let key = "recentArticles"
    private let cacheStore: DiskArticleCache

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        cacheStore = DiskArticleCache()
    }

    /// Loads recent articles from storage
    func load() -> [RecentArticle] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder().decode([RecentArticle].self, from: data)
        } catch {
            print("Failed to decode recent articles: \(error)")
            return []
        }
    }

    /// Saves a new article to recent history
    func save(_ article: Article) {
        var articles = load()

        // Remove existing entry with same URL if present
        articles.removeAll { $0.url == article.url.absoluteString }

        // Add new entry at the beginning
        cacheStore.save(article)
        let recent = RecentArticle(from: article)
        articles.insert(recent, at: 0)

        // Persist
        persist(articles)
        cacheStore.prune(keeping: Set(articles.map { $0.url }))
    }

    /// Clears all recent articles
    func clear() {
        userDefaults.removeObject(forKey: key)
        cacheStore.clear()
    }

    private func persist(_ articles: [RecentArticle]) {
        do {
            let data = try JSONEncoder().encode(articles)
            userDefaults.set(data, forKey: key)
        } catch {
            print("Failed to encode recent articles: \(error)")
        }
    }

    func loadCachedArticle(for urlString: String) -> CachedArticle? {
        cacheStore.load(urlString: urlString)
    }

    func remove(urlString: String) -> [RecentArticle] {
        var articles = load()
        articles.removeAll { $0.url == urlString }
        persist(articles)
        cacheStore.remove(urlString: urlString)
        return articles
    }

    func updateProgress(urlString: String, position: Int, contentLength: Int, wordCount: Int) -> [RecentArticle] {
        var articles = load()
        guard let index = articles.firstIndex(where: { $0.url == urlString }) else {
            return articles
        }

        let entry = articles[index]
        let updated = RecentArticle(
            id: entry.id,
            url: entry.url,
            title: entry.title,
            host: entry.host,
            readAt: entry.readAt,
            lastPosition: position,
            contentLength: contentLength,
            wordCount: wordCount,
            cachedBytes: entry.cachedBytes
        )

        articles[index] = updated
        persist(articles)
        cacheStore.updateProgress(urlString: urlString, position: position)
        return articles
    }
}

final class DiskArticleCache {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directoryURL = baseURL.appendingPathComponent("SpeakTheWeb", isDirectory: true)
            .appendingPathComponent("ArticleCache", isDirectory: true)
        createDirectoryIfNeeded()
    }

    func save(_ article: Article) {
        let cached = CachedArticle(from: article)
        let url = cacheURL(for: article.url.absoluteString)
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: url, options: .atomic)
            if let size = size(urlString: article.url.absoluteString) {
                print("Cached article size for \(article.url.absoluteString): \(size) bytes")
            }
        } catch {
            print("Failed to write cached article: \(error)")
        }
    }

    func load(urlString: String) -> CachedArticle? {
        let url = cacheURL(for: urlString)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CachedArticle.self, from: data)
        } catch {
            print("Failed to read cached article: \(error)")
            return nil
        }
    }

    func size(urlString: String) -> Int? {
        let url = cacheURL(for: urlString)
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return values.fileSize
        } catch {
            return nil
        }
    }

    func remove(urlString: String) {
        let url = cacheURL(for: urlString)
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            print("Failed to remove cached article: \(error)")
        }
    }

    func prune(keeping urls: Set<String>) {
        let keepSet = Set(urls.map { cacheURL(for: $0).lastPathComponent })
        do {
            let files = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            for file in files where !keepSet.contains(file.lastPathComponent) {
                try fileManager.removeItem(at: file)
            }
        } catch {
            print("Failed to prune cache directory: \(error)")
        }
    }

    func clear() {
        do {
            let files = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
        } catch {
            print("Failed to clear cache directory: \(error)")
        }
    }

    private func cacheURL(for urlString: String) -> URL {
        let filename = hash(urlString)
        return directoryURL.appendingPathComponent(filename).appendingPathExtension("json")
    }

    private func createDirectoryIfNeeded() {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create cache directory: \(error)")
        }
    }

    private func hash(_ value: String) -> String {
        let data = Data(value.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func updateProgress(urlString: String, position: Int) {
        let url = cacheURL(for: urlString)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            var cached = try JSONDecoder().decode(CachedArticle.self, from: data)
            cached.lastPosition = position
            let updatedData = try JSONEncoder().encode(cached)
            try updatedData.write(to: url, options: .atomic)
        } catch {
            print("Failed to update cached article progress: \(error)")
        }
    }
}
