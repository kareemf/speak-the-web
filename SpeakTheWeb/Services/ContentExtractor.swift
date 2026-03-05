import Foundation

/// Service for extracting readable content from URLs.
///
/// ## Security Design
///
/// This implementation prioritizes security over rendering fidelity:
///
/// ### Parser Choice
/// Uses a non-executing regex-based HTML parser (NOT WKWebView or JavaScriptCore).
/// This prevents XSS attacks since no JavaScript is ever evaluated. The regex approach
/// is less sophisticated than DOM parsers but eliminates entire attack surfaces.
///
/// ### Text-Only Extraction
/// - Extracts text content only; does not evaluate scripts or load remote resources
/// - Does NOT fetch any URLs found in HTML (images, stylesheets, scripts, iframes, fonts, etc.)
/// - Does NOT resolve relative URLs in parsed content
/// - Does NOT follow `<link rel="canonical">`, `<meta http-equiv="refresh">`, or other redirects
/// - All `src`, `href`, `srcset` attributes are ignored during parsing
///
/// ### Dangerous Element Removal
/// Before text extraction, these elements are stripped completely:
/// `script`, `style`, `nav`, `header`, `footer`, `aside`, `noscript`, `iframe`,
/// `form`, `button`, `input`, `select`, `textarea`, `svg`, `canvas`, `video`, `audio`
///
/// ### Text Sanitization
/// After extraction, text is sanitized to remove:
/// - HTML entities (decoded to plain text)
/// - Null bytes and control characters (except newlines/tabs)
/// - Excessive whitespace
///
/// ### SSRF/DNS Rebinding Protection
/// See DNSResolver.swift for pre-fetch and post-connect IP validation.
final class ContentExtractor: NSObject {
    private struct RedirectContext {
        var allowedHTTPHosts: Set<String>
        var redirectCount: Int
        var initialScheme: String
    }

