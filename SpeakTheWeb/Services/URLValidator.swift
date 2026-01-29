import Darwin
import Foundation

/// Comprehensive URL validator for security-sensitive URL fetching.
/// Validates schemes, hosts, and IP addresses to prevent SSRF attacks.
enum URLValidator {
    // MARK: - Validation Result

    enum ValidationResult {
        case valid(URL)
        case requiresHTTPConfirmation(URL, host: String)
        case invalid(ValidationError)
    }

    enum ValidationError: LocalizedError {
        case emptyURL
        case malformedURL
        case unsupportedScheme(String)
        case blockedHost(String)
        case blockedIPAddress(String)
        case embeddedCredentials
        case nonASCIIHostname
        case invalidIPFormat

        var errorDescription: String? {
            switch self {
            case .emptyURL:
                "Please enter a URL"
            case .malformedURL:
                "The URL format is invalid"
            case let .unsupportedScheme(scheme):
                "URLs with '\(scheme)' are not supported. Please use http or https."
            case let .blockedHost(host):
                "Cannot access '\(host)'. Local and private network addresses are not allowed."
            case let .blockedIPAddress(ip):
                "Cannot access '\(ip)'. Private and reserved IP addresses are not allowed."
            case .embeddedCredentials:
                "URLs with embedded usernames or passwords are not supported for security reasons."
            case .nonASCIIHostname:
                "Please use the ASCII version of this domain (e.g., xn--...)"
            case .invalidIPFormat:
                "The IP address format is invalid"
            }
        }
    }

    // MARK: - Blocked Schemes

    private static let allowedSchemes: Set<String> = ["https", "http"]

    private static let blockedSchemes: Set<String> = [
        "file", "ftp", "ftps", "sftp",
        "data", "javascript", "vbscript",
        "mailto", "tel", "sms",
        "about", "blob", "ws", "wss",
    ]

    // MARK: - Blocked Hostnames

    private static let blockedHostnames: Set<String> = [
        "localhost",
        "localhost.",
    ]

    private static let blockedHostnameSuffixes: [String] = [
        ".localhost",
        ".local",
    ]

    // MARK: - Public API

    /// Validates a URL string for security.
    /// - Parameter urlString: The URL string to validate
    /// - Returns: ValidationResult indicating if URL is valid, requires HTTP confirmation, or is invalid
    static func validate(_ urlString: String) -> ValidationResult {
        // Trim whitespace
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return invalid(.emptyURL)
        }

        // Check for existing scheme BEFORE adding default
        // This prevents ftp://example.com becoming https://ftp://example.com
        var normalizedString = trimmed
        if let schemeRange = trimmed.range(of: "://") {
            let existingScheme = String(trimmed[..<schemeRange.lowerBound]).lowercased()
            if !allowedSchemes.contains(existingScheme) {
                return invalid(.unsupportedScheme(existingScheme))
            }
        } else if let colonIndex = trimmed.firstIndex(of: ":") {
            let possibleScheme = String(trimmed[..<colonIndex]).lowercased()
            if blockedSchemes.contains(possibleScheme) {
                return invalid(.unsupportedScheme(possibleScheme))
            }
            if allowedSchemes.contains(possibleScheme) {
                return invalid(.malformedURL)
            }
            normalizedString = "https://" + normalizedString
        } else {
            normalizedString = "https://" + normalizedString
        }

        // Parse URL
        guard let url = URL(string: normalizedString),
              let scheme = url.scheme?.lowercased()
        else {
            return invalid(.malformedURL)
        }

        // Validate scheme before requiring a host
        if let schemeError = validateScheme(scheme) {
            return invalid(schemeError)
        }

        guard let host = url.host else {
            return invalid(.malformedURL)
        }

        // Check for embedded credentials (user:pass@host)
        if url.user != nil || url.password != nil {
            return invalid(.embeddedCredentials)
        }

        // Normalize host (lowercase, strip trailing dots)
        let normalizedHost = stripTrailingDots(from: host.lowercased())

        // Check for non-ASCII characters (require punycode)
        if !normalizedHost.allSatisfy(\.isASCII) {
            return invalid(.nonASCIIHostname)
        }

        // Validate hostname patterns
        if let hostError = validateHostname(normalizedHost) {
            return invalid(hostError)
        }

        // Check if host is an IP literal
        if isIPAddress(normalizedHost) {
            if let ipError = validateIPAddress(normalizedHost) {
                return invalid(ipError)
            }
        }

        // Reconstruct URL with normalized components
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        components?.host = normalizedHost

        guard let finalURL = components?.url else {
            return invalid(.malformedURL)
        }

        // HTTP requires user confirmation
        if scheme == "http" {
            return .requiresHTTPConfirmation(finalURL, host: normalizedHost)
        }

