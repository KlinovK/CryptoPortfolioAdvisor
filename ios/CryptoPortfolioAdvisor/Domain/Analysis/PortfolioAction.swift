import Foundation

enum PortfolioActionType: String, Equatable, Codable, Sendable {
    case buy
    case sell
    case hold
    case wait
    case placeLimit = "place_limit_order"
    case keepLimit = "keep_limit_order"
    case cancelLimit = "cancel_limit_order"
    case rebalance
    case monitor
}

struct PortfolioAction: Equatable, Codable, Sendable {
    let id: UUID
    let asset: AssetSymbol?
    let type: PortfolioActionType
    let side: OrderSide?
    let price: Decimal?
    let amountUSD: Decimal?
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