    private let redirectQueue = DispatchQueue(label: "ContentExtractor.Redirect")
    private var redirectContexts: [Int: RedirectContext] = [:]
    private var redirectErrors: [Int: ExtractionError] = [:]
    private let maxRedirects = 10

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    enum ExtractionError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case parsingError
        case noContent
        case requiresHTTPConfirmation(URL, host: String)
        case redirectBlocked(String)
        case redirectLoop
        case dnsResolutionFailed(String)
        case allIPsBlocked(String)
        case postConnectIPBlocked(String)
        case connectionVerificationFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "Invalid URL provided"
            case let .networkError(error):
                "Network error: \(error.localizedDescription)"
            case .parsingError:
                "Failed to parse page content"
            case .noContent:
                "No readable content found on this page"
            case let .requiresHTTPConfirmation(_, host):
                "HTTP access requires confirmation for \(host)"
            case let .redirectBlocked(reason):
                "Redirect blocked: \(reason)"
            case .redirectLoop:
                "Too many redirects"
            case let .dnsResolutionFailed(message):
                message
            case let .allIPsBlocked(host):
                "Cannot access '\(host)'. All resolved addresses are in blocked ranges."
            case let .postConnectIPBlocked(ip):
                "Connection blocked: '\(ip)' is a private or reserved address."
            case .connectionVerificationFailed:
                "Unable to verify connection security. If you're using a VPN or proxy, try disabling it temporarily to load this article."
            }
        }
    }

    /// Extracts article content from a URL
    func extract(from urlString: String, allowedHTTPHosts: Set<String> = []) async throws -> Article {
        // Normalize URL
        var normalizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedURL.hasPrefix("http://"), !normalizedURL.hasPrefix("https://") {
            normalizedURL = "https://" + normalizedURL
        }

        guard let url = URL(string: normalizedURL) else {
            throw ExtractionError.invalidURL
        }

        return try await extract(from: url, allowedHTTPHosts: allowedHTTPHosts)
    }

    /// Extracts article content from a URL
    func extract(from url: URL, allowedHTTPHosts: Set<String> = []) async throws -> Article {
        let initialScheme = url.scheme?.lowercased() ?? "https"

        // Pre-fetch DNS validation (DNS rebinding protection)
        if let host = url.host {
            let dnsResult = await DNSResolver.resolve(host)
            switch dnsResult {
            case .resolved:
                // At least one public IP found - proceed with fetch
                break
            case .allBlocked:
                throw ExtractionError.allIPsBlocked(host)
            case let .failed(error):
                throw ExtractionError.dnsResolutionFailed(error.localizedDescription)
            }
        }

        let request = URLRequest(url: url)

        // Fetch HTML content
        let html: String
        do {
            let (data, response) = try await data(
                for: request,
                allowedHTTPHosts: allowedHTTPHosts,
                initialScheme: initialScheme
            )

            // Check for valid response
            if let httpResponse = response as? HTTPURLResponse,
               !(200 ... 299).contains(httpResponse.statusCode)
            {
                throw ExtractionError.networkError(
                    NSError(
                        domain: "HTTP",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
                    )
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

    private func data(
        for request: URLRequest,
        allowedHTTPHosts: Set<String>,
        initialScheme: String
    ) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            var taskId: Int?

            let task = session.dataTask(with: request) { [weak self] data, response, error in
                guard let self, let taskId else { return }

                let redirectError = redirectQueue.sync { self.redirectErrors[taskId] }
                redirectQueue.sync {
                    self.redirectContexts[taskId] = nil
                    self.redirectErrors[taskId] = nil
                }

                if let redirectError {
                    continuation.resume(throwing: redirectError)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let response else {
                    continuation.resume(throwing: ExtractionError.networkError(NSError(domain: "HTTP", code: -1)))
                    return
                }

                continuation.resume(returning: (data, response))
            }

            taskId = task.taskIdentifier
            redirectQueue.sync {
                self.redirectContexts[task.taskIdentifier] = RedirectContext(
                    allowedHTTPHosts: allowedHTTPHosts,
                    redirectCount: 0,
                    initialScheme: initialScheme
                )
            }

            task.resume()
        }
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
            "<meta[^>]*content=[\"']([^\"']*)[\"'][^>]*property=[\"']\(property)[\"']",
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
        let unwantedTags = [
            "script",
            "style",
            "nav",
            "header",
            "footer",
            "aside",
            "noscript",
            "iframe",
            "form",
            "button",
            "input",
            "select",
            "textarea",
            "svg",
            "canvas",
            "video",
            "audio",
        ]
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
            "<div[^>]*id=[\"'][^\"']*(?:content|article|post|entry)[^\"']*[\"'][^>]*>(.*?)</div>",
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
                let range = Range(match.range, in: workingHTML)
            {
                contentHTML = String(workingHTML[range])
                break
            }
        }

        // Remove MediaWiki-specific noise elements (only if page is MediaWiki)
        let isMediaWiki = workingHTML.contains("mw-content-text") || workingHTML.contains("mw-body-content")
        let noisePatterns: [String] = isMediaWiki ? [
            "<sup[^>]*class=[\"'][^\"']*\\breference\\b[^\"']*[\"'][^>]*>[\\s\\S]*?</sup>",
            "<span[^>]*class=[\"'][^\"']*\\bmw-editsection\\b[^\"']*[\"'][^>]*>[\\s\\S]*?</span>",
            "<ol[^>]*class=[\"'][^\"']*\\breferences\\b[^\"']*[\"'][^>]*>[\\s\\S]*?</ol>",
            "<table[^>]*class=[\"'][^\"']*\\b(?:navbox|infobox)\\b[^\"']*[\"'][^>]*>[\\s\\S]*?</table>",
            "<div[^>]*id=[\"']mw-panel-toc[\"'][^>]*>[\\s\\S]*?</div>",
            "<div[^>]*class=[\"'][^\"']*\\b(?:reflist|catlinks|printfooter|mw-[a-z-]+)\\b[^\"']*[\"'][^>]*>[\\s\\S]*?</div>",
        ] : []
        for pattern in noisePatterns {
            if let regex = try? NSRegularExpression(
                pattern: pattern,
                options: .caseInsensitive
            ) {
                contentHTML = regex.stringByReplacingMatches(
                    in: contentHTML,
                    range: NSRange(contentHTML.startIndex..., in: contentHTML),
                    withTemplate: ""
                )
            }
        }

        let contentHTMLForHeadings = contentHTML

        // Extract sections (headings) before stripping tags
        var sections: [ArticleSection] = []
        let headingPattern = "<h([1-6])[^>]*>(.*?)</h\\1>"
        let regex = try? NSRegularExpression(pattern: headingPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])

        // Convert paragraphs and line breaks
        contentHTML = contentHTML.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        contentHTML = contentHTML.replacingOccurrences(
            of: "<br[^>]*>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        contentHTML = contentHTML.replacingOccurrences(
            of: "</h[1-6]>",
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
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
        plainText = sanitizeText(plainText)
        plainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Now extract sections from the plain text by finding heading text
        if let regex {
            let matches = regex.matches(
                in: contentHTMLForHeadings,
                options: [],
                range: NSRange(contentHTMLForHeadings.startIndex..., in: contentHTMLForHeadings)
            )

            for match in matches {
                if let levelRange = Range(match.range(at: 1), in: contentHTMLForHeadings),
                   let textRange = Range(match.range(at: 2), in: contentHTMLForHeadings),
                   let level = Int(contentHTMLForHeadings[levelRange])
                {
                    let headingText = stripHTMLTags(String(contentHTMLForHeadings[textRange]))
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

    /// Sanitizes text by removing null bytes and control characters.
    /// Preserves newlines (\n, \r), tabs (\t), and all printable characters.
    /// This prevents potential issues with null-byte injection or hidden control sequences.
    private func sanitizeText(_ string: String) -> String {
        string.unicodeScalars.filter { scalar in
            // Keep printable characters, newlines, tabs, and carriage returns
            scalar == "\n" || scalar == "\r" || scalar == "\t" || scalar.value >= 0x20
        }.map { String($0) }.joined()
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
            "&middot;": "·",
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
                   let scalar = Unicode.Scalar(codePoint)
                {
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
                   let scalar = Unicode.Scalar(codePoint)
                {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }

        return result
    }
}

extension ContentExtractor: URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let redirectURL = request.url else {
            completionHandler(nil)
            return
        }

        var context = redirectQueue.sync { redirectContexts[task.taskIdentifier] }
        guard let existingContext = context else {
            completionHandler(request)
            return
        }

        if existingContext.redirectCount >= maxRedirects {
            redirectQueue.sync {
                redirectErrors[task.taskIdentifier] = .redirectLoop
            }
            completionHandler(nil)
            return
        }

        context?.redirectCount += 1
        if let context {
            redirectQueue.sync { redirectContexts[task.taskIdentifier] = context }
        }

        // Perform DNS validation for redirect target
        if let host = redirectURL.host {
            Task {
                let dnsResult = await DNSResolver.resolve(host)
                switch dnsResult {
                case .resolved:
                    // Continue with URL validation
                    self.validateAndCompleteRedirect(
                        request: request,
                        redirectURL: redirectURL,
                        existingContext: existingContext,
                        taskIdentifier: task.taskIdentifier,
                        completionHandler: completionHandler
                    )
                case .allBlocked:
                    self.redirectQueue.sync {
                        self.redirectErrors[task.taskIdentifier] = .allIPsBlocked(host)
                    }
                    completionHandler(nil)
                case let .failed(error):
                    self.redirectQueue.sync {
                        self.redirectErrors[task.taskIdentifier] = .dnsResolutionFailed(error.localizedDescription)
                    }
                    completionHandler(nil)
                }
            }
        } else {
            validateAndCompleteRedirect(
                request: request,
                redirectURL: redirectURL,
                existingContext: existingContext,
                taskIdentifier: task.taskIdentifier,
                completionHandler: completionHandler
            )
        }
    }

    private func validateAndCompleteRedirect(
        request: URLRequest,
        redirectURL: URL,
        existingContext: RedirectContext,
        taskIdentifier: Int,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        switch URLValidator.validate(redirectURL.absoluteString) {
        case let .valid(validURL):
            if let scheme = validURL.scheme?.lowercased(),
               scheme == "http",
               let host = validURL.host?.lowercased(),
               !existingContext.allowedHTTPHosts.contains(host),
               existingContext.initialScheme == "https"
            {
                redirectQueue.sync {
                    redirectErrors[taskIdentifier] = .requiresHTTPConfirmation(validURL, host: host)
                }
                completionHandler(nil)
                return
            }

            var updatedRequest = request
            updatedRequest.url = validURL
            completionHandler(updatedRequest)
        case let .requiresHTTPConfirmation(url, host):
            if existingContext.allowedHTTPHosts.contains(host) {
                var updatedRequest = request
                updatedRequest.url = url
                completionHandler(updatedRequest)
            } else {
                redirectQueue.sync {
                    redirectErrors[taskIdentifier] = .requiresHTTPConfirmation(url, host: host)
                }
                completionHandler(nil)
            }
        case let .invalid(error):
            redirectQueue.sync {
                redirectErrors[taskIdentifier] = .redirectBlocked(error.localizedDescription)
            }
            completionHandler(nil)
        }
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        // Post-connect IP validation using transaction metrics
        // This catches DNS rebinding attacks where the actual connected IP differs from resolved IP
        for transaction in metrics.transactionMetrics {
            guard let remoteAddress = transaction.remoteAddress else {
                // Fail-closed: If we can't verify the IP, record an error
                // This may indicate VPN/proxy usage
                #if DEBUG
                    print("[ContentExtractor] Post-connect validation: remoteAddress is nil (possible VPN/proxy)")
                #endif
                redirectQueue.sync {
                    self.redirectErrors[task.taskIdentifier] = .connectionVerificationFailed
                }
                return
            }

            // Extract IP string from sockaddr
            if let ipString = extractIPFromSockAddr(remoteAddress) {
                if !DNSResolver.isAllowedIP(ipString) {
                    #if DEBUG
                        print("[ContentExtractor] Post-connect validation BLOCKED: \(ipString)")
                    #endif
                    redirectQueue.sync {
                        self.redirectErrors[task.taskIdentifier] = .postConnectIPBlocked(ipString)
                    }
                    // Cancel the task since we detected a blocked IP
                    task.cancel()
                    return
                }
                #if DEBUG
                    print("[ContentExtractor] Post-connect validation PASSED: \(ipString)")
                #endif
            }
        }
    }

    private func extractIPFromSockAddr(_ endpoint: String) -> String? {
        // URLSessionTaskTransactionMetrics.remoteAddress format:
        // IPv4: "192.168.1.1:443" or just "192.168.1.1"
        // IPv6: "[::1]:443" or "[2001:db8::1]:443"
        var ip = endpoint

        // Handle IPv6 with brackets and port: "[::1]:443"
        if ip.hasPrefix("[") {
            if let closeBracket = ip.firstIndex(of: "]") {
                ip = String(ip[ip.index(after: ip.startIndex) ..< closeBracket])
                return ip
            }
        }

        // Handle IPv4 with port: "192.168.1.1:443"
        // IPv4 has exactly one colon if port is present
        if ip.contains("."), ip.count(where: { $0 == ":" }) == 1 {
            if let colonIndex = ip.lastIndex(of: ":") {
                ip = String(ip[..<colonIndex])
            }
        }

        return ip.isEmpty ? nil : ip
    }
}
