import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class PersistenceStoreTests: XCTestCase {
    func testDashboardDraftPreservesRawFinancialStrings() async throws {
        let client = try makeClient()
        let draft = PersistedDashboardDraft(
            assetPositions: [
                PersistedAssetDraft(id: UUID(), symbol: "BTC", amount: "0.")
            ],
            constraints: PersistedTradingConstraintsDraft(
                tradingStyle: .active,
                riskTolerance: .conservative,
                leverageAllowed: false,
                additionalMonthlyIncomeUSD: "-",
                minimumStableReserveUSD: "1000."
            ),
            limitOrders: [
                PersistedLimitOrderDraft(
                    id: UUID(),
                    symbol: "BTC",
                    side: .buy,
                    amountUSD: "200.",
                    targetPrice: "76500.",
                    status: .open,
                    createdAt: fixedDate,
                    resolvedAt: nil
                )
            ]
        )

        try await client.saveDashboardDraft(draft)
        let restored = try await client.loadDashboardDraft()

        XCTAssertEqual(restored, draft)
    }

    func testArbitraryAssetsSurviveDraftPersistenceRoundTrip() async throws {
        let client = try makeClient()
        let draft = PersistedDashboardDraft(
            assetPositions: [
                PersistedAssetDraft(id: UUID(), symbol: "LINK", amount: "42.125"),
                PersistedAssetDraft(id: UUID(), symbol: "JITO", amount: "7")
            ],
            constraints: defaultPersistedConstraints,
            limitOrders: []
        )

        try await client.saveDashboardDraft(draft)
        let restored = try await client.loadDashboardDraft()

        XCTAssertEqual(restored?.assetPositions.map(\.symbol), ["LINK", "JITO"])
    }

    func testSnapshotPortfolioRoundTripIsExact() async throws {
        let client = try makeClient()
        let snapshot = try makeSnapshot()

        try await client.saveSnapshot(snapshot)
        let restored = try await client.loadLatestSnapshot()

        XCTAssertEqual(restored?.portfolio, snapshot.portfolio)
    }

    func testSnapshotTradingConstraintsRoundTripIsExact() async throws {
        let client = try makeClient()
        let snapshot = try makeSnapshot()

        try await client.saveSnapshot(snapshot)
        let restored = try await client.loadLatestSnapshot()

        XCTAssertEqual(restored?.constraints, snapshot.constraints)
    }

    func testSnapshotOrdersRoundTripIsExact() async throws {
        let client = try makeClient()
        let snapshot = try makeSnapshot()

        try await client.saveSnapshot(snapshot)
        let restored = try await client.loadLatestSnapshot()

        XCTAssertEqual(restored?.orders, snapshot.orders)
    }

    func testSnapshotDecimalsRoundTripWithoutPrecisionLoss() async throws {
        let client = try makeClient()
        let snapshot = try makeSnapshot(
            positionAmount: decimal("0.1234567890123456789012345678"),
            orderAmount: decimal("1234.567890123456789"),
            targetPrice: decimal("76500.123456789012345")
        )

        try await client.saveSnapshot(snapshot)
        let loadedSnapshot = try await client.loadLatestSnapshot()
        let restored = try XCTUnwrap(loadedSnapshot)

        XCTAssertEqual(restored.portfolio.positions[0].amount, decimal("0.1234567890123456789012345678"))
        XCTAssertEqual(restored.orders[0].amountUSD, decimal("1234.567890123456789"))
        XCTAssertEqual(restored.orders[0].targetPrice, decimal("76500.123456789012345"))
    }

    func testSavedSnapshotRemainsImmutableWhenCurrentDraftChanges() async throws {
        let client = try makeClient()
        let snapshotA = try makeSnapshot(positionAmount: decimal("1.25"))
        try await client.saveSnapshot(snapshotA)

        let changedDraft = PersistedDashboardDraft(
            assetPositions: [
                PersistedAssetDraft(id: UUID(), symbol: "LINK", amount: "999")
            ],
            constraints: defaultPersistedConstraints,
            limitOrders: []
        )
        try await client.saveDashboardDraft(changedDraft)

        let restoredSnapshotA = try await client.loadLatestSnapshot()
        XCTAssertEqual(restoredSnapshotA, snapshotA)
    }

    func testNextDayDraftCreatesNewImmutableSnapshotAndAnalysis() async throws {
        let client = try makeClient()
        let dayOneSnapshot = try Phase6TestFixtures.snapshot()
        let dayOneAnalysis = try Phase6TestFixtures.analysis()
        try await client.saveSnapshot(dayOneSnapshot)
        try await client.saveAnalysis(dayOneAnalysis)

        var nextDayState = DashboardFeature.State()
        nextDayState.restore(from: dayOneSnapshot, makePositionID: UUID.init)
        nextDayState.assetPositions[0].amount = "0.2"
        nextDayState.limitOrders[0].status = .filled
        nextDayState.limitOrders[0].resolvedAt = fixedDate.addingTimeInterval(86_400)
        let validated = try XCTUnwrap(nextDayState.makeValidatedDraft().validatedInput)
        let dayTwoSnapshot = PortfolioSnapshot(
            id: UUID(),
            createdAt: fixedDate.addingTimeInterval(86_400),
            portfolio: validated.portfolio,
            constraints: validated.constraints,
            orders: validated.limitOrders
        )
        let dayTwoAnalysis = try Phase6TestFixtures.analysis(
            id: UUID(),
            snapshotID: dayTwoSnapshot.id,
            generatedAt: dayTwoSnapshot.createdAt,
            analysisMode: .aiFallback
        )

        try await client.saveSnapshot(dayTwoSnapshot)
        try await client.saveAnalysis(dayTwoAnalysis)

        let restoredDayOneSnapshot = try await client.loadSnapshot(dayOneSnapshot.id)
        let restoredDayOneAnalysis = try await client.loadAnalysis(dayOneAnalysis.id)
        let restoredDayTwoSnapshot = try await client.loadSnapshot(dayTwoSnapshot.id)
        let restoredDayTwoAnalysis = try await client.loadAnalysis(dayTwoAnalysis.id)
        let snapshots = try await client.loadSnapshots()
        let analyses = try await client.loadAnalyses()

        XCTAssertEqual(restoredDayOneSnapshot, dayOneSnapshot)
        XCTAssertEqual(restoredDayOneAnalysis, dayOneAnalysis)
        XCTAssertEqual(restoredDayTwoSnapshot, dayTwoSnapshot)
        XCTAssertEqual(restoredDayTwoAnalysis, dayTwoAnalysis)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(analyses.count, 2)
    }

    func testLatestSnapshotLoadsMostRecentRecord() async throws {
        let client = try makeClient()
        let older = try makeSnapshot(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = try makeSnapshot(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try await client.saveSnapshot(newer)
        try await client.saveSnapshot(older)

        let latest = try await client.loadLatestSnapshot()
        XCTAssertEqual(latest, newer)
    }

    func testLoadSnapshotsReturnsNewestFirstWithDeterministicTiebreaker() async throws {
        let client = try makeClient()
        let firstTieID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondTieID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let older = try makeSnapshot(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let firstTie = try makeSnapshot(
            id: firstTieID,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let secondTie = try makeSnapshot(
            id: secondTieID,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        try await client.saveSnapshot(secondTie)
        try await client.saveSnapshot(older)
        try await client.saveSnapshot(firstTie)

        let snapshots = try await client.loadSnapshots()

        XCTAssertEqual(snapshots.map(\.id), [firstTieID, secondTieID, older.id])
    }

    func testLoadSnapshotReturnsMatchingIDAndNilForMissingID() async throws {
        let client = try makeClient()
        let first = try makeSnapshot(id: UUID())
        let second = try makeSnapshot(id: UUID())
        try await client.saveSnapshot(first)
        try await client.saveSnapshot(second)

        let matched = try await client.loadSnapshot(second.id)
        let missing = try await client.loadSnapshot(UUID())

        XCTAssertEqual(matched, second)
        XCTAssertNil(missing)
    }

    func testLoadSnapshotsPreservesCompleteSnapshotAndDecimalPrecision() async throws {
        let client = try makeClient()
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let link = try AssetSymbol("LINK")
        let statuses: [OrderStatus] = [.filled, .open, .cancelled]
        let snapshot = PortfolioSnapshot(
            id: UUID(),
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
                riskTolerance: .aggressive,
                leverageAllowed: true,
                additionalMonthlyIncomeUSD: decimal("10.000000000000001"),
                minimumStableReserveUSD: decimal("1000.000000000000001")
            ),
            orders: try statuses.map { status in
                try LimitOrder(
                    id: UUID(),
                    symbol: link,
                    side: .sell,
                    amountUSD: decimal("1234.567890123456789"),
                    targetPrice: decimal("76500.123456789012345"),
                    status: status,
                    createdAt: createdAt,
                    resolvedAt: status == .open ? nil : createdAt.addingTimeInterval(60)
                )
            }
        )

        try await client.saveSnapshot(snapshot)
        let restored = try await client.loadSnapshots()

        XCTAssertEqual(restored, [snapshot])
    }

    func testExistingSnapshotIDCannotBeOverwritten() async throws {
        let client = try makeClient()
        let id = UUID()
        let original = try makeSnapshot(id: id, positionAmount: decimal("1"))
        let replacement = try makeSnapshot(id: id, positionAmount: decimal("999"))
        try await client.saveSnapshot(original)

        do {
            try await client.saveSnapshot(replacement)
            XCTFail("Saving a duplicate snapshot ID should fail.")
        } catch {
            XCTAssertEqual(error as? PersistenceStoreError, .duplicateSnapshotID(id))
        }

        let restored = try await client.loadLatestSnapshot()
        XCTAssertEqual(restored, original)
    }

    func testAnalysisPersistenceRoundTripIsLossless() async throws {
        let client = try makeClient()
        let analysis = try Phase6TestFixtures.analysis(analysisMode: .aiFallback)

        try await client.saveAnalysis(analysis)
        let restored = try await client.loadAnalysis(analysis.id)

        XCTAssertEqual(restored, analysis)
        XCTAssertEqual(
            restored?.actions[0].amountUSD,
            decimal("1234.567890123456789")
        )
        XCTAssertEqual(
            restored?.actions[0].price,
            decimal("15.123456789012345")
        )
        XCTAssertEqual(restored?.analysisMode, .aiFallback)
    }

    func testAllAnalysisModesRemainReadable() throws {
        for mode in [AnalysisMode.deterministic, .aiAssisted, .aiFallback] {
            let analysis = try Phase6TestFixtures.analysis(analysisMode: mode)

            let restored = try PersistenceMapper.decodeAnalysis(
                PersistenceMapper.encodeAnalysis(analysis)
            )

            XCTAssertEqual(restored, analysis)
            XCTAssertEqual(restored.analysisMode, mode)
        }
    }

    func testAnalysisSummaryMetricsPersistLosslessly() async throws {
        let client = try makeClient()
        let analysis = try Phase6TestFixtures.analysis()

        try await client.saveAnalysis(analysis)
        let loaded = try await client.loadAnalysis(analysis.id)
        let restored = try XCTUnwrap(loaded)

        XCTAssertEqual(restored.portfolioSummary, analysis.portfolioSummary)
        XCTAssertEqual(
            restored.portfolioSummary.stableAllocationPercentage,
            decimal("0.000000000000081")
        )
        XCTAssertEqual(
            restored.portfolioSummary.openBuyOrdersUSD,
            decimal("1234.567890123456789")
        )
    }

    func testPhase6AnalysisPayloadMigratesCashToStableValue() throws {
        let legacyJSON =
            """
            {
              "id": "20000000-0000-0000-0000-000000000002",
              "generatedAt": 0,
              "snapshotID": "10000000-0000-0000-0000-000000000001",
              "riskLevel": "low",
              "portfolioSummary": {
                "totalValueUSD": "100",
                "cashValueUSD": "25",
                "investedValueUSD": "75",
                "allocations": []
              },
              "marketSummary": {"as_of": 0, "overview": "Legacy Phase 6 analysis."},
              "actions": [],
              "assetAnalysis": [],
              "warnings": []
            }
            """

        let analysis = try PersistenceMapper.decodeAnalysis(Data(legacyJSON.utf8))

        XCTAssertEqual(analysis.portfolioSummary.stableValueUSD, decimal("25"))
        XCTAssertEqual(analysis.portfolioSummary.stableAllocationPercentage, decimal("25"))
        XCTAssertEqual(analysis.portfolioSummary.openBuyOrdersUSD, 0)
        XCTAssertEqual(analysis.portfolioSummary.deployableStableUSD, 0)
        XCTAssertEqual(analysis.analysisMode, .deterministic)
    }

    func testLoadAnalysesReturnsNewestFirstWithDeterministicTiebreaker() async throws {
        let client = try makeClient()
        let firstTieID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondTieID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let older = try Phase6TestFixtures.analysis(
            id: UUID(),
            generatedAt: Date(timeIntervalSince1970: 100)
        )
        let firstTie = try Phase6TestFixtures.analysis(
            id: firstTieID,
            generatedAt: Date(timeIntervalSince1970: 200)
        )
        let secondTie = try Phase6TestFixtures.analysis(
            id: secondTieID,
            generatedAt: Date(timeIntervalSince1970: 200)
        )

        try await client.saveAnalysis(secondTie)
        try await client.saveAnalysis(older)
        try await client.saveAnalysis(firstTie)

        let analyses = try await client.loadAnalyses()
        XCTAssertEqual(analyses.map(\.id), [firstTieID, secondTieID, older.id])
    }

    func testSavingSameAnalysisTwiceIsIdempotent() async throws {
        let client = try makeClient()
        let analysis = try Phase6TestFixtures.analysis()

        try await client.saveAnalysis(analysis)
        try await client.saveAnalysis(analysis)

        let restored = try await client.loadAnalyses()
        XCTAssertEqual(restored, [analysis])
    }

    func testAnalysisIDCannotBeOverwrittenWithDifferentContent() async throws {
        let client = try makeClient()
        let original = try Phase6TestFixtures.analysis()
        let replacement = try Phase6TestFixtures.analysis(
            id: original.id,
            snapshotID: UUID()
        )
        try await client.saveAnalysis(original)

        do {
            try await client.saveAnalysis(replacement)
            XCTFail("Saving conflicting content under an analysis ID should fail.")
        } catch {
            XCTAssertEqual(
                error as? PersistenceStoreError,
                .conflictingAnalysisID(original.id)
            )
        }

        let restored = try await client.loadAnalysis(original.id)
        XCTAssertEqual(restored, original)
    }

    private var fixedDate: Date {
        Date(timeIntervalSince1970: 1_750_000_000)
    }

    private var defaultPersistedConstraints: PersistedTradingConstraintsDraft {
        PersistedTradingConstraintsDraft(
            tradingStyle: .active,
            riskTolerance: .conservative,
            leverageAllowed: false,
            additionalMonthlyIncomeUSD: "0",
            minimumStableReserveUSD: "1000"
        )
    }

    private func makeClient() throws -> PortfolioPersistenceClient {
        let modelContainer = try PersistenceContainerFactory.makeModelContainer(
            isStoredInMemoryOnly: true
        )
        return .live(modelContainer: modelContainer)
    }

    private func makeSnapshot(
        id: UUID = UUID(),
        createdAt: Date? = nil,
        positionAmount: Decimal? = nil,
        orderAmount: Decimal? = nil,
        targetPrice: Decimal? = nil
    ) throws -> PortfolioSnapshot {
        let portfolio = try Portfolio(
            positions: [
                try AssetPosition(
                    symbol: AssetSymbol("LINK"),
                    amount: positionAmount ?? decimal("42.125")
                )
            ]
        )
        let constraints = try TradingConstraints(
            tradingStyle: .active,
            riskTolerance: .moderate,
            leverageAllowed: false,
            additionalMonthlyIncomeUSD: decimal("0"),
            minimumStableReserveUSD: decimal("1000.000000000000001")
        )
        let order = try LimitOrder(
            id: UUID(),
            symbol: .btc,
            side: .buy,
            amountUSD: orderAmount ?? decimal("200.25"),
            targetPrice: targetPrice ?? decimal("76500.125"),
            status: .open,
            createdAt: fixedDate
        )

        return PortfolioSnapshot(
            id: id,
            createdAt: createdAt ?? fixedDate,
            portfolio: portfolio,
            constraints: constraints,
            orders: [order]
        )
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
