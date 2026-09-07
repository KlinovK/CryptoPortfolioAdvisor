import Foundation

struct PortfolioSnapshot: Equatable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let portfolio: Portfolio
    let constraints: TradingConstraints
    let orders: [LimitOrder]
}
