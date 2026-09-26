import Foundation

// Immutable read models; no transport, persistence, or strategy behavior.

struct ATAAnalysisRun: Equatable, Sendable {
    let runID: UUID
    let snapshotID: UUID
    let startedAt: Date
    let status: ATAAnalysisRunStatus
    let completedAt: Date?
    let marketCutoff: Date?
}

struct ATARecentAnalyses: Equatable, Sendable {
    let analyses: [ATAAnalysisRun]
}

struct ATACandle: Equatable, Sendable {
    let closedAt: Date
    let open: Decimal
    let high: Decimal
    let low: Decimal
    let close: Decimal
}

struct ATATechnicalFeatures: Equatable, Sendable {
    let change24hPct: Decimal?
    let change7dPct: Decimal?
    let rsi4H: Decimal?
    let ema204H: Decimal?
    let ema504H: Decimal?
    let atr4H: Decimal?
    let support: Decimal?
    let resistance: Decimal?
}

struct ATADailyContext: Equatable, Sendable {
    let latestClosedAt: Date?
    let closedPriceUSD: Decimal?
    let ema20: Decimal?
    let ema50: Decimal?
    let support: Decimal?
    let resistance: Decimal?
    let trend: ATADailyTrend
}

struct ATAMarketAsset: Equatable, Sendable {
    let symbol: AssetSymbol
    let priceUSD: Decimal
    let quotedAt: Date
    let latestClosedCandleAt: Date?
    let technicalFeatures: ATATechnicalFeatures
    let completeness: ATADataCompleteness
    let latestClosedPriceUSD: Decimal?
    let dailyContext: ATADailyContext
    let closed1HCandles: [ATACandle]
}

struct ATAMarketSnapshot: Equatable, Sendable {
    let asOf: Date
    let assets: [ATAMarketAsset]
    let isLive: Bool
}

struct ATAFinancialSummary: Equatable, Sendable {
    let totalPortfolioUSD: Decimal
    let currentStablesUSD: Decimal
    let stableAllocationPercent: Decimal
    let monthlyExpensesUSD: Decimal
    let targetExpenseRunwayMonths: Decimal
    let recommendedMinimumStablesUSD: Decimal
    let deployableStablesUSD: Decimal
    let stableReserveDeficitUSD: Decimal
    let actualExpenseRunwayMonths: Decimal
    let openBuyCommitmentsUSD: Decimal
    let hardExpenseReserveUSD: Decimal
    let marketBufferUSD: Decimal
    let potentialTradingLiquidityUSD: Decimal
    let strategyDryPowderUSD: Decimal
    let recommendedDeploymentUSD: Decimal
}

struct ATARecommendation: Equatable, Sendable {
    let recommendationID: UUID
    let asset: AssetSymbol?
    let actionType: ATAActionType
    let priority: Int
    let reason: String
    let existingOrderID: UUID?
    let side: ATAOrderSide?
    let targetPrice: Decimal?
    let quantityAsset: Decimal?
    let invalidationCondition: String?
    let reviewAt: Date?
    let expiresAt: Date?
    let setupID: UUID?
}

struct ATADecisionConfiguration: Equatable, Sendable {
    let marketRegimeVersion: Int
    let stableReserveVersion: Int
    let wholePlanVersion: Int
    let targetRunwayMonths: Decimal
    let marketSource: String
    let aiEnabled: Bool
    let modelName: String?
    let reasoningEffort: String?
    let aiContextVersion: Int?
    let aiSchemaVersion: Int?
    let aiPromptVersion: Int?
    let aiFailureCategory: String?
    let recommendationParameters: String
    let activePolicyParameters: String?
    let reservePolicyParameters: String?
}

struct ATASetupLevel: Equatable, Sendable {
    let price: Decimal
    let source: String
    let priority: Int
}

struct ATASetupScore: Equatable, Sendable {
    let version: Int
    let components: [ATAScoreComponent]
}

struct ATATriggerTransition: Equatable, Sendable {
    let previousState: ATASetupStatus
    let currentState: ATASetupStatus
    let transitionedAt: Date
    let marketCutoff: Date
    let timeframe: ATATriggerTimeframe
    let reason: ATATriggerReason
    let referencePrice: Decimal
}

struct ATATriggerContext: Equatable, Sendable {
    let version: Int
    let zoneLow: Decimal
    let zoneHigh: Decimal
    let atrAtCreation: Decimal
    let transitions: [ATATriggerTransition]
    let touchedAt: Date?
    let highestObservedPrice: Decimal?
    let lowestObservedPrice: Decimal?
    let triggerReferencePrice: Decimal?
    let confirmationAt: Date?
    let confirmationCandle: ATACandle?
    let expiresAt: Date?
    let lastProcessed1HCandleAt: Date?
    let executionValid: Bool
}

struct ATATradeSetup: Equatable, Sendable {
    let id: UUID
    let asset: AssetSymbol
    let direction: ATAOrderSide
    let setupType: ATASetupType
    let createdAt: Date
    let originatingCutoff: Date
    let status: ATASetupStatus
    let limitPrice: Decimal
    let priceSource: String
    let invalidationPrice: Decimal
    let invalidationSource: String
    let targetPrice: Decimal
    let targetSource: String
    let riskReward: Decimal
    let maximumCapitalUSD: Decimal
    let score: ATASetupScore
    let relatedOrderIDs: [UUID]
    let levels: [ATASetupLevel]
    let trigger: ATATriggerContext?
}

struct ATAAssetDecision: Equatable, Sendable {
    let asset: AssetSymbol
    let decision: ATAAssetDecisionType
    let quantity: Decimal
    let marketValueUSD: Decimal
    let allocationPercent: Decimal
    let coreFloor: Decimal?
    let preferredCore: Decimal?
    let tradableQuantity: Decimal
    let dailyTrend: ATADailyTrend
    let setupID: UUID?
}

struct ATAActiveAnalysis: Equatable, Sendable {
    let policyVersion: Int
    let setups: [ATATradeSetup]
    let assetDecisions: [ATAAssetDecision]
    let rankedSetupIDs: [UUID]
    let recommendedDeploymentUSD: Decimal
    let strategyDryPowderUSD: Decimal
    let severity: ATAAnalysisSeverity
}

struct ATAAnalysisResult: Equatable, Sendable {
    let runID: UUID
    let snapshotID: UUID
    let generatedAt: Date
    let marketCutoff: Date?
    let market: ATAMarketSnapshot
    let marketRegime: ATAMarketRegime
    let regimePolicyVersion: Int
    let recommendationPolicyVersion: Int
    let financial: ATAFinancialSummary
    let warnings: [String]
    let recommendations: [ATARecommendation]
    let reasoningMode: ATAReasoningMode
    let reasoningModel: String?
    let aiWarning: String?
    let configuration: ATADecisionConfiguration?
    let active: ATAActiveAnalysis?
}

struct ATAAnalysisDetail: Equatable, Sendable {
    let run: ATAAnalysisRun
    let result: ATAAnalysisResult?
    let failureCategory: String?
}
