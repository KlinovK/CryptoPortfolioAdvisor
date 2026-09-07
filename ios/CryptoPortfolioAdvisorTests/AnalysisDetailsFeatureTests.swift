import ComposableArchitecture
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class AnalysisDetailsFeatureTests: XCTestCase {
    func testReadOnlyStateContainsExactAnalysisActionsAndWarnings() throws {
        let analysis = try Phase6TestFixtures.analysis()
        let store = TestStore(
            initialState: AnalysisDetailsFeature.State(analysis: analysis)
        ) {
            AnalysisDetailsFeature()
        }

        XCTAssertEqual(store.state.analysis.actions, analysis.actions)
        XCTAssertEqual(store.state.analysis.warnings, analysis.warnings)
    }

    func testReadOnlyStateContainsDeterministicPortfolioMetrics() throws {
        let analysis = try Phase6TestFixtures.analysis()
        let store = TestStore(
            initialState: AnalysisDetailsFeature.State(analysis: analysis)
        ) {
            AnalysisDetailsFeature()
        }

        XCTAssertEqual(
            store.state.analysis.portfolioSummary.stableValueUSD,
            Phase6TestFixtures.decimal("0.000000000000001")
        )
        XCTAssertEqual(
            store.state.analysis.portfolioSummary.openBuyOrdersUSD,
            Phase6TestFixtures.decimal("1234.567890123456789")
        )
        XCTAssertEqual(store.state.analysis.portfolioSummary.deployableStableUSD, 0)
    }

    func testActionsAreOrderedByPriorityWithStableTies() throws {
        let link = try AssetSymbol("LINK")
        let firstMedium = action(id: UUID(), asset: link, type: .hold, priority: 3)
        let low = action(id: UUID(), asset: nil, type: .wait, priority: 5)
        let high = action(id: UUID(), asset: link, type: .buy, priority: 1)
        let secondMedium = action(id: UUID(), asset: link, type: .monitor, priority: 3)

        let ordered = AnalysisDetailsPresentation.orderedActions([
            firstMedium,
            low,
            high,
            secondMedium,
        ])

        XCTAssertEqual(ordered.map(\.id), [high.id, firstMedium.id, secondMedium.id, low.id])
        XCTAssertEqual(AnalysisDetailsPresentation.actionTitle(high), "BUY · LINK")
        XCTAssertEqual(AnalysisDetailsPresentation.priorityTitle(1), "High priority")
        XCTAssertEqual(AnalysisDetailsPresentation.priorityTitle(3), "Medium priority")
        XCTAssertEqual(AnalysisDetailsPresentation.priorityTitle(5), "Low priority")
    }

    func testWarningsAreDeduplicatedAndMostSevereAppearFirst() throws {
        let link = try AssetSymbol("LINK")
        let info = PortfolioWarning(
            code: "INFO",
            severity: .info,
            message: "Informational context.",
            asset: nil
        )
        let critical = PortfolioWarning(
            code: "RISK",
            severity: .critical,
            message: "Critical exposure.",
            asset: link
        )
        let warning = PortfolioWarning(
            code: "LIMIT",
            severity: .warning,
            message: "Review this order.",
            asset: link
        )
        let duplicateWarning = PortfolioWarning(
            code: "LIMIT",
            severity: .info,
            message: "Duplicate lower-severity wording.",
            asset: link
        )

        let ordered = AnalysisDetailsPresentation.orderedWarnings([
            info,
            warning,
            critical,
            duplicateWarning,
        ])

        XCTAssertEqual(ordered.map(\.severity), [.critical, .warning, .info])
        XCTAssertEqual(ordered.count, 3)
        XCTAssertEqual(
            AnalysisDetailsPresentation.warningTitle(.critical),
            "Critical warning"
        )
        XCTAssertEqual(RiskPresentation.title(for: .high), "High risk")
        XCTAssertEqual(
            AnalysisModePresentation.title(for: .aiFallback),
            "AI unavailable — deterministic analysis used"
        )
    }

    private func action(
        id: UUID,
        asset: AssetSymbol?,
        type: PortfolioActionType,
        priority: Int
    ) -> PortfolioAction {
        PortfolioAction(
            id: id,
            asset: asset,
            type: type,
            side: nil,
            price: nil,
            amountUSD: nil,
            priority: priority,
            reason: "Test reason."
        )
    }
}
