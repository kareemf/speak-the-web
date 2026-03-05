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

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

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

        // Try to find main content area using a multi-phase approach
        var contentHTML = workingHTML

        // Phase 1: Simple semantic selectors (article, main)
        // [\s\S]*? crosses newlines without requiring dotMatchesLineSeparators
        let simpleSelectors = [
            "<article[^>]*>([\\s\\S]*?)</article>",
            "<main[^>]*>([\\s\\S]*?)</main>",
        ]
        for selector in simpleSelectors {
            if let regex = try? NSRegularExpression(
                pattern: selector,
                options: .caseInsensitive
            ),
                let match = regex.firstMatch(
                    in: workingHTML,
                    range: NSRange(workingHTML.startIndex..., in: workingHTML)
                ),
                let range = Range(match.range(at: 1), in: workingHTML)
            {
                contentHTML = String(workingHTML[range])
                break
            }
        }

        // Phase 2: Div selectors with depth counting for proper nesting
        if contentHTML == workingHTML {
            let divSelectors = [
                "<div[^>]*id=[\"']mw-content-text[\"'][^>]*>",
                "<div[^>]*id=[\"']mw-body-content[\"'][^>]*>",
                "<div[^>]*class=[\"'][^\"']*\\b(?:content|article|post|entry)\\b[^\"']*[\"'][^>]*>",
                "<div[^>]*id=[\"'][^\"']*\\b(?:content|article|post|entry)\\b[^\"']*[\"'][^>]*>",
            ]
            for selector in divSelectors {
                if let content = extractDivContent(from: workingHTML, openingPattern: selector) {
                    contentHTML = content
                    break
                }
            }
        }

        // Phase 3: ARIA role fallback (reuse depth counting for proper nesting)
        if contentHTML == workingHTML {
            let ariaSelectors = [
                "<div[^>]*role=[\"']main[\"'][^>]*>",
                "<div[^>]*role=[\"']article[\"'][^>]*>",
            ]
            for selector in ariaSelectors {
                if let content = extractDivContent(from: workingHTML, openingPattern: selector) {
                    contentHTML = content
                    break
                }
            }
        }

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
            let matches = regex.matches(in: workingHTML, options: [], range: NSRange(workingHTML.startIndex..., in: workingHTML))

            for match in matches {
                if let levelRange = Range(match.range(at: 1), in: workingHTML),
                   let textRange = Range(match.range(at: 2), in: workingHTML),
                   let level = Int(workingHTML[levelRange])
                {
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

    /// Extracts content from a div element by finding the opening tag via regex
    /// and then scanning for matching open/close div tags to handle nesting.
    /// Uses UTF-8 byte scanning for safe indexing (HTML tag names are ASCII).
    private func extractDivContent(from html: String, openingPattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: openingPattern,
            options: .caseInsensitive
        ),
            let match = regex.firstMatch(
                in: html,
                range: NSRange(html.startIndex..., in: html)
            ),
            let matchRange = Range(match.range, in: html)
        else {
            return nil
        }

        let searchStart = matchRange.upperBound
        let utf8 = Array(html.utf8)
        var pos = html.utf8.distance(from: html.utf8.startIndex, to: searchStart.samePosition(in: html.utf8)!)
        let len = utf8.count
        var depth = 1

        // ASCII bytes for comparison
        let lt: UInt8 = 0x3C // <
        let slash: UInt8 = 0x2F // /
        let gt: UInt8 = 0x3E // >
        let space: UInt8 = 0x20
        let tab: UInt8 = 0x09
        let newline: UInt8 = 0x0A
        let cr: UInt8 = 0x0D
        /// d/D = 0x64/0x44, i/I = 0x69/0x49, v/V = 0x76/0x56
        func isD(_ b: UInt8) -> Bool {
            b == 0x64 || b == 0x44
        }
        func isI(_ b: UInt8) -> Bool {
            b == 0x69 || b == 0x49
        }
        func isV(_ b: UInt8) -> Bool {
            b == 0x76 || b == 0x56
        }
        func isTagEnd(_ b: UInt8) -> Bool {
            b == space || b == gt || b == tab || b == newline || b == cr || b == slash
        }

        while pos < len, depth > 0 {
            // Scan for next '<'
            while pos < len, utf8[pos] != lt {
                pos += 1
            }
            if pos >= len { break }

            let remaining = len - pos

            // Check for </div
            if remaining >= 6,
               utf8[pos + 1] == slash,
               isD(utf8[pos + 2]),
               isI(utf8[pos + 3]),
               isV(utf8[pos + 4]),
               isTagEnd(utf8[pos + 5])
            {
                depth -= 1
                if depth == 0 {
                    // Convert UTF-8 offset back to String.Index
                    let endIndex = String.Index(utf8Index: html.utf8.index(html.utf8.startIndex, offsetBy: pos), within: html)!
                    return String(html[searchStart ..< endIndex])
                }
                pos += 6
            }
            // Check for <div (but not </div which we already handled)
            // Skip self-closing <div/> (scan ahead for /> to avoid unbalanced depth)
            else if remaining >= 4,
                    isD(utf8[pos + 1]),
                    isI(utf8[pos + 2]),
                    isV(utf8[pos + 3]),
                    remaining == 4 || isTagEnd(utf8[pos + 4])
            {
                // Check if self-closing: scan forward to find unquoted > and check for preceding /
                let dquote: UInt8 = 0x22 // "
                let squote: UInt8 = 0x27 // '
                var scanPos = pos + 4
                var isSelfClosing = false
                var inQuote: UInt8 = 0
                while scanPos < len {
                    let b = utf8[scanPos]
                    if inQuote != 0 {
                        if b == inQuote { inQuote = 0 }
                    } else if b == dquote || b == squote {
                        inQuote = b
                    } else if b == gt {
                        break
                    }
                    scanPos += 1
                }
                if scanPos < len, scanPos > pos + 4, utf8[scanPos - 1] == slash {
                    isSelfClosing = true
                }
                if !isSelfClosing {
                    depth += 1
                }
                pos = scanPos + 1
                continue
            } else {
                pos += 1
            }
        }

        return nil
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
