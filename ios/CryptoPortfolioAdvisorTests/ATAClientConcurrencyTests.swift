import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class ATAClientConcurrencyTests: XCTestCase {
    func testPreCancelledReadAndMutationNeverReachTransport() async throws {
        for mutation in [false, true] {
            let probe = ATAHTTPProbe()
            let client = try ATAClientTestSupport.client(probe)
            let task = Task { try await operation(client, mutation: mutation) }
            task.cancel()
            do {
                try await task.value
                XCTFail("Expected cancellation")
            } catch { XCTAssertEqual(error as? ATAClientError, .cancelled) }
            let requests = await probe.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testInFlightCancellationPropagatesAndMutationIsUncertain() async throws {
        for mutation in [false, true] {
            let (started, signal) = AsyncStream<Void>.makeStream()
            let probe = ATAHTTPProbe { _ in
                signal.yield()
                try await Task.sleep(for: .seconds(30))
                throw URLError(.timedOut)
            }
            let client = try ATAClientTestSupport.client(probe)
            let task = Task { try await operation(client, mutation: mutation) }
            var iterator = started.makeAsyncIterator()
            _ = await iterator.next()
            task.cancel()
            do {
                try await task.value
                XCTFail("Expected cancellation")
            } catch {
                XCTAssertEqual(
                    error as? ATAClientError,
                    mutation ? .uncertainMutationOutcome(.cancelled) : .cancelled)
            }
            signal.finish()
            let requests = await probe.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testCredentialLoadCancellationIsLocalEvenForMutation() async throws {
        let (started, signal) = AsyncStream<Void>.makeStream()
        var credentials = ATAClientTestSupport.credentials
        credentials.load = {
            signal.yield()
            try await Task.sleep(for: .seconds(30))
            throw CredentialStoreError.readFailed
        }
        let probe = ATAHTTPProbe()
        let client = try ATAClientTestSupport.client(probe, credentials: credentials)
        let task = Task { try await operation(client, mutation: true) }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertEqual(error as? ATAClientError, .cancelled) }
        signal.finish()
        let requests = await probe.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCancellationOnResponseDoesNotImplyMutationRollback() async throws {
        let probe = ATAHTTPProbe { request in
            withUnsafeCurrentTask { $0?.cancel() }
            return ATAClientTestSupport.response(request)
        }
        let client = try ATAClientTestSupport.client(probe)
        let task = Task { try await operation(client, mutation: true) }
        do {
            try await task.value
            XCTFail("Expected uncertain cancellation")
        } catch { XCTAssertEqual(error as? ATAClientError, .uncertainMutationOutcome(.cancelled)) }
    }

    func testRedirectDelegateRejectsSameAndCrossOriginBeforeForwarding() async throws {
        let session = URLSession(configuration: ATAURLSessionTransport.configuration())
        defer { session.invalidateAndCancel() }
        let url = URL(string: ATAClientTestSupport.baseURL + "/v1/portfolio")!
        let task = session.dataTask(with: url)  // Suspended forever: no network request.
        let delegate = ATARedirectDelegate()
        for target in [
            "https://ata.example.com/other", "https://other.example.com/steal",
            "http://ata.example.com/v1/portfolio",
        ] {
            var proposed = URLRequest(url: URL(string: target)!)
            proposed.setValue(
                "Bearer " + ATAClientTestSupport.secret, forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(
                url: url, statusCode: 307, httpVersion: nil,
                headerFields: ["Location": target])!
            let redirected = await delegate.urlSession(
                session, task: task,
                willPerformHTTPRedirection: response, newRequest: proposed)
            XCTAssertNil(redirected)
        }
        task.cancel()
    }

    func testSessionIsEphemeralWithoutSharedCookiesCredentialsOrCacheAndBounded() {
        let configuration = ATAURLSessionTransport.configuration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 60)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 60)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    private func operation(_ client: ATAClient, mutation: Bool) async throws {
        if mutation {
            _ = try await client.renameAccount(
                ATAClientTestSupport.id,
                ATARenameAccountRequestDTO(expectedRevision: 7, name: "Renamed"))
        } else {
            _ = try await client.loadPortfolio()
        }
    }
}
