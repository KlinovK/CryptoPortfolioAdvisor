import Darwin
import Foundation

enum ATAAPIEnvironment: Sendable {
    case debug
    case release
}

enum ATAAPIConfigurationError: Error, Equatable, Sendable {
    case missingBaseURL
    case invalidBaseURL
    case insecureReleaseURL
    case localReleaseURL
}

enum ATAAPIConfiguration {
    // Reserved for future build-setting-backed configuration. Not read by the app yet.
    static let infoDictionaryKey = "ATA_BACKEND_BASE_URL"

    static func baseURL(configuredValue: String?, environment: ATAAPIEnvironment) throws -> URL {
        guard let text = configuredValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { throw ATAAPIConfigurationError.missingBaseURL }
        guard !text.contains(where: \.isWhitespace),
            let parts = URLComponents(string: text),
            let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = parts.host, !host.isEmpty,
            parts.user == nil, parts.password == nil,
            parts.query == nil, parts.fragment == nil,
            parts.port.map({ (1...65535).contains($0) }) ?? true,
            let url = parts.url
        else { throw ATAAPIConfigurationError.invalidBaseURL }
        if environment == .release {
            guard scheme == "https" else { throw ATAAPIConfigurationError.insecureReleaseURL }
            guard !isLocal(host) else { throw ATAAPIConfigurationError.localReleaseURL }
        }
        return url
    }

    private static func isLocal(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        // Scoped/encoded local addresses are not Release hosts.
        if host.contains("%") { return true }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
            || host.hasSuffix(".localdomain")
            || host.hasSuffix(".internal") || host.hasSuffix(".lan") || host.hasSuffix(".home")
        {
            return true
        }
        // inet_aton also recognizes numeric IPv4 aliases (127.1, decimal/hex literals).
        // These are pure address parsers: no DNS lookup or socket is performed.
        var ipv4 = in_addr()
        if host.withCString({ inet_aton($0, &ipv4) }) == 1 {
            return withUnsafeBytes(of: ipv4) { localIPv4(Array($0)) }
        }
        var ipv6 = in6_addr()
        if host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            let bytes = withUnsafeBytes(of: ipv6) { Array($0) }
            if bytes.prefix(12).allSatisfy({ $0 == 0 }) {
                return localIPv4(Array(bytes.suffix(4)))  // Unspecified, loopback, compatible IPv4.
            }
            if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
                return localIPv4(Array(bytes.suffix(4)))
            }
            return bytes[0] & 0xfe == 0xfc || bytes[0] == 0xff
                || (bytes[0] == 0xfe && bytes[1] & 0xc0 != 0)
        }
        // Unqualified names and malformed IP literals cannot be production hosts.
        return !host.contains(".") || host.contains(":")
    }

    private static func localIPv4(_ bytes: [UInt8]) -> Bool {
        let a = bytes[0]
        let b = bytes[1]
        return a == 0 || a == 10 || a == 127 || a >= 224
            || (a == 169 && b == 254) || (a == 172 && (16...31).contains(b))
            || (a == 192 && b == 168) || (a == 100 && (64...127).contains(b))
    }
}
