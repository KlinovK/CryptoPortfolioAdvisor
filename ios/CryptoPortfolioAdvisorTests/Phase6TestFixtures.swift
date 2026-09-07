import Foundation

@testable import CryptoPortfolioAdvisor

enum Phase6TestFixtures {
    static let snapshotID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let analysisID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    static let actionID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    static let date = Date(timeIntervalSince1970: 1_788_500_520)

    static func snapshot(
        id: UUID = snapshotID,
        createdAt: Date = date
    ) throws -> PortfolioSnapshot {
        let link = try AssetSymbol("LINK")
        return PortfolioSnapshot(
            id: id,
            createdAt: createdAt,
            portfolio: try Portfolio(
                positions: [
                    try AssetPosition(
                        symbol: link,
                        amount: decimal("0.1234567890123456789012345678")
                    )
                ]
            ),
            constraints: try TradingConstraints(
                tradingStyle: .active,
                riskTolerance: .moderate,
                leverageAllowed: false,
                additionalMonthlyIncomeUSD: decimal("0"),
                minimumStableReserveUSD: decimal("1000.000000000000001")
            ),
            orders: [
                try LimitOrder(
                    id: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
                    symbol: link,
                    side: .buy,
                    amountUSD: decimal("1234.567890123456789"),
                    targetPrice: decimal("15.123456789012345"),
                    status: .open,
                    createdAt: createdAt
                )
            ]
        )
    }

    static func analysis(
        id: UUID = analysisID,
        snapshotID: UUID = snapshotID,
        generatedAt: Date = date,
        analysisMode: AnalysisMode = .deterministic
    ) throws -> PortfolioAnalysis {
        let link = try AssetSymbol("LINK")
        return PortfolioAnalysis(
            id: id,
            generatedAt: generatedAt,
            snapshotID: snapshotID,
            analysisMode: analysisMode,
            riskLevel: .moderate,
            portfolioSummary: PortfolioSummary(
                totalValueUSD: decimal("1234.567890123456789"),
                stableValueUSD: decimal("0.000000000000001"),
                investedValueUSD: decimal("1234.567890123456788"),
                stableAllocationPercentage: decimal("0.000000000000081"),
                openBuyOrdersUSD: decimal("1234.567890123456789"),
                openSellOrdersUSD: decimal("0"),
                deployableStableUSD: decimal("0"),
                allocations: [
                    PortfolioAllocation(
                        asset: link,
                        valueUSD: decimal("1234.567890123456789"),
                        allocationPercentage: decimal("100")
                    )
                ]
            ),
            marketSummary: MarketSummary(
                asOf: generatedAt,
                overview: "Deterministic analysis using static development market data."
            ),
            actions: [
                PortfolioAction(
                    id: actionID,
                    asset: link,
                    type: .keepLimit,
                    side: .buy,
                    price: decimal("15.123456789012345"),
                    amountUSD: decimal("1234.567890123456789"),
                    priority: 1,
                    reason: "Deterministic fixture action."
                )
            ],
            assetAnalysis: [
                AssetAnalysis(
                    asset: link,
                    valueUSD: decimal("1234.567890123456789"),
                    allocationPercentage: decimal("100"),
                    assessment: "LINK quantity received.",
                    recommendation: "No AI recommendation in deterministic mode."
                )
            ],
            warnings: [
                PortfolioWarning(
                    code: "DEVELOPMENT_MARKET_DATA",
                    severity: .info,
                    message: "Static prices only.",
                    asset: nil
                )
            ]
        )
    }

    static func validDashboardState() -> DashboardFeature.State {
        var state = DashboardFeature.State()
        state.assetPositions = [
            AssetPositionDraft(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!,
                symbol: "LINK",
                amount: "0.1234567890123456789012345678"
            )
        ]
        state.constraints.riskTolerance = .moderate
        state.constraints.minimumStableReserveUSD = "1000.000000000000001"
        state.limitOrders = [
            LimitOrderDraft(
                id: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
                symbol: "LINK",
                side: .buy,
                amountUSD: "1234.567890123456789",
                targetPrice: "15.123456789012345",
                status: .open,
                createdAt: date
            )
        ]
        return state
    }

    static func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
