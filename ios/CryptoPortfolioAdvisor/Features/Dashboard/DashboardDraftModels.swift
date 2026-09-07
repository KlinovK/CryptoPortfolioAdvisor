import Foundation

struct AssetPositionDraft: Equatable, Identifiable, Sendable {
    let id: UUID
    var symbol: String
    var amount: String

    init(
        id: UUID,
        symbol: String = "",
        amount: String = ""
    ) {
        self.id = id
        self.symbol = symbol
        self.amount = amount
    }
}

struct TradingConstraintsDraft: Equatable, Sendable {
    var tradingStyle: TradingStyle = .active
    var riskTolerance: RiskTolerance = .conservative
    var leverageAllowed = false
    var additionalMonthlyIncomeUSD = "0"
    var minimumStableReserveUSD = "0"
}

struct LimitOrderDraft: Equatable, Identifiable, Sendable {
    let id: UUID
    var symbol: String
    var side: OrderSide
    var amountUSD: String
    var targetPrice: String
    var status: OrderStatus
    let createdAt: Date
    var resolvedAt: Date?

    init(
        id: UUID,
        symbol: String = "",
        side: OrderSide = .buy,
        amountUSD: String = "",
        targetPrice: String = "",
        status: OrderStatus = .open,
        createdAt: Date,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.amountUSD = amountUSD
        self.targetPrice = targetPrice
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

extension DashboardFeature.State {
    var persistedDraft: PersistedDashboardDraft {
        PersistedDashboardDraft(
            assetPositions: assetPositions.map {
                PersistedAssetDraft(id: $0.id, symbol: $0.symbol, amount: $0.amount)
            },
            constraints: PersistedTradingConstraintsDraft(
                tradingStyle: constraints.tradingStyle,
                riskTolerance: constraints.riskTolerance,
                leverageAllowed: constraints.leverageAllowed,
                additionalMonthlyIncomeUSD: constraints.additionalMonthlyIncomeUSD,
                minimumStableReserveUSD: constraints.minimumStableReserveUSD
            ),
            limitOrders: limitOrders.map {
                PersistedLimitOrderDraft(
                    id: $0.id,
                    symbol: $0.symbol,
                    side: $0.side,
                    amountUSD: $0.amountUSD,
                    targetPrice: $0.targetPrice,
                    status: $0.status,
                    createdAt: $0.createdAt,
                    resolvedAt: $0.resolvedAt
                )
            }
        )
    }

    mutating func restore(from draft: PersistedDashboardDraft) {
        assetPositions = draft.assetPositions.map {
            AssetPositionDraft(id: $0.id, symbol: $0.symbol, amount: $0.amount)
        }
        constraints = TradingConstraintsDraft(
            tradingStyle: draft.constraints.tradingStyle,
            riskTolerance: draft.constraints.riskTolerance,
            leverageAllowed: draft.constraints.leverageAllowed,
            additionalMonthlyIncomeUSD: draft.constraints.additionalMonthlyIncomeUSD,
            minimumStableReserveUSD: draft.constraints.minimumStableReserveUSD
        )
        limitOrders = draft.limitOrders.map {
            LimitOrderDraft(
                id: $0.id,
                symbol: $0.symbol,
                side: $0.side,
                amountUSD: $0.amountUSD,
                targetPrice: $0.targetPrice,
                status: $0.status,
                createdAt: $0.createdAt,
                resolvedAt: $0.resolvedAt
            )
        }
    }

    mutating func restore(
        from snapshot: PortfolioSnapshot,
        makePositionID: () -> UUID
    ) {
        assetPositions = snapshot.portfolio.positions.map {
            AssetPositionDraft(
                id: makePositionID(),
                symbol: $0.symbol.rawValue,
                amount: DashboardDecimalString.canonical($0.amount)
            )
        }
        constraints = TradingConstraintsDraft(
            tradingStyle: snapshot.constraints.tradingStyle,
            riskTolerance: snapshot.constraints.riskTolerance,
            leverageAllowed: snapshot.constraints.leverageAllowed,
            additionalMonthlyIncomeUSD: DashboardDecimalString.canonical(
                snapshot.constraints.additionalMonthlyIncomeUSD
            ),
            minimumStableReserveUSD: DashboardDecimalString.canonical(
                snapshot.constraints.minimumStableReserveUSD
            )
        )
        limitOrders = snapshot.orders.map {
            LimitOrderDraft(
                id: $0.id,
                symbol: $0.symbol.rawValue,
                side: $0.side,
                amountUSD: DashboardDecimalString.canonical($0.amountUSD),
                targetPrice: DashboardDecimalString.canonical($0.targetPrice),
                status: $0.status,
                createdAt: $0.createdAt,
                resolvedAt: $0.resolvedAt
            )
        }
    }
}

private enum DashboardDecimalString {
    static func canonical(_ decimal: Decimal) -> String {
        var decimal = decimal
        return NSDecimalString(&decimal, Locale(identifier: "en_US_POSIX"))
    }
}
