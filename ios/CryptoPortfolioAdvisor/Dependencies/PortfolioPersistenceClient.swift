import ComposableArchitecture
import Foundation

struct PersistedAssetDraft: Codable, Equatable, Sendable {
    let id: UUID
    let symbol: String
    let amount: String
}

struct PersistedTradingConstraintsDraft: Codable, Equatable, Sendable {
    let tradingStyle: TradingStyle
    let riskTolerance: RiskTolerance
    let leverageAllowed: Bool
    let additionalMonthlyIncomeUSD: String
    let minimumStableReserveUSD: String
}

struct PersistedLimitOrderDraft: Codable, Equatable, Sendable {
    let id: UUID
    let symbol: String
    let side: OrderSide
    let amountUSD: String
    let targetPrice: String
    let status: OrderStatus
    let createdAt: Date
    let resolvedAt: Date?
}

struct PersistedDashboardDraft: Codable, Equatable, Sendable {
    let assetPositions: [PersistedAssetDraft]
    let constraints: PersistedTradingConstraintsDraft
    let limitOrders: [PersistedLimitOrderDraft]
}

struct PortfolioPersistenceClient: Sendable {
    var loadDashboardDraft: @Sendable () async throws -> PersistedDashboardDraft?
    var saveDashboardDraft: @Sendable (PersistedDashboardDraft) async throws -> Void
    var saveSnapshot: @Sendable (PortfolioSnapshot) async throws -> Void
    var loadLatestSnapshot: @Sendable () async throws -> PortfolioSnapshot?
    var loadSnapshots: @Sendable () async throws -> [PortfolioSnapshot]
    var loadSnapshot: @Sendable (UUID) async throws -> PortfolioSnapshot?
    var saveAnalysis: @Sendable (PortfolioAnalysis) async throws -> Void
    var loadAnalyses: @Sendable () async throws -> [PortfolioAnalysis]
    var loadAnalysis: @Sendable (UUID) async throws -> PortfolioAnalysis?
}

enum PortfolioPersistenceClientError: Error, Equatable, Sendable {
    case liveClientNotConfigured
}

extension PortfolioPersistenceClient: DependencyKey {
    static let liveValue = Self(
        loadDashboardDraft: { throw PortfolioPersistenceClientError.liveClientNotConfigured },
        saveDashboardDraft: { _ in
            throw PortfolioPersistenceClientError.liveClientNotConfigured
        },
        saveSnapshot: { _ in
            throw PortfolioPersistenceClientError.liveClientNotConfigured
        },
        loadLatestSnapshot: { throw PortfolioPersistenceClientError.liveClientNotConfigured },
        loadSnapshots: { throw PortfolioPersistenceClientError.liveClientNotConfigured },
        loadSnapshot: { _ in
            throw PortfolioPersistenceClientError.liveClientNotConfigured
        },
        saveAnalysis: { _ in
            throw PortfolioPersistenceClientError.liveClientNotConfigured
        },
        loadAnalyses: {
            throw PortfolioPersistenceClientError.liveClientNotConfigured
        },
        loadAnalysis: { _ in
            throw PortfolioPersistenceClientError.liveClientNotConfigured
        }
    )

    static let testValue = Self.noop
    static let previewValue = Self.noop

    static let noop = Self(
        loadDashboardDraft: { nil },
        saveDashboardDraft: { _ in },
        saveSnapshot: { _ in },
        loadLatestSnapshot: { nil },
        loadSnapshots: { [] },
        loadSnapshot: { _ in nil },
        saveAnalysis: { _ in },
        loadAnalyses: { [] },
        loadAnalysis: { _ in nil }
    )
}

extension DependencyValues {
    var portfolioPersistence: PortfolioPersistenceClient {
        get { self[PortfolioPersistenceClient.self] }
        set { self[PortfolioPersistenceClient.self] = newValue }
    }
}
