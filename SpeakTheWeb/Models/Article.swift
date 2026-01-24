import Foundation

/// Represents an extracted article from a URL
struct Article: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let content: String
    let sections: [ArticleSection]
    let extractedAt: Date

    init(url: URL, title: String, content: String, sections: [ArticleSection], extractedAt: Date = Date()) {
        self.url = url
        self.title = title
        self.content = content
        self.sections = sections
        self.extractedAt = extractedAt
    }

    init(cached: CachedArticle) {
        let resolvedURL = URL(string: cached.url) ?? URL(string: "about:blank")!
        url = resolvedURL
        title = cached.title
        content = cached.content
        extractedAt = cached.extractedAt

        let sortedSections = cached.sections.sorted { $0.startIndex < $1.startIndex }
        var mappedSections: [ArticleSection] = []
        mappedSections.reserveCapacity(sortedSections.count)

        for (index, section) in sortedSections.enumerated() {
            let startOffset = max(0, min(section.startIndex, cached.content.count))
            let startIndex = cached.content.index(cached.content.startIndex, offsetBy: startOffset)

            let endOffset: Int = if index + 1 < sortedSections.count {
                max(startOffset, min(sortedSections[index + 1].startIndex, cached.content.count))
            } else {
                cached.content.count
            }
            let endIndex = cached.content.index(cached.content.startIndex, offsetBy: endOffset)

            mappedSections.append(ArticleSection(
                title: section.title,
                level: section.level,
                range: startIndex ..< endIndex,
                startIndex: section.startIndex
            ))
        }

        sections = mappedSections
    }

    /// Total word count of the article
    var wordCount: Int {
        content.split(separator: " ").count
    }

    /// Estimated reading time in minutes (average 200 words per minute)
    var estimatedReadingTime: Int {
        max(1, wordCount / 200)
    }
}

/// Represents a section within an article (for table of contents)
struct ArticleSection: Identifiable {
    let id = UUID()
    let title: String
    let level: Int // 1 = h1, 2 = h2, etc.
    let range: Range<String.Index>
    let startIndex: Int // Character offset in the content

    /// Indentation based on heading level
    var indentation: CGFloat {
        CGFloat((level - 1) * 16)
    }
}

struct CachedArticle: Codable {
    let url: String
    let title: String
    let content: String
    let sections: [CachedSection]
    let extractedAt: Date
    var lastPosition: Int

    init(from article: Article) {
        url = article.url.absoluteString
        title = article.title
        content = article.content
        sections = article.sections.map { CachedSection(from: $0) }
        extractedAt = article.extractedAt
        lastPosition = 0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        sections = try container.decode([CachedSection].self, forKey: .sections)
        extractedAt = try container.decode(Date.self, forKey: .extractedAt)
        lastPosition = try container.decodeIfPresent(Int.self, forKey: .lastPosition) ?? 0
    }
}

struct CachedSection: Codable {
    let title: String
    let level: Int
    let startIndex: Int

    init(from section: ArticleSection) {
        title = section.title
        level = section.level
        startIndex = section.startIndex
    }
}
