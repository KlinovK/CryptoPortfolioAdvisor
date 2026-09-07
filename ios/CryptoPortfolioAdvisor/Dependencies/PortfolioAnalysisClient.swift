import ComposableArchitecture
import Foundation

struct PortfolioAnalysisClient: Sendable {
    var analyze: @Sendable (PortfolioSnapshot) async throws -> PortfolioAnalysis
}

enum PortfolioAnalysisClientError: Error, Equatable, Sendable {
    case liveClientNotConfigured
}

extension PortfolioAnalysisClient: DependencyKey {
    static let liveValue = Self(
        analyze: { _ in
            throw PortfolioAnalysisClientError.liveClientNotConfigured
        }
    )

    static let testValue = Self(
        analyze: { _ in
            throw PortfolioAnalysisClientError.liveClientNotConfigured
        }
    )
}

extension DependencyValues {
    var portfolioAnalysis: PortfolioAnalysisClient {
        get { self[PortfolioAnalysisClient.self] }
        set { self[PortfolioAnalysisClient.self] = newValue }
    }
}
