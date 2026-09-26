import Foundation

enum ATAValueError: Error, Equatable, Sendable {
    case nonPositivePosition
}

struct ATAServiceError: Equatable, Sendable {
    enum KnownCode: String, CaseIterable, Sendable {
        case unauthorized = "unauthorized"
        case portfolioNotFound = "portfolio_not_found"
        case analysisNotFound = "analysis_not_found"
        case resourceNotFound = "resource_not_found"
        case revisionConflict = "revision_conflict"
        case stateConflict = "state_conflict"
        case invalidRequest = "invalid_request"
        case validationError = "validation_error"
        case notFound = "not_found"
        case methodNotAllowed = "method_not_allowed"
        case internalError = "internal_error"
        case httpError = "http_error"
    }

    // Preserve unknown codes without assigning them a known meaning.
    let code: String
    let message: String
    let reloadRequired: Bool?

    var knownCode: KnownCode? { KnownCode(rawValue: code) }
}

struct ATAScoreComponent: Equatable, Sendable {
    let name: String
    let points: Int
    let maximum: Int
}
