import Foundation

/// Service for extracting readable content from URLs
class ContentExtractor {

    enum ExtractionError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case parsingError
        case noContent

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL provided"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .parsingError:
                return "Failed to parse page content"
            case .noContent:
                return "No readable content found on this page"
            }
        }
    }

    /// Extracts article content from a URL
    func extract(from urlString: String) async throws -> Article {
        // Normalize URL
        var normalizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
            normalizedURL = "https://" + normalizedURL
        }

        guard let url = URL(string: normalizedURL) else {
            throw ExtractionError.invalidURL
        }

        // Fetch HTML content
        let html: String
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            // Check for valid response
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw ExtractionError.networkError(
                    NSError(domain: "HTTP", code: httpResponse.statusCode,
                           userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                )
            }

            // Detect encoding and convert to string
            html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
        } catch let error as ExtractionError {
            throw error
        } catch {
            throw ExtractionError.networkError(error)
        }

        guard !html.isEmpty else {
            throw ExtractionError.noContent
        }

        // Parse HTML
        let title = extractTitle(from: html)
        let (content, sections) = extractContent(from: html)

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionError.noContent
        }

        return Article(
            url: url,
            title: title,
            content: content,
            sections: sections,
            extractedAt: Date()
        )
    }

    /// Extracts the page title from HTML
    private func extractTitle(from html: String) -> String {
        // Try <title> tag first
        if let titleMatch = html.range(of: "<title[^>]*>(.*?)</title>", options: .regularExpression) {
            let titleHTML = String(html[titleMatch])
            let cleaned = titleHTML
                .replacingOccurrences(of: "<title[^>]*>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "</title>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return decodeHTMLEntities(cleaned)
            }
        }

        // Try og:title meta tag
        if let ogTitle = extractMetaContent(from: html, property: "og:title") {
            return ogTitle
        }

        // Try first h1
        if let h1Match = html.range(of: "<h1[^>]*>(.*?)</h1>", options: [.regularExpression, .caseInsensitive]) {
            let h1Text = stripHTMLTags(String(html[h1Match]))
            if !h1Text.isEmpty {
                return h1Text
            }
        }

        return "Untitled Article"
    }

    /// Extracts meta tag content
    private func extractMetaContent(from html: String, property: String) -> String? {
        let patterns = [
            "<meta[^>]*property=[\"']\(property)[\"'][^>]*content=[\"']([^\"']*)[\"']",
            "<meta[^>]*content=[\"']([^\"']*)[\"'][^>]*property=[\"']\(property)[\"']"
        ]

        for pattern in patterns {
            if let match = html.range(of: pattern, options: .regularExpression) {
                let metaTag = String(html[match])
                if let contentMatch = metaTag.range(of: "content=[\"']([^\"']*)[\"']", options: .regularExpression) {
                    let content = String(metaTag[contentMatch])
                        .replacingOccurrences(of: "content=[\"']", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "[\"']$", with: "", options: .regularExpression)
                    return decodeHTMLEntities(content)
                }
            }
        }
        return nil
    }

    /// Extracts main content and sections from HTML
    private func extractContent(from html: String) -> (String, [ArticleSection]) {
        var workingHTML = html

        // Remove unwanted elements
        let unwantedTags = ["script", "style", "nav", "header", "footer", "aside",
                           "noscript", "iframe", "form", "button", "input", "select",
                           "textarea", "svg", "canvas", "video", "audio"]
        for tag in unwantedTags {
            // Use NSRegularExpression for dotMatchesLineSeparators support
            if let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                options: .caseInsensitive
            ) {
                workingHTML = regex.stringByReplacingMatches(
                    in: workingHTML,
                    range: NSRange(workingHTML.startIndex..., in: workingHTML),
                    withTemplate: ""
                )
            }
            // Also remove self-closing variants
            workingHTML = workingHTML.replacingOccurrences(
                of: "<\(tag)[^>]*/?>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Try to find main content area
        let contentSelectors = [
            "<article[^>]*>(.*?)</article>",
            "<main[^>]*>(.*?)</main>",
            "<div[^>]*class=[\"'][^\"']*(?:content|article|post|entry)[^\"']*[\"'][^>]*>(.*?)</div>",
            "<div[^>]*id=[\"'][^\"']*(?:content|article|post|entry)[^\"']*[\"'][^>]*>(.*?)</div>"
        ]

        var contentHTML = workingHTML
        for selector in contentSelectors {
            // Use NSRegularExpression for dotMatchesLineSeparators support
            if let regex = try? NSRegularExpression(
                pattern: selector,
                options: .caseInsensitive
            ),
               let match = regex.firstMatch(
                in: workingHTML,
                range: NSRange(workingHTML.startIndex..., in: workingHTML)
               ),
               let range = Range(match.range, in: workingHTML) {
                contentHTML = String(workingHTML[range])
                break
            }
        }

        // Extract sections (headings) before stripping tags
        var sections: [ArticleSection] = []
        let headingPattern = "<h([1-6])[^>]*>(.*?)</h\\1>"
        let regex = try? NSRegularExpression(pattern: headingPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])

        // Convert paragraphs and line breaks
        contentHTML = contentHTML.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        contentHTML = contentHTML.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        contentHTML = contentHTML.replacingOccurrences(of: "</h[1-6]>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        contentHTML = contentHTML.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
        contentHTML = contentHTML.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        contentHTML = contentHTML.replacingOccurrences(of: "</tr>", with: "\n", options: .caseInsensitive)

        // Strip remaining HTML tags
        var plainText = stripHTMLTags(contentHTML)

        // Clean up whitespace
        plainText = plainText.replacingOccurrences(of: "\r\n", with: "\n")
        plainText = plainText.replacingOccurrences(of: "\r", with: "\n")
        plainText = plainText.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        plainText = plainText.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        plainText = decodeHTMLEntities(plainText)
        plainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Now extract sections from the plain text by finding heading text
        if let regex = regex {
            let matches = regex.matches(in: workingHTML, options: [], range: NSRange(workingHTML.startIndex..., in: workingHTML))

            for match in matches {
                if let levelRange = Range(match.range(at: 1), in: workingHTML),
                   let textRange = Range(match.range(at: 2), in: workingHTML),
                   let level = Int(workingHTML[levelRange]) {

                    let headingText = stripHTMLTags(String(workingHTML[textRange]))
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !headingText.isEmpty else { continue }

                    // Find this heading in the plain text
                    if let foundRange = plainText.range(of: headingText, options: .caseInsensitive) {
                        let startIndex = plainText.distance(from: plainText.startIndex, to: foundRange.lowerBound)
                        sections.append(ArticleSection(
                            title: headingText,
                            level: level,
                            range: foundRange,
                            startIndex: startIndex
                        ))
                    }
                }
            }
        }

        // Sort sections by their position in the text
        sections.sort { $0.startIndex < $1.startIndex }

        return (plainText, sections)
    }

    /// Removes HTML tags from a string
    private func stripHTMLTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// Decodes HTML entities
    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string

        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&nbsp;": " ",
            "&ndash;": "–",
            "&mdash;": "—",
            "&lsquo;": "'",
            "&rsquo;": "'",
            "&ldquo;": "\u{201C}",
            "&rdquo;": "\u{201D}",
            "&hellip;": "…",
            "&copy;": "©",
            "&reg;": "®",
            "&trade;": "™",
            "&bull;": "•",
            "&middot;": "·"
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Handle numeric entities
        let numericPattern = "&#([0-9]+);"
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let numRange = Range(match.range(at: 1), in: result),
                   let codePoint = Int(result[numRange]),
                   let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }

        // Handle hex entities
        let hexPattern = "&#x([0-9a-fA-F]+);"
        if let regex = try? NSRegularExpression(pattern: hexPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let hexRange = Range(match.range(at: 1), in: result),
                   let codePoint = Int(result[hexRange], radix: 16),
                   let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }

        return result
    }
}
