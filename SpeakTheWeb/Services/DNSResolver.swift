import Darwin
import Foundation

/// DNS resolver with security validation for preventing SSRF/DNS rebinding attacks.
/// Resolves hostnames and validates all returned IP addresses against blocked ranges.
enum DNSResolver {
    // MARK: - Resolution Result

    enum ResolutionResult {
        case resolved([String])
        case allBlocked(String)
        case failed(ResolutionError)
    }

    enum ResolutionError: LocalizedError {
        case dnsFailure
        case invalidHostname
        case timeout

        var errorDescription: String? {
            switch self {
            case .dnsFailure:
                "Unable to reach this website. Please check the URL and try again."
            case .invalidHostname:
                "The hostname could not be resolved."
            case .timeout:
                "DNS lookup timed out. Please try again."
            }
        }
    }

    // MARK: - Configuration

    private static let maxRetries = 2
    private static let baseDelayMs: UInt64 = 1_000_000_000 // 1 second in nanoseconds

    // MARK: - Public API

    /// Resolves a hostname and validates all returned IPs.
    /// Returns success only if at least one resolved IP is public (not blocked).
    /// - Parameter hostname: The hostname to resolve
    /// - Returns: ResolutionResult with list of valid public IPs, or error
    /// - Note: This runs DNS resolution on a background thread to avoid blocking the main actor.
    static func resolve(_ hostname: String) async -> ResolutionResult {
        // Skip resolution for IP literals - they're validated directly by URLValidator
        if URLValidator.isIPAddress(hostname) {
            return .resolved([hostname])
        }

        // Run DNS resolution on a background thread to avoid blocking the main actor
        // getaddrinfo is a synchronous blocking call that can take seconds on slow networks
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = resolveWithRetries(hostname)
                continuation.resume(returning: result)
            }
        }
    }

    /// Performs DNS resolution with retries. Called on a background thread.
    private static func resolveWithRetries(_ hostname: String) -> ResolutionResult {
        var lastError: ResolutionError = .dnsFailure

        for attempt in 0 ... maxRetries {
            if attempt > 0 {
                // Exponential backoff: 1s, 2s (blocking sleep on background thread)
                let delaySeconds = UInt32(1 << (attempt - 1))
                sleep(delaySeconds)
            }

            let result = performResolution(hostname)

            switch result {
            case .resolved, .allBlocked:
                return result
            case let .failed(error):
                lastError = error
                logResolutionFailure(hostname: hostname, attempt: attempt, error: error)
                continue
            }
        }

        return .failed(lastError)
    }

    /// Validates a resolved IP address string.
    /// Used for post-connect validation of the actual connected IP.
    /// - Parameter ipString: The IP address string to validate
    /// - Returns: true if the IP is allowed (public), false if blocked
    static func isAllowedIP(_ ipString: String) -> Bool {
        // Normalize the IP string (remove brackets from IPv6, etc.)
        var ip = ipString
        if ip.hasPrefix("["), ip.hasSuffix("]") {
            ip = String(ip.dropFirst().dropLast())
        }

        // Try IPv4 validation
        var ipv4Addr = in_addr()
        if inet_pton(AF_INET, ip, &ipv4Addr) == 1 {
            let ipNum = UInt32(bigEndian: ipv4Addr.s_addr)
            return !isBlockedIPv4(ipNum)
        }

        // Try IPv6 validation
        var ipv6Addr = in6_addr()
        if inet_pton(AF_INET6, ip, &ipv6Addr) == 1 {
            let bytes = withUnsafeBytes(of: ipv6Addr.__u6_addr.__u6_addr8) { Array($0) }
            return !isBlockedIPv6(bytes)
        }

        // If we can't parse it, fail closed
        return false
    }

    // MARK: - Private Resolution

    private static func performResolution(_ hostname: String) -> ResolutionResult {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC // Allow both IPv4 and IPv6
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_ADDRCONFIG // Only return addresses that make sense for this system

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostname, nil, &hints, &result)

        guard status == 0, let addrList = result else {
            return .failed(.dnsFailure)
        }

        defer { freeaddrinfo(addrList) }

        var allIPs: [String] = []
        var publicIPs: [String] = []
        var blockedCount = 0

        var current: UnsafeMutablePointer<addrinfo>? = addrList
        while let addr = current {
            if let ipString = extractIPString(from: addr.pointee) {
                allIPs.append(ipString)

                if isAllowedIP(ipString) {
                    publicIPs.append(ipString)
                } else {
                    blockedCount += 1
                    logBlockedIP(hostname: hostname, ip: ipString)
                }
            }
            current = addr.pointee.ai_next
        }

        // No IPs resolved at all
        if allIPs.isEmpty {
            return .failed(.invalidHostname)
        }

        // All IPs are blocked
        if publicIPs.isEmpty {
            return .allBlocked(
                "All resolved IP addresses for '\(hostname)' are in blocked ranges."
            )
        }

        // At least one public IP - allow the connection
        return .resolved(publicIPs)
    }

    private static func extractIPString(from addr: addrinfo) -> String? {
        switch addr.ai_family {
        case AF_INET:
            var ipString = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let sockAddr = addr.ai_addr!.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0 }
            var sin_addr = sockAddr.pointee.sin_addr
            guard inet_ntop(AF_INET, &sin_addr, &ipString, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: ipString)

        case AF_INET6:
            var ipString = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let sockAddr = addr.ai_addr!.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0 }
            var sin6_addr = sockAddr.pointee.sin6_addr
            guard inet_ntop(AF_INET6, &sin6_addr, &ipString, socklen_t(INET6_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: ipString)

        default:
            return nil
        }
    }

    // MARK: - IP Validation (mirrors URLValidator logic)

    private static func isBlockedIPv4(_ ip: UInt32) -> Bool {
        // 0.0.0.0/8 - Current network
        if (ip & 0xFF00_0000) == 0x0000_0000 { return true }
        // 10.0.0.0/8 - Private
        if (ip & 0xFF00_0000) == 0x0A00_0000 { return true }
        // 100.64.0.0/10 - Carrier-grade NAT
        if (ip & 0xFFC0_0000) == 0x6440_0000 { return true }
        // 127.0.0.0/8 - Loopback
        if (ip & 0xFF00_0000) == 0x7F00_0000 { return true }
        // 169.254.0.0/16 - Link-local
        if (ip & 0xFFFF_0000) == 0xA9FE_0000 { return true }
        // 172.16.0.0/12 - Private
        if (ip & 0xFFF0_0000) == 0xAC10_0000 { return true }
        // 192.0.0.0/24 - IETF protocol assignments
        if (ip & 0xFFFF_FF00) == 0xC000_0000 { return true }
        // 192.168.0.0/16 - Private
        if (ip & 0xFFFF_0000) == 0xC0A8_0000 { return true }
        // 198.18.0.0/15 - Benchmarking
        if (ip & 0xFFFE_0000) == 0xC612_0000 { return true }
        // 224.0.0.0/4 - Multicast
        if (ip & 0xF000_0000) == 0xE000_0000 { return true }
        // 240.0.0.0/4 - Reserved
        if (ip & 0xF000_0000) == 0xF000_0000 { return true }

        return false
    }

    private static func isBlockedIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }

        // ::/128 - Unspecified
        if bytes.allSatisfy({ $0 == 0 }) { return true }

        // ::1/128 - Loopback
        if bytes[0 ... 14].allSatisfy({ $0 == 0 }), bytes[15] == 1 { return true }

        // ::/96 - IPv4-compatible (deprecated)
        if bytes[0 ... 11].allSatisfy({ $0 == 0 }) { return true }

        // ::ffff:0:0/96 - IPv4-mapped - check the embedded IPv4
        if bytes[0 ... 9].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
            let ipv4 = extractIPv4FromMapped(bytes)
            return isBlockedIPv4(ipv4)
        }

        // 64:ff9b::/96 - NAT64 - extract and validate embedded IPv4
        if bytes[0] == 0x00, bytes[1] == 0x64, bytes[2] == 0xFF, bytes[3] == 0x9B,
           bytes[4 ... 11].allSatisfy({ $0 == 0 })
        {
            let ipv4 = extractIPv4FromLast32(bytes)
            return isBlockedIPv4(ipv4)
        }

        // 2002::/16 - 6to4 - extract and validate embedded IPv4
        if bytes[0] == 0x20, bytes[1] == 0x02 {
            let ipv4 = extractIPv4From6to4(bytes)
            return isBlockedIPv4(ipv4)
        }

        // 2001:0000::/32 - Teredo - extract and validate embedded IPv4 (XOR'd)
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x00, bytes[3] == 0x00 {
            let ipv4 = extractIPv4FromTeredo(bytes)
            return isBlockedIPv4(ipv4)
        }

        // fe80::/10 - Link-local
        if bytes[0] == 0xFE, (bytes[1] & 0xC0) == 0x80 { return true }

        // fc00::/7 - Unique local (ULA)
        if (bytes[0] & 0xFE) == 0xFC { return true }

        // ff00::/8 - Multicast
        if bytes[0] == 0xFF { return true }

        // 100::/64 - Discard-only
        if bytes[0] == 0x01, bytes[1] == 0x00, bytes[2 ... 7].allSatisfy({ $0 == 0 }) { return true }

        // 2001:db8::/32 - Documentation
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0D, bytes[3] == 0xB8 { return true }

        // 2001:10::/28 - ORCHID (deprecated)
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x00, (bytes[3] & 0xF0) == 0x10 { return true }

        // 2001:2::/48 - Benchmarking
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x00, bytes[3] == 0x02,
           bytes[4] == 0x00, bytes[5] == 0x00
        { return true }

        return false
    }

    // MARK: - IPv4 Extraction Helpers

    private static func extractIPv4FromMapped(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[12]) << 24 | UInt32(bytes[13]) << 16 |
            UInt32(bytes[14]) << 8 | UInt32(bytes[15])
    }

    private static func extractIPv4FromLast32(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[12]) << 24 | UInt32(bytes[13]) << 16 |
            UInt32(bytes[14]) << 8 | UInt32(bytes[15])
    }

    private static func extractIPv4From6to4(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[2]) << 24 | UInt32(bytes[3]) << 16 |
            UInt32(bytes[4]) << 8 | UInt32(bytes[5])
    }

    private static func extractIPv4FromTeredo(_ bytes: [UInt8]) -> UInt32 {
        let obfuscated = UInt32(bytes[12]) << 24 | UInt32(bytes[13]) << 16 |
            UInt32(bytes[14]) << 8 | UInt32(bytes[15])
        return obfuscated ^ 0xFFFF_FFFF
    }

    // MARK: - Logging

    private static func logResolutionFailure(hostname: String, attempt: Int, error: ResolutionError) {
        #if DEBUG
            print("[DNSResolver] Resolution failed for hostname (attempt \(attempt + 1)/\(maxRetries + 1)): \(error)")
        #endif
    }

    private static func logBlockedIP(hostname: String, ip: String) {
        #if DEBUG
            print("[DNSResolver] Blocked IP resolved for hostname: \(ip)")
        #endif
    }
}
