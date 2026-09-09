import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

final class DomainModelTests: XCTestCase {
    func testAssetSymbolNormalizesLowercaseInput() throws {
        let symbol = try AssetSymbol("btc")

        XCTAssertEqual(symbol.rawValue, "BTC")
        XCTAssertEqual(symbol, .btc)
    }

    func testEmptyAssetSymbolIsRejected() {
        XCTAssertThrowsError(try AssetSymbol("  \n")) { error in
            XCTAssertEqual(error as? DomainValidationError, .emptyAssetSymbol)
        }
    }

    func testTransportIncompatibleAssetSymbolsAreRejected() {
        for rawValue in ["BTC/USD", "BT C", "_BTC", String(repeating: "A", count: 21)] {
            XCTAssertThrowsError(try AssetSymbol(rawValue)) { error in
                XCTAssertEqual(error as? DomainValidationError, .invalidAssetSymbol)
            }
        }
    }

    func testAssetPositionRejectsNegativeAmount() {
        XCTAssertThrowsError(try AssetPosition(symbol: .btc, amount: -1)) { error in
            XCTAssertEqual(error as? DomainValidationError, .negativeAssetAmount)
        }
    }

    func testPortfolioRejectsDuplicateSymbols() throws {
        let firstPosition = try AssetPosition(symbol: .btc, amount: 1)
        let secondPosition = try AssetPosition(symbol: .btc, amount: 2)

        XCTAssertThrowsError(try Portfolio(positions: [firstPosition, secondPosition])) { error in
            XCTAssertEqual(error as? DomainValidationError, .duplicateAssetSymbol(.btc))
        }
    }

    func testTradingConstraintsRejectNegativeMonthlyIncome() {
        XCTAssertThrowsError(
            try TradingConstraints(
                tradingStyle: .active,
                riskTolerance: .conservative,
                leverageAllowed: false,
                additionalMonthlyIncomeUSD: -1,
                minimumStableReserveUSD: 0
            )
        ) { error in
            XCTAssertEqual(
                error as? DomainValidationError,
                .negativeAdditionalMonthlyIncomeUSD
            )
        }
    }

    func testTradingConstraintsRejectNegativeStableReserve() {
        XCTAssertThrowsError(
            try TradingConstraints(
                tradingStyle: .active,
                riskTolerance: .moderate,
                leverageAllowed: false,
                additionalMonthlyIncomeUSD: 0,
                minimumStableReserveUSD: -1
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .negativeMinimumStableReserveUSD)
        }
    }

    func testLimitOrderRejectsZeroAmount() {
        XCTAssertThrowsError(
            try LimitOrder(
                id: UUID(),
                symbol: .btc,
                side: .buy,
                amountUSD: 0,
                targetPrice: 50_000,
                status: .open,
                createdAt: Date()
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .nonPositiveOrderAmountUSD)
        }
    }

    func testLimitOrderRejectsNegativeTargetPrice() {
        XCTAssertThrowsError(
            try LimitOrder(
                id: UUID(),
                symbol: .btc,
                side: .buy,
                amountUSD: 500,
                targetPrice: -100,
                status: .open,
                createdAt: Date()
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .nonPositiveOrderTargetPrice)
        }
    }

    func testOpenLimitOrderRejectsResolvedDate() {
        XCTAssertThrowsError(
            try LimitOrder(
                id: UUID(),
                symbol: .btc,
                side: .buy,
                amountUSD: 500,
                targetPrice: 50_000,
                status: .open,
                createdAt: Date(),
                resolvedAt: Date()
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .openOrderCannotHaveResolvedAt)
        }
    }

    func testArbitraryAssetSymbolWorks() throws {
        let symbol = try AssetSymbol("link")
        let position = try AssetPosition(symbol: symbol, amount: 42)

        XCTAssertEqual(symbol.rawValue, "LINK")
        XCTAssertEqual(position.symbol, symbol)
    }

    func testPortfolioSnapshotPreservesSuppliedState() throws {
        let portfolio = try makePortfolio()
        let constraints = try makeConstraints()
        let orders = [try makeOpenOrder()]
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)

        let snapshot = PortfolioSnapshot(
            id: id,
            createdAt: createdAt,
            portfolio: portfolio,
            constraints: constraints,
            orders: orders
        )

