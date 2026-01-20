import Foundation

/// Represents an extracted article from a URL
struct Article: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let content: String
    let sections: [ArticleSection]
    let extractedAt: Date

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