        return .valid(finalURL)
    }

    private static func invalid(_ error: ValidationError) -> ValidationResult {
        logFailure(error)
        return .invalid(error)
    }

    private static func logFailure(_ error: ValidationError) {
        #if DEBUG
            let reason = switch error {
            case .emptyURL:
                "emptyURL"
            case .malformedURL:
                "malformedURL"
            case .unsupportedScheme:
                "unsupportedScheme"
            case .blockedHost:
                "blockedHost"
            case .blockedIPAddress:
                "blockedIPAddress"
            case .embeddedCredentials:
                "embeddedCredentials"
            case .nonASCIIHostname:
                "nonASCIIHostname"
            case .invalidIPFormat:
                "invalidIPFormat"
            }
            print("[URLValidator] Validation failed: \(reason)")
        #endif
    }

    // MARK: - Scheme Validation

    private static func validateScheme(_ scheme: String) -> ValidationError? {
        if blockedSchemes.contains(scheme) {
            return .unsupportedScheme(scheme)
        }

        if !allowedSchemes.contains(scheme) {
            return .unsupportedScheme(scheme)
        }

        return nil
    }

    // MARK: - Hostname Validation

    private static func validateHostname(_ host: String) -> ValidationError? {
        if host.hasPrefix(".") {
            return .blockedHost(host)
        }

        // Check exact matches
        if blockedHostnames.contains(host) {
            return .blockedHost(host)
        }

        // Check suffix patterns
        for suffix in blockedHostnameSuffixes {
            if host.hasSuffix(suffix) {
                return .blockedHost(host)
            }
        }

        return nil
    }

    private static func stripTrailingDots(from host: String) -> String {
        var trimmed = host
        while trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        return trimmed
    }

    // MARK: - IP Address Detection

    /// Checks if the host string appears to be an IP address (IPv4 or IPv6)
    /// Also detects numeric forms that could be interpreted as IPv4 by resolvers
    static func isIPAddress(_ host: String) -> Bool {
        // IPv6 in brackets
        if host.hasPrefix("["), host.hasSuffix("]") {
            return true
        }

        // Check for IPv4 pattern (digits and dots only, 4 parts)
        let parts = host.split(separator: ".")
        if parts.count == 4, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            return true
        }

        // IPv6 without brackets (contains colons)
        if host.contains(":") {
            return true
        }

        // Detect numeric-only hosts that could be interpreted as IPv4
        // e.g., 2130706433 = 127.0.0.1, 0x7f000001, 017700000001 (octal)
        if isNumericIPv4Form(host) {
            return true
        }

        return false
    }

    /// Detects numeric forms that could be interpreted as IPv4 addresses
    /// Includes decimal integers, hex (0x...), and octal (0...) forms
    private static func isNumericIPv4Form(_ host: String) -> Bool {
        // Pure decimal number (e.g., 2130706433)
        if host.allSatisfy(\.isNumber), !host.isEmpty {
            return true
        }

        // Hex format (0x...)
        if host.lowercased().hasPrefix("0x"),
           host.dropFirst(2).allSatisfy(\.isHexDigit)
        {
            return true
        }

        // Octal format (starts with 0, contains only 0-7)
        if host.hasPrefix("0"), host.count > 1,
           host.allSatisfy({ $0 >= "0" && $0 <= "7" })
        {
            return true
        }

        // Mixed dotted formats with hex/octal (e.g., 0x7f.0.0.1)
        let dotParts = host.split(separator: ".")
        if dotParts.count >= 1, dotParts.count <= 4 {
            let allNumericLike = dotParts.allSatisfy { part in
                let p = String(part).lowercased()
                // Decimal
                if p.allSatisfy(\.isNumber) { return true }
                // Hex
                if p.hasPrefix("0x"), p.dropFirst(2).allSatisfy(\.isHexDigit) { return true }
                // Octal
                if p.hasPrefix("0"), p.count > 1, p.allSatisfy({ $0 >= "0" && $0 <= "7" }) { return true }
                return false
            }
            if allNumericLike, dotParts.count > 1 {
                return true
            }
        }

        return false
    }

    // MARK: - IP Address Validation

    private static func validateIPAddress(_ host: String) -> ValidationError? {
        // Remove brackets for IPv6
        var ip = host
        if ip.hasPrefix("["), ip.hasSuffix("]") {
            ip = String(ip.dropFirst().dropLast())
        }

        // Reject non-standard numeric IPv4 forms outright
        // These are almost exclusively used for SSRF obfuscation
        // e.g., 2130706433, 0x7f000001, 017700000001
        if isNumericIPv4Form(ip) {
            let parts = ip.split(separator: ".")
            // Standard dotted-decimal has 4 parts with no hex/octal prefixes
            let isStandardDotted = parts.count == 4 && parts.allSatisfy { part in
                part.allSatisfy(\.isNumber) && !part.hasPrefix("0x") &&
                    !(part.hasPrefix("0") && part.count > 1)
            }
            if !isStandardDotted {
                return .blockedIPAddress(ip)
            }
        }

        // Try IPv4 first
        if let ipv4Error = validateIPv4(ip) {
            return ipv4Error
        }

        // Try IPv6
        if ip.contains(":") {
            if let ipv6Error = validateIPv6(ip) {
                return ipv6Error
            }
        }

        return nil
    }

    // MARK: - IPv6 Validation

    /// Validates IPv6 address and checks for blocked ranges including tunnel addresses
    private static func validateIPv6(_ ip: String) -> ValidationError? {
        // Parse using inet_pton for strict validation
        var addr = in6_addr()
        guard inet_pton(AF_INET6, ip, &addr) == 1 else {
            return .invalidIPFormat
        }

        // Convert to 128-bit value for range checking
        let bytes = withUnsafeBytes(of: addr.__u6_addr.__u6_addr8) { Array($0) }

        // Check for IPv4-mapped addresses (::ffff:x.x.x.x)
        if isIPv4Mapped(bytes) {
            let ipv4 = extractIPv4FromMapped(bytes)
            if isBlockedIPv4Range(ipv4) {
                return .blockedIPAddress(ip)
            }
            return .blockedIPAddress(ip)
        }

        // Check for NAT64 addresses (64:ff9b::/96) - extract and validate embedded IPv4
        if isNAT64Address(bytes) {
            let ipv4 = extractIPv4FromNAT64(bytes)
            if isBlockedIPv4Range(ipv4) {
                return .blockedIPAddress(ip)
            }
            return nil // Allow NAT64 to public IPs (required for IPv6-only networks)
        }

        // Check for 6to4 addresses (2002::/16) - extract and validate embedded IPv4
        if is6to4Address(bytes) {
            let ipv4 = extractIPv4From6to4(bytes)
            if isBlockedIPv4Range(ipv4) {
                return .blockedIPAddress(ip)
            }
            return nil
        }

        // Check for Teredo addresses (2001:0000::/32) - extract and validate embedded IPv4
        if isTeredoAddress(bytes) {
            let ipv4 = extractIPv4FromTeredo(bytes)
            if isBlockedIPv4Range(ipv4) {
                return .blockedIPAddress(ip)
            }
            return nil
        }

        // Check blocked IPv6 ranges
        if isBlockedIPv6Range(bytes) {
            return .blockedIPAddress(ip)
        }

        return nil
    }

    // MARK: - IPv6 Range Checks

    /// Checks if IPv6 address is in a blocked range
    private static func isBlockedIPv6Range(_ bytes: [UInt8]) -> Bool {
        // ::/128 - Unspecified
        if bytes.allSatisfy({ $0 == 0 }) {
            return true
        }

        // ::1/128 - Loopback
        if bytes[0 ... 14].allSatisfy({ $0 == 0 }), bytes[15] == 1 {
            return true
        }

        // ::/96 - IPv4-compatible (deprecated)
        if bytes[0 ... 11].allSatisfy({ $0 == 0 }) {
            return true
        }

        // fe80::/10 - Link-local
        if bytes[0] == 0xFE, (bytes[1] & 0xC0) == 0x80 {
            return true
        }

        // fc00::/7 - Unique local (ULA)
        if (bytes[0] & 0xFE) == 0xFC {
            return true
        }

        // ff00::/8 - Multicast
        if bytes[0] == 0xFF {
            return true
        }

        // 100::/64 - Discard-only
        if bytes[0] == 0x01, bytes[1] == 0x00,
           bytes[2 ... 7].allSatisfy({ $0 == 0 })
        {
            return true
        }

        // 2001:db8::/32 - Documentation
        if bytes[0] == 0x20, bytes[1] == 0x01,
           bytes[2] == 0x0D, bytes[3] == 0xB8
        {
            return true
        }

        // 2001:10::/28 - ORCHID (deprecated)
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x00,
           (bytes[3] & 0xF0) == 0x10
        {
            return true
        }

        // 2001:2::/48 - Benchmarking
        if bytes[0] == 0x20, bytes[1] == 0x01,
           bytes[2] == 0x00, bytes[3] == 0x02,
           bytes[4] == 0x00, bytes[5] == 0x00
        {
            return true
        }

        return false
    }

    // MARK: - Tunnel Address Detection

    /// IPv4-mapped: ::ffff:x.x.x.x
    private static func isIPv4Mapped(_ bytes: [UInt8]) -> Bool {
        bytes[0 ... 9].allSatisfy { $0 == 0 } &&
            bytes[10] == 0xFF && bytes[11] == 0xFF
    }

    private static func extractIPv4FromMapped(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[12]) << 24 |
            UInt32(bytes[13]) << 16 |
            UInt32(bytes[14]) << 8 |
            UInt32(bytes[15])
    }

    /// NAT64: 64:ff9b::/96
    private static func isNAT64Address(_ bytes: [UInt8]) -> Bool {
        bytes[0] == 0x00 && bytes[1] == 0x64 &&
            bytes[2] == 0xFF && bytes[3] == 0x9B &&
            bytes[4 ... 11].allSatisfy { $0 == 0 }
    }

    private static func extractIPv4FromNAT64(_ bytes: [UInt8]) -> UInt32 {
        // Last 32 bits contain IPv4
        UInt32(bytes[12]) << 24 |
            UInt32(bytes[13]) << 16 |
            UInt32(bytes[14]) << 8 |
            UInt32(bytes[15])
    }

    /// 6to4: 2002::/16 - IPv4 embedded in bits 16-47
    private static func is6to4Address(_ bytes: [UInt8]) -> Bool {
        bytes[0] == 0x20 && bytes[1] == 0x02
    }

    private static func extractIPv4From6to4(_ bytes: [UInt8]) -> UInt32 {
        // IPv4 in bytes 2-5
        UInt32(bytes[2]) << 24 |
            UInt32(bytes[3]) << 16 |
            UInt32(bytes[4]) << 8 |
            UInt32(bytes[5])
    }

    /// Teredo: 2001:0000::/32 - IPv4 embedded (obfuscated) in last 32 bits
    private static func isTeredoAddress(_ bytes: [UInt8]) -> Bool {
        bytes[0] == 0x20 && bytes[1] == 0x01 &&
            bytes[2] == 0x00 && bytes[3] == 0x00
    }

    private static func extractIPv4FromTeredo(_ bytes: [UInt8]) -> UInt32 {
        // Teredo client IPv4 is XOR'd with 0xFFFFFFFF in last 32 bits
        let obfuscated = UInt32(bytes[12]) << 24 |
            UInt32(bytes[13]) << 16 |
            UInt32(bytes[14]) << 8 |
            UInt32(bytes[15])
        return obfuscated ^ 0xFFFF_FFFF
    }

    /// Validates IPv4 address using strict parsing and checks for blocked ranges
    private static func validateIPv4(_ ip: String) -> ValidationError? {
        // Only process if it looks like IPv4
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }

        // Use inet_pton for strict parsing (rejects octal, hex, partial forms)
        var addr = in_addr()
        guard inet_pton(AF_INET, ip, &addr) == 1 else {
            // If it looks like IPv4 but fails parsing, reject it
            if parts.allSatisfy({ $0.allSatisfy { $0.isNumber || $0 == "x" || $0 == "X" } }) {
                return .invalidIPFormat
            }
            return nil
        }

        // Convert to host byte order for range checking
        let ipNum = UInt32(bigEndian: addr.s_addr)

        // Check blocked ranges
        if isBlockedIPv4Range(ipNum) {
            return .blockedIPAddress(ip)
        }

        return nil
    }

    /// Checks if an IPv4 address (in host byte order) is in a blocked range
    private static func isBlockedIPv4Range(_ ip: UInt32) -> Bool {
        if isIPv4InRange(ip, base: 0x0000_0000, mask: 0xFF00_0000) { return true } // 0.0.0.0/8
        if isIPv4InRange(ip, base: 0x0A00_0000, mask: 0xFF00_0000) { return true } // 10.0.0.0/8
        if isIPv4InRange(ip, base: 0x6440_0000, mask: 0xFFC0_0000) { return true } // 100.64.0.0/10
        if isIPv4InRange(ip, base: 0x7F00_0000, mask: 0xFF00_0000) { return true } // 127.0.0.0/8
        if isIPv4InRange(ip, base: 0xA9FE_0000, mask: 0xFFFF_0000) { return true } // 169.254.0.0/16
        if isIPv4InRange(ip, base: 0xAC10_0000, mask: 0xFFF0_0000) { return true } // 172.16.0.0/12
        if isIPv4InRange(ip, base: 0xC000_0000, mask: 0xFFFF_FF00) { return true } // 192.0.0.0/24
        if isIPv4InRange(ip, base: 0xC0A8_0000, mask: 0xFFFF_0000) { return true } // 192.168.0.0/16
        if isIPv4InRange(ip, base: 0xC612_0000, mask: 0xFFFE_0000) { return true } // 198.18.0.0/15
        if isIPv4InRange(ip, base: 0xE000_0000, mask: 0xF000_0000) { return true } // 224.0.0.0/4
        if isIPv4InRange(ip, base: 0xF000_0000, mask: 0xF000_0000) { return true } // 240.0.0.0/4

        return false
    }

    private static func isIPv4InRange(_ ip: UInt32, base: UInt32, mask: UInt32) -> Bool {
        (ip & mask) == base
    }
}
