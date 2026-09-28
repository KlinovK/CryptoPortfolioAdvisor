import Foundation

struct ATAHTTPTransport: Sendable {
    var send: @Sendable (URLRequest) async throws -> (Data, URLResponse)
}

// Reject ALL redirects, including same-origin ones. There is no redirect/replay contract in V1.
final class ATARedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

final class ATAURLSessionTransport: Sendable {
    static let timeout: TimeInterval = 60
    private let session: URLSession

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return configuration
    }

    init() {
        session = URLSession(
            configuration: Self.configuration(), delegate: ATARedirectDelegate(), delegateQueue: nil
        )
    }

    deinit { session.invalidateAndCancel() }

    var transport: ATAHTTPTransport {
        ATAHTTPTransport { request in
            // Foundation's async data(for:) propagates Task cancellation to the underlying task.
            try await self.session.data(for: request)
        }
    }
}
