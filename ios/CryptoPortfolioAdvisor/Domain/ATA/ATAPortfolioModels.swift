import Foundation

// Immutable read models; no transport, persistence, or strategy behavior.

struct ATAPosition: Equatable, Sendable {
    let symbol: AssetSymbol
    let amount: Decimal

    init(symbol: AssetSymbol, amount: Decimal) throws {
        guard !amount.isNaN, amount > 0 else {
            throw ATAValueError.nonPositivePosition
        }
        self.symbol = symbol
        self.amount = amount
    }
}

struct ATAAccount: Equatable, Sendable {
    let id: UUID
    let name: String
    let type: ATAAccountType
    let positions: [ATAPosition]
}

struct ATAFinancialSettings: Equatable, Sendable {
    let monthlyExpensesUSD: Decimal
    let targetExpenseRunwayMonths: Decimal
}

struct ATACorePosition: Equatable, Sendable {
    let symbol: AssetSymbol
    let hardFloor: Decimal
    let preferredQuantity: Decimal
    let policyVersion: Int
}

struct ATALimitOrder: Equatable, Sendable {
    let id: UUID
    let accountID: UUID
    let asset: AssetSymbol
    let side: ATAOrderSide
    let targetPrice: Decimal
    let quantityAsset: Decimal
    let status: ATAOrderStatus
    let createdAt: Date
    let updatedAt: Date
    let resolvedAt: Date?
}

struct ATACurrentPortfolio: Equatable, Sendable {
    let revision: Int
    let snapshotID: UUID
    let confirmedAt: Date
    let accounts: [ATAAccount]
    let aggregatePositions: [ATAPosition]
    let financialSettings: ATAFinancialSettings
    let corePositions: [ATACorePosition]
    let limitOrders: [ATALimitOrder]
}
