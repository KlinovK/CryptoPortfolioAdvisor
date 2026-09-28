import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

enum ATAClientTestSupport {
    // Deliberately synthetic; never a real credential or configured server.
    static let secret = "synthetic-offline-credential"
    static let id = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
    static let idPath = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    static let baseURL = "https://ata.example.com"

    static var credentials: CredentialStore {
        CredentialStore(
            load: { try ATABearerToken(secret) },
            save: { _ in throw CredentialStoreError.notConfigured },
            delete: { throw CredentialStoreError.notConfigured }
        )
    }

    static func response(
        _ request: URLRequest, status: Int = 200,
        body: String = ATAFoundationFixtures.portfolio
    ) -> (Data, URLResponse) {
        (
            Data(body.utf8),
            HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
        )
    }

    static func client(_ probe: ATAHTTPProbe, credentials: CredentialStore = credentials) throws
        -> ATAClient
    {
        try ATAClient.live(
            configuredBaseURL: baseURL, environment: .release,
            credentials: credentials, transport: probe.transport)
    }

    static func positions() throws -> [ATAPosition] {
        try [
            ATAPosition(
                symbol: .btc,
                amount: ATADecimalCodec.decode("0.12345678901234567890123456789012345678")),
            ATAPosition(symbol: .usdc, amount: 2000),
        ]
    }
}

actor ATAHTTPProbe {
    private(set) var requests: [URLRequest] = []
    let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            ATAClientTestSupport.response($0)
        }
    ) {
        self.handler = handler
    }

    nonisolated var transport: ATAHTTPTransport {
        ATAHTTPTransport { try await self.send($0) }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return try await handler(request)
    }
}
