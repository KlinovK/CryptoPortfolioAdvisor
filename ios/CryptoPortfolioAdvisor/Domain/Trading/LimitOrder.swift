import Foundation

enum OrderSide: String, Equatable, Codable, Sendable {
    case buy
    case sell
}

enum OrderStatus: String, Equatable, Codable, Sendable {
    case open
    case filled
    case cancelled
}

struct LimitOrder: Equatable, Codable, Sendable {
    let id: UUID
    let symbol: AssetSymbol
    let side: OrderSide
    let amountUSD: Decimal
    let targetPrice: Decimal
    let status: OrderStatus
    let createdAt: Date
    let resolvedAt: Date?

    init(
        id: UUID,
        symbol: AssetSymbol,
        side: OrderSide,
        amountUSD: Decimal,
        targetPrice: Decimal,
        status: OrderStatus,
        createdAt: Date,
        resolvedAt: Date? = nil
    ) throws {
        guard amountUSD > 0 else {
            throw DomainValidationError.nonPositiveOrderAmountUSD
        }

        guard targetPrice > 0 else {
            throw DomainValidationError.nonPositiveOrderTargetPrice
        }

        guard status != .open || resolvedAt == nil else {
            throw DomainValidationError.openOrderCannotHaveResolvedAt
        }

        self.id = id
        self.symbol = symbol
        self.side = side
        self.amountUSD = amountUSD
        self.targetPrice = targetPrice
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }

    private enum CodingKeys: CodingKey {
        case id
        case symbol
        case side
        case amountUSD
        case targetPrice
        case status
        case createdAt
        case resolvedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            symbol: container.decode(AssetSymbol.self, forKey: .symbol),
            side: container.decode(OrderSide.self, forKey: .side),
            amountUSD: container.decode(Decimal.self, forKey: .amountUSD),
            targetPrice: container.decode(Decimal.self, forKey: .targetPrice),
            status: container.decode(OrderStatus.self, forKey: .status),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            resolvedAt: container.decodeIfPresent(Date.self, forKey: .resolvedAt)
        )
    }
}
