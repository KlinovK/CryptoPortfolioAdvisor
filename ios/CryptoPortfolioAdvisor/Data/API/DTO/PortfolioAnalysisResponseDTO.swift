import Foundation

struct PortfolioAnalysisResponseDTO: Codable, Equatable, Sendable {
    struct Allocation: Codable, Equatable, Sendable {
        let asset: String
        let valueUSD: String
        let allocationPercentage: String

        private enum CodingKeys: String, CodingKey {
            case asset
            case valueUSD = "value_usd"
            case allocationPercentage = "allocation_pct"
        }
    }

    struct Summary: Codable, Equatable, Sendable {
        let totalValueUSD: String
        let stableValueUSD: String
        let investedValueUSD: String
        let stableAllocationPercentage: String
        let openBuyOrdersUSD: String
        let openSellOrdersUSD: String
        let deployableStableUSD: String
        let allocations: [Allocation]

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

    struct Market: Codable, Equatable, Sendable {
        let asOf: Date
        let overview: String

        private enum CodingKeys: String, CodingKey {
            case asOf = "as_of"
            case overview
        }
    }

    struct Action: Codable, Equatable, Sendable {
        let id: UUID
        let asset: String?
        let type: PortfolioActionType
        let side: OrderSide?
        let price: String?
        let amountUSD: String?
        let priority: Int
        let reason: String

        private enum CodingKeys: String, CodingKey {
            case id
            case asset
            case type
            case side
            case price
            case amountUSD = "amount_usd"
            case priority
            case reason
        }
    }

    struct Asset: Codable, Equatable, Sendable {
        let asset: String
        let valueUSD: String
        let allocationPercentage: String
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

    struct Warning: Codable, Equatable, Sendable {
        let code: String
        let severity: WarningSeverity
        let message: String
        let asset: String?
    }

    let analysisID: UUID
    let generatedAt: Date
    let snapshotID: UUID
    let analysisMode: AnalysisMode
    let riskLevel: RiskLevel
    let portfolioSummary: Summary
    let marketSummary: Market
    let actions: [Action]
    let assetAnalysis: [Asset]
    let warnings: [Warning]

    private enum CodingKeys: String, CodingKey {
        case analysisID = "analysis_id"
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

struct PortfolioAPIErrorResponseDTO: Codable, Equatable, Sendable {
    struct Detail: Codable, Equatable, Sendable {
        let code: String
        let message: String
    }

    let error: Detail
}
