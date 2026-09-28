import ComposableArchitecture
import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class ATAClientReadTests: XCTestCase {
    func testAllReadOperationsUseExactRoutesAndMappedResults() async throws {
        let probe = ATAHTTPProbe { request in
            let body: String
            switch request.url!.path {
            case "/v1/portfolio": body = ATAFoundationFixtures.portfolio
            case "/v1/analyses": body = ATAFoundationFixtures.list
            default: body = ATAFoundationFixtures.detail
            }
            return ATAClientTestSupport.response(request, body: body)
        }
        let client = try ATAClientTestSupport.client(probe)
        let portfolio = try await client.loadPortfolio()
        let latest = try await client.loadLatestAnalysis()
        let recent = try await client.loadAnalyses(17)
        let detail = try await client.loadAnalysis(ATAClientTestSupport.id)
        XCTAssertEqual(portfolio.accounts.count, 2)
        XCTAssertEqual(portfolio.revision, 7)
        XCTAssertEqual(
            portfolio.accounts[0].positions[0].amount,
            try ATADecimalCodec.decode("0.12345678901234567890123456789012345678"))
        XCTAssertEqual(latest.result?.reasoningMode, .aiAssisted)
        XCTAssertEqual(detail, latest)
        XCTAssertEqual(recent.analyses.count, 2)
        let requests = await probe.requests
        XCTAssertEqual(
            requests.map { $0.url!.path },
            [
                "/v1/portfolio", "/v1/analyses/latest", "/v1/analyses",
                "/v1/analyses/" + ATAClientTestSupport.idPath,
            ])
        for (index, request) in requests.enumerated() {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.host, "ata.example.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertTrue(
                request.value(forHTTPHeaderField: "Authorization") == "Bearer "
                    + ATAClientTestSupport.secret)
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
            XCTAssertFalse(request.url!.absoluteString.contains(ATAClientTestSupport.secret))
            XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
            XCTAssertEqual(request.timeoutInterval, 60)
            XCTAssertEqual(request.url?.query, index == 2 ? "limit=17" : nil)
        }
    }

    func testMissingCredentialStopsBeforeTransport() async throws {
        let probe = ATAHTTPProbe()
        var credentials = ATAClientTestSupport.credentials
        credentials.load = { throw CredentialStoreError.tokenAbsent }
        let client = try ATAClientTestSupport.client(probe, credentials: credentials)
        await expect(.missingCredential) { _ = try await client.loadPortfolio() }
        let requests = await probe.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCredentialFailureIsSanitizedBeforeTransport() async throws {
        let probe = ATAHTTPProbe()
        var credentials = ATAClientTestSupport.credentials
        credentials.load = { throw NSError(domain: ATAClientTestSupport.secret, code: 99) }
        let client = try ATAClientTestSupport.client(probe, credentials: credentials)
        await expect(.credentialUnavailable) { _ = try await client.loadPortfolio() }
        let requests = await probe.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testTokenIsReloadedForEachRequest() async throws {
        actor Tokens {
            var count = 0
            func load() throws -> ATABearerToken {
                count += 1
                return try ATABearerToken("synthetic-rotation-\(count)")
            }
        }
        let tokens = Tokens()
        var credentials = ATAClientTestSupport.credentials
        credentials.load = { try await tokens.load() }
        let probe = ATAHTTPProbe()
        let client = try ATAClientTestSupport.client(probe, credentials: credentials)
        _ = try await client.loadPortfolio()
        _ = try await client.loadPortfolio()
        let requests = await probe.requests
        XCTAssertTrue(
            requests[0].value(forHTTPHeaderField: "Authorization")
                != requests[1].value(forHTTPHeaderField: "Authorization"))
        let count = await tokens.count
        XCTAssertEqual(count, 2)
    }

    func testInvalidConfigurationNeverUsesCPAFallback() {
        for url in [
            nil, "", "http://public.example.com", "https://127.0.0.2",
            "https://localhost.", "https://[::1]",
        ] as [String?] {
            XCTAssertThrowsError(
                try ATAClient.live(
                    configuredBaseURL: url, environment: .release,
                    credentials: ATAClientTestSupport.credentials,
                    transport: ATAHTTPProbe().transport)
            ) {
                XCTAssertEqual($0 as? ATAClientError, .invalidConfiguration)
            }
        }
    }

    func testDebugLocalOriginAndBasePathArePreserved() async throws {
        let probe = ATAHTTPProbe()
        let client = try ATAClient.live(
            configuredBaseURL: "http://127.0.0.2:8000/api",
            environment: .debug, credentials: ATAClientTestSupport.credentials,
            transport: probe.transport)
        _ = try await client.loadPortfolio()
        let requests = await probe.requests
        XCTAssertEqual(requests[0].url?.absoluteString, "http://127.0.0.2:8000/api/v1/portfolio")
    }

    func testInvalidLimitAndNilUUIDAreLocalFailures() async throws {
        let probe = ATAHTTPProbe()
        let client = try ATAClientTestSupport.client(probe)
        for limit in [0, -1] {
            await expect(.invalidRequest) { _ = try await client.loadAnalyses(limit) }
        }
        await expect(.invalidRequest) {
            _ = try await client.loadAnalysis(
                UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        }
        let requests = await probe.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testTimeoutConnectionAndCancellationAreDistinctWithoutRetry() async throws {
        for (code, expected) in [
            (URLError.timedOut, ATAClientError.transport(.timeout)),
            (.notConnectedToInternet, .transport(.connection)), (.cancelled, .cancelled),
        ] {
            let probe = ATAHTTPProbe { _ in
                throw URLError(
                    code, userInfo: [NSLocalizedDescriptionKey: ATAClientTestSupport.secret])
            }
            let client = try ATAClientTestSupport.client(probe)
            await expect(expected) { _ = try await client.loadPortfolio() }
            let requests = await probe.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testMalformedAndIncompatibleSuccessResponsesAreRejected() async throws {
        let bodies = [
            "not JSON",
            ATAFoundationFixtures.portfolio.replacingOccurrences(of: "binance", with: "future"),
            ATAFoundationFixtures.portfolio.replacingOccurrences(of: "\"3.4503\"", with: "\"1e3\""),
            ATAFoundationFixtures.portfolio.replacingOccurrences(
                of: "2026-09-25T12:00:03.000000Z", with: "not-a-date"),
        ]
        for body in bodies {
            let probe = ATAHTTPProbe { ATAClientTestSupport.response($0, body: body) }
            let client = try ATAClientTestSupport.client(probe)
            await expect(.invalidResponse) { _ = try await client.loadPortfolio() }
        }
    }

    func testSemanticErrorsAndUnknownCodesRemainDistinct() async throws {
        for (status, code) in [
            (401, "unauthorized"), (404, "portfolio_not_found"),
            (404, "analysis_not_found"), (422, "invalid_request"), (500, "future_code"),
        ] {
            let body =
                "{\"error\":{\"code\":\"\(code)\",\"message\":\"\(ATAClientTestSupport.secret)\"}}"
            let probe = ATAHTTPProbe {
                ATAClientTestSupport.response($0, status: status, body: body)
            }
            let client = try ATAClientTestSupport.client(probe)
            await expect(
                .http(
                    ATAHTTPFailure(
                        statusCode: status,
                        error: ATAServiceError(
                            code: code, message: "ATA rejected the request.", reloadRequired: nil)))
            ) {
                _ = try await client.loadPortfolio()
            }
        }
    }

    func testMalformedErrorRedirectNonHTTPAndUnexpectedOriginAreSanitized() async throws {
        let handlers: [@Sendable (URLRequest) async throws -> (Data, URLResponse)] = [
            { ATAClientTestSupport.response($0, status: 500, body: ATAClientTestSupport.secret) },
            { ATAClientTestSupport.response($0, status: 302, body: "") },
            { ATAClientTestSupport.response($0, status: 201) },
            {
                (
                    Data(),
                    URLResponse(
                        url: $0.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil
                    )
                )
            },
            { _ in
                (
                    Data(ATAFoundationFixtures.portfolio.utf8),
                    HTTPURLResponse(
                        url: URL(string: "https://other.example.com")!, statusCode: 200,
                        httpVersion: nil, headerFields: nil)!
                )
            },
        ]
        for handler in handlers {
            let probe = ATAHTTPProbe(handler: handler)
            let client = try ATAClientTestSupport.client(probe)
            await expect(.invalidResponse) { _ = try await client.loadPortfolio() }
        }
    }

    func testEchoedTokenCannotEscapeInErrorCodeOrDescription() async throws {
        let body =
            "{\"error\":{\"code\":\"\(ATAClientTestSupport.secret)\",\"message\":\"\(ATAClientTestSupport.secret)\"}}"
        let probe = ATAHTTPProbe { ATAClientTestSupport.response($0, status: 401, body: body) }
        let client = try ATAClientTestSupport.client(probe)
        do {
            _ = try await client.loadPortfolio()
            XCTFail("Expected error")
        } catch let error as ATAClientError {
            guard case .http(let failure) = error else { return XCTFail("Expected HTTP error") }
            XCTAssertNil(failure.error.knownCode)
            XCTAssertFalse(failure.error.code.contains(ATAClientTestSupport.secret))
            XCTAssertFalse(failure.error.message.contains(ATAClientTestSupport.secret))
            assertSanitized(error)
        }
    }

    func testUnconfiguredTCAClientDoesNotPerformIO() async {
        await expect(.invalidConfiguration) {
            try await withDependencies {
                $0.ataClient = .testValue
            } operation: {
                @Dependency(\.ataClient) var client
                _ = try await client.loadPortfolio()
            }
        }
    }

    private func expect(_ expected: ATAClientError, operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected client failure")
        } catch {
            XCTAssertEqual(error as? ATAClientError, expected)
            if let error = error as? ATAClientError { assertSanitized(error) }
        }
    }

    private func assertSanitized(_ error: ATAClientError) {
        for text in [
            String(describing: error), String(reflecting: error), error.localizedDescription,
        ] {
            XCTAssertFalse(text.contains(ATAClientTestSupport.secret))
        }
        XCTAssertFalse(
            Mirror(reflecting: error).children.contains {
                String(describing: $0.value).contains(ATAClientTestSupport.secret)
            })
    }
}
