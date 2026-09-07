import Foundation

struct AnalyzePortfolioRequestDTO: Codable, Equatable, Sendable {
    struct Position: Codable, Equatable, Sendable {
        let symbol: String
        let amount: String
    }

    struct Portfolio: Codable, Equatable, Sendable {
        let positions: [Position]
    }

    struct Constraints: Codable, Equatable, Sendable {
        let tradingStyle: TradingStyle
        let riskTolerance: RiskTolerance
        let leverageAllowed: Bool
        let additionalMonthlyIncomeUSD: String
        let minimumStableReserveUSD: String

        private enum CodingKeys: String, CodingKey {
            case tradingStyle = "trading_style"
            case riskTolerance = "risk_tolerance"
            case leverageAllowed = "leverage_allowed"
            case additionalMonthlyIncomeUSD = "additional_monthly_income_usd"
            case minimumStableReserveUSD = "minimum_stable_reserve_usd"
        }
    }

    struct Order: Codable, Equatable, Sendable {
        let id: UUID
        let symbol: String
        let side: OrderSide
        let amountUSD: String
        let targetPrice: String
        let status: OrderStatus
        let createdAt: Date
        let resolvedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case id
            case symbol
            case side
            case amountUSD = "amount_usd"
            case targetPrice = "target_price"
            case status
            case createdAt = "created_at"
            case resolvedAt = "resolved_at"
        }
    }

    let snapshotID: UUID
    let createdAt: Date
    let portfolio: Portfolio
    let constraints: Constraints
    let orders: [Order]

    private enum CodingKeys: String, CodingKey {
        case snapshotID = "snapshot_id"
        case createdAt = "created_at"
        case portfolio
        case constraints
        case orders
    }
}
