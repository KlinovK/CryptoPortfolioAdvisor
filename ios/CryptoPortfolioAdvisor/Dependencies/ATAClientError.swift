import Foundation

struct ATAHTTPFailure: Equatable, Sendable {
    let statusCode: Int
    let error: ATAServiceError
}

enum ATATransportFailure: Equatable, Sendable {
    case timeout
    case connection
}

enum ATAMutationUncertainty: Equatable, Sendable {
    case timeout
    case connection
    case cancelled
    case invalidResponse
    case redirect
    case serverFailure
}

enum ATAClientError: Error, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable, LocalizedError
{
    case missingCredential
    case credentialUnavailable
    case invalidConfiguration
    case invalidRequest
    case transport(ATATransportFailure)
    case cancelled
    // Once handed to transport, absence of a usable response is never evidence of rollback.
    case uncertainMutationOutcome(ATAMutationUncertainty, server: ATAHTTPFailure? = nil)
    case http(ATAHTTPFailure)
    case invalidResponse

    var description: String {
        switch self {
        case .missingCredential: "ATA credential is missing."
        case .credentialUnavailable: "ATA credential is unavailable."
        case .invalidConfiguration: "ATA configuration is invalid."
        case .invalidRequest: "ATA request is invalid."
        case .transport(.timeout): "ATA request timed out."
        case .transport(.connection): "ATA connection failed."
        case .cancelled: "ATA request was cancelled."
        case .uncertainMutationOutcome:
            "The update outcome is uncertain. Reload and reconcile before submitting again."
        case .http: "ATA rejected the request."
        case .invalidResponse: "ATA returned an incompatible response."
        }
    }

    var debugDescription: String { description }
    var errorDescription: String? { description }
    var customMirror: Mirror { Mirror(self, children: ["error": description]) }
}