        XCTAssertEqual(snapshot.id, id)
        XCTAssertEqual(snapshot.createdAt, createdAt)
        XCTAssertEqual(snapshot.portfolio, portfolio)
        XCTAssertEqual(snapshot.constraints, constraints)
        XCTAssertEqual(snapshot.orders, orders)
    }

    func testAnalysisRepresentsLimitOrderRecommendation() {
        let action = PortfolioAction(
            id: UUID(),
            asset: .btc,
            type: .placeLimit,
            side: .buy,
            price: 50_000,
            amountUSD: 500,
            priority: 1,
            reason: "Place a conservative limit order."
        )

        let analysis = makeAnalysis(actions: [action])

        XCTAssertEqual(analysis.actions.first, action)
        XCTAssertEqual(analysis.actions.first?.type, .placeLimit)
        XCTAssertEqual(analysis.actions.first?.side, .buy)
    }

    func testPortfolioSnapshotCodableRoundTrip() throws {
        let snapshot = PortfolioSnapshot(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            portfolio: try makePortfolio(),
            constraints: try makeConstraints(),
            orders: [try makeOpenOrder()]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let encoded = try encoder.encode(snapshot)
        let decoded = try decoder.decode(PortfolioSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, snapshot)
    }

    func testPortfolioAnalysisCodableRoundTrip() throws {
        let action = PortfolioAction(
            id: UUID(),
            asset: .btc,
            type: .keepLimit,
            side: .buy,
            price: 50_000,
            amountUSD: 500,
            priority: 2,
            reason: "Keep the existing limit order open."
        )
        let analysis = makeAnalysis(actions: [action])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let encoded = try encoder.encode(analysis)
        let decoded = try decoder.decode(PortfolioAnalysis.self, from: encoded)

        XCTAssertEqual(decoded, analysis)
    }

    private func makePortfolio() throws -> Portfolio {
        try Portfolio(
            positions: [
                try AssetPosition(symbol: .btc, amount: 0.15),
                try AssetPosition(symbol: .usdt, amount: 1_200),
            ]
        )
    }

    private func makeConstraints() throws -> TradingConstraints {
        try TradingConstraints(
            tradingStyle: .active,
            riskTolerance: .conservative,
            leverageAllowed: false,
            additionalMonthlyIncomeUSD: 0,
            minimumStableReserveUSD: 1_000
        )
    }

    private func makeOpenOrder() throws -> LimitOrder {
        try LimitOrder(
            id: UUID(),
            symbol: .btc,
            side: .buy,
            amountUSD: 500,
            targetPrice: 50_000,
            status: .open,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

    private func makeAnalysis(actions: [PortfolioAction]) -> PortfolioAnalysis {
        PortfolioAnalysis(
            id: UUID(),
            generatedAt: Date(timeIntervalSince1970: 1_750_000_100),
            snapshotID: UUID(),
            analysisMode: .deterministic,
            riskLevel: .moderate,
            portfolioSummary: PortfolioSummary(
                totalValueUSD: 9_400,
                stableValueUSD: 1_200,
                investedValueUSD: 8_200,
                stableAllocationPercentage: 12.766,
                openBuyOrdersUSD: 500,
                openSellOrdersUSD: 0,
                deployableStableUSD: 0,
                allocations: [
                    PortfolioAllocation(
                        asset: .btc,
                        valueUSD: 8_200,
                        allocationPercentage: 87.234
                    ),
                    PortfolioAllocation(
                        asset: .usdt,
                        valueUSD: 1_200,
                        allocationPercentage: 12.766
                    ),
                ]
            ),
            marketSummary: MarketSummary(
                asOf: Date(timeIntervalSince1970: 1_750_000_000),
                overview: "Market context."
            ),
            actions: actions,
            assetAnalysis: [
                AssetAnalysis(
                    asset: .btc,
                    valueUSD: 8_200,
                    allocationPercentage: 87.234,
                    assessment: "Concentrated position.",
                    recommendation: "Monitor exposure."
                )
            ],
            warnings: [
                PortfolioWarning(
                    code: "CONCENTRATION_RISK",
                    severity: .warning,
                    message: "A single asset dominates the portfolio.",
                    asset: .btc
                )
            ]
        )
    }
}
