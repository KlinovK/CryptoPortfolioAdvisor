import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class SnapshotDetailsFeatureTests: XCTestCase {
    func testReadOnlyStateContainsExactSnapshot() throws {
        let snapshot = try makeSnapshot()

        let state = SnapshotDetailsFeature.State(snapshot: snapshot)

        XCTAssertEqual(state.snapshot, snapshot)
    }

    func testFinancialFormatterUsesPracticalPrecisionWithoutConvertingToDouble() {
        let formatter = PortfolioFinancialFormatter(locale: Locale(identifier: "en_US"))

        XCTAssertEqual(
            formatter.quantity(decimal("0.1234567890123456789012345678")),
            "0.12345679"
        )
        XCTAssertEqual(formatter.usd(decimal("76500.125")), "$76,500.13")
        XCTAssertEqual(formatter.percentage(decimal("32.456")), "32.46%")
    }

    func testFinancialFormatterNeverDisplaysTinyNonzeroValueAsZero() {
        let formatter = PortfolioFinancialFormatter(locale: Locale(identifier: "en_US"))

        XCTAssertEqual(formatter.usd(decimal("0.000000000000001")), "$0.000000000000001")
        XCTAssertEqual(formatter.quantity(decimal("0.000000000000001")), "0.000000000000001")
        XCTAssertEqual(formatter.percentage(decimal("0.000000000000081")), "0.000000000000081%")
        XCTAssertNotEqual(formatter.usd(decimal("0.000000000000001")), "$0")
    }

    private func makeSnapshot() throws -> PortfolioSnapshot {
        PortfolioSnapshot(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            portfolio: try Portfolio(
                positions: [
                    try AssetPosition(symbol: AssetSymbol("LINK"), amount: decimal("42.125"))
                ]
            ),
            constraints: try TradingConstraints(
                tradingStyle: .active,
                riskTolerance: .moderate,
                leverageAllowed: false,
                additionalMonthlyIncomeUSD: 0,
                minimumStableReserveUSD: decimal("1000.50")
            ),
            orders: []
        )
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
