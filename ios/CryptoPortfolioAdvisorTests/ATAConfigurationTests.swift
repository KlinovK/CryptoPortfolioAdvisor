import XCTest

@testable import CryptoPortfolioAdvisor

final class ATAConfigurationTests: XCTestCase {
    func testReleaseAcceptsPublicHTTPS() throws {
        for text in [
            "https://advisor.example.com", "https://advisor.example.com/api",
            "https://8.8.8.8", "https://[2001:4860:4860::8888]",
        ] {
            XCTAssertEqual(
                try ATAAPIConfiguration.baseURL(configuredValue: text, environment: .release)
                    .absoluteString, text)
        }
    }

    func testDebugAllowsLocalDevelopmentTargets() throws {
        for host in ["localhost", "localhost.", "127.0.0.1", "127.0.0.2", "[::1]", "192.168.1.2"] {
            XCTAssertNoThrow(
                try ATAAPIConfiguration.baseURL(
                    configuredValue: "http://\(host):8000", environment: .debug))
        }
    }

    func testReleaseRejectsEntireLoopbackAndAliasFamilies() {
        for host in [
            "localhost", "LOCALHOST.", "dev.localhost", "127.0.0.1", "127.0.0.2",
            "127.255.255.255", "127.1", "2130706433", "0x7f000001", "[::1]",
            "[0:0:0:0:0:0:0:1]", "[::ffff:127.0.0.2]", "[::ffff:7f00:1]",
        ] {
            XCTAssertThrowsError(
                try ATAAPIConfiguration.baseURL(
                    configuredValue: "https://\(host)", environment: .release), host
            ) {
                XCTAssertEqual($0 as? ATAAPIConfigurationError, .localReleaseURL)
            }
        }
    }

    func testReleaseRejectsPrivateAndLocalTargets() {
        for host in [
            "mac.local", "localhost.localdomain", "advisor", "10.0.0.1", "172.16.0.1",
            "192.168.1.1",
            "169.254.1.1", "0.0.0.0", "[::]", "[fe80::1]", "[fc00::1]",
        ] {
            XCTAssertThrowsError(
                try ATAAPIConfiguration.baseURL(
                    configuredValue: "https://\(host)", environment: .release))
        }
    }

    func testReleaseRejectsHTTPIncludingPublicHosts() {
        for text in ["http://localhost", "http://127.0.0.2", "http://advisor.example.com"] {
            XCTAssertThrowsError(
                try ATAAPIConfiguration.baseURL(configuredValue: text, environment: .release)
            ) {
                XCTAssertEqual($0 as? ATAAPIConfigurationError, .insecureReleaseURL)
            }
        }
    }

    func testMalformedOrUnexpectedComponentsAreRejected() {
        for text in [
            "not a url", "https:///", "https://", "ftp://example.com",
            "https://user:password@example.com", "https://example.com?query=1",
            "https://example.com#fragment", "https://example.com:0",
            "https://example.com:65536", "https://example .com",
        ] {
            XCTAssertThrowsError(
                try ATAAPIConfiguration.baseURL(configuredValue: text, environment: .debug), text)
        }
    }

    func testMissingConfigurationNeverFallsBackToCPA() {
        for environment in [ATAAPIEnvironment.debug, .release] {
            for text: String? in [nil, "", "  "] {
                XCTAssertThrowsError(
                    try ATAAPIConfiguration.baseURL(configuredValue: text, environment: environment)
                ) {
                    XCTAssertEqual($0 as? ATAAPIConfigurationError, .missingBaseURL)
                }
            }
        }
        XCTAssertEqual(ATAAPIConfiguration.infoDictionaryKey, "ATA_BACKEND_BASE_URL")
    }
}
