import ComposableArchitecture
import Foundation

struct ATAClient: Sendable {
    var loadPortfolio: @Sendable () async throws -> ATACurrentPortfolio
    var loadLatestAnalysis: @Sendable () async throws -> ATAAnalysisDetail
    var loadAnalyses: @Sendable (Int) async throws -> ATARecentAnalyses
    var loadAnalysis: @Sendable (UUID) async throws -> ATAAnalysisDetail
    var createAccount: @Sendable (ATACreateAccountRequestDTO) async throws -> ATACurrentPortfolio
    var renameAccount:
        @Sendable (UUID, ATARenameAccountRequestDTO) async throws -> ATACurrentPortfolio
    var updateAccountHoldings:
        @Sendable (UUID, ATAReplaceAccountHoldingsRequestDTO) async throws -> ATACurrentPortfolio
    var deleteAccount:
        @Sendable (UUID, ATADeleteAccountRequestDTO) async throws -> ATACurrentPortfolio
    var updateFinancialSettings:
        @Sendable (ATAUpdateFinancialSettingsRequestDTO) async throws -> ATACurrentPortfolio
    var updateCorePosition:
        @Sendable (AssetSymbol, ATAUpdateCorePositionRequestDTO) async throws -> ATACurrentPortfolio
    var createLimitOrder: @Sendable (ATACreateOrderRequestDTO) async throws -> ATACurrentPortfolio
    var cancelLimitOrder:
        @Sendable (UUID, ATAOrderLifecycleRequestDTO) async throws -> ATACurrentPortfolio
    var expireLimitOrder:
        @Sendable (UUID, ATAOrderLifecycleRequestDTO) async throws -> ATACurrentPortfolio
    var confirmLimitOrderFilled:
        @Sendable (UUID, ATAConfirmOrderFilledRequestDTO) async throws -> ATACurrentPortfolio
}

extension ATAClient: DependencyKey {
    // Step 9C does not configure or activate ATA at the application composition root.
    static let liveValue = Self(
        loadPortfolio: { throw ATAClientError.invalidConfiguration },
        loadLatestAnalysis: { throw ATAClientError.invalidConfiguration },
        loadAnalyses: { _ in throw ATAClientError.invalidConfiguration },
        loadAnalysis: { _ in throw ATAClientError.invalidConfiguration },
        createAccount: { _ in throw ATAClientError.invalidConfiguration },
        renameAccount: { _, _ in throw ATAClientError.invalidConfiguration },
        updateAccountHoldings: { _, _ in throw ATAClientError.invalidConfiguration },
        deleteAccount: { _, _ in throw ATAClientError.invalidConfiguration },
        updateFinancialSettings: { _ in throw ATAClientError.invalidConfiguration },
        updateCorePosition: { _, _ in throw ATAClientError.invalidConfiguration },
        createLimitOrder: { _ in throw ATAClientError.invalidConfiguration },
        cancelLimitOrder: { _, _ in throw ATAClientError.invalidConfiguration },
        expireLimitOrder: { _, _ in throw ATAClientError.invalidConfiguration },
        confirmLimitOrderFilled: { _, _ in throw ATAClientError.invalidConfiguration }
    )
    static let testValue: Self = liveValue
    static let previewValue: Self = liveValue
}

extension DependencyValues {
    var ataClient: ATAClient {
        get { self[ATAClient.self] }
        set { self[ATAClient.self] = newValue }
    }
}
