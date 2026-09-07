import Foundation

enum RiskLevel: String, Equatable, Codable, Sendable {
    case low
    case moderate
    case high
}

enum AnalysisMode: String, Equatable, Codable, Sendable {
    case deterministic
    case aiAssisted = "ai_assisted"
    case aiFallback = "ai_fallback"
}

struct PortfolioAllocation: Equatable, Codable, Sendable {
    let asset: AssetSymbol
    let valueUSD: Decimal
    let allocationPercentage: Decimal

    private enum CodingKeys: String, CodingKey {
        case asset
        case valueUSD = "value_usd"
        case allocationPercentage = "allocation_pct"
    }
}

struct PortfolioSummary: Equatable, Codable, Sendable {
    let totalValueUSD: Decimal
    let stableValueUSD: Decimal
    let investedValueUSD: Decimal
    let stableAllocationPercentage: Decimal
    let openBuyOrdersUSD: Decimal
    let openSellOrdersUSD: Decimal
    let deployableStableUSD: Decimal
    let allocations: [PortfolioAllocation]

    private enum CodingKeys: String, CodingKey {
        case totalValueUSD = "total_value_usd"
        case stableValueUSD = "stable_value_usd"
        case investedValueUSD = "invested_value_usd"
        case stableAllocationPercentage = "stable_allocation_pct"
        case openBuyOrdersUSD = "open_buy_orders_usd"
        case openSellOrdersUSD = "open_sell_orders_usd"
        case deployableStableUSD = "deployable_stable_usd"
        case allocations
    }
}

struct MarketSummary: Equatable, Codable, Sendable {
    let asOf: Date
    let overview: String

    private enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case overview
    }
}

struct AssetAnalysis: Equatable, Codable, Sendable {
    let asset: AssetSymbol
    let valueUSD: Decimal
    let allocationPercentage: Decimal
    let assessment: String
    let recommendation: String

    private enum CodingKeys: String, CodingKey {
        case asset
        case valueUSD = "value_usd"
        case allocationPercentage = "allocation_pct"
        case assessment
        case recommendation
    }
}

enum WarningSeverity: String, Equatable, Codable, Sendable {
    case info
    case warning
    case critical
}

struct PortfolioWarning: Equatable, Codable, Sendable {
    let code: String
    let severity: WarningSeverity
    let message: String
    let asset: AssetSymbol?
}

struct PortfolioAnalysis: Equatable, Codable, Sendable {
    let id: UUID
    let generatedAt: Date
    let snapshotID: UUID
    let analysisMode: AnalysisMode
    let riskLevel: RiskLevel
    let portfolioSummary: PortfolioSummary
    let marketSummary: MarketSummary
    let actions: [PortfolioAction]
    let assetAnalysis: [AssetAnalysis]
    let warnings: [PortfolioWarning]

    private enum CodingKeys: String, CodingKey {
        case id = "analysis_id"
        case generatedAt = "generated_at"
        case snapshotID = "snapshot_id"
        case analysisMode = "analysis_mode"
        case riskLevel = "risk_level"
        case portfolioSummary = "portfolio_summary"
        case marketSummary = "market_summary"
        case actions
        case assetAnalysis = "asset_analysis"
        case warnings
    }
}
