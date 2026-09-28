import ComposableArchitecture
import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
// The CPA editor remains compiled but is no longer the app's active Dashboard.
final class LegacyCPADashboardFeatureTests: XCTestCase {
    func testDashboardStartsWithProductDefaults() {
        let state = DashboardFeature.State()

        XCTAssertEqual(state.constraints.tradingStyle, .active)
        XCTAssertEqual(state.constraints.riskTolerance, .conservative)
        XCTAssertFalse(state.constraints.leverageAllowed)
        XCTAssertEqual(state.constraints.additionalMonthlyIncomeUSD, "0")
        XCTAssertEqual(state.constraints.minimumStableReserveUSD, "0")
        XCTAssertTrue(state.isPortfolioEmpty)
        XCTAssertEqual(state.analysisButtonTitle, "Analyze Portfolio")
        XCTAssertFalse(state.shouldRetryAnalysis)
    }

    func testAddAssetRow() async {
        let id = UUID()
        let store = makeEditStore()

        await store.send(.addAssetTapped(id: id)) {
            $0.assetPositions = [AssetPositionDraft(id: id)]
            $0.draftRevision = 1
            $0.draftPersistenceStatus = .saving
        }
        await store.finish()
    }

    func testRemoveAssetRow() async {
        let id = UUID()
        var initialState = DashboardFeature.State()
        initialState.assetPositions = [AssetPositionDraft(id: id)]
        let store = makeEditStore(initialState: initialState)

        await store.send(.removeAsset(id: id)) {
            $0.assetPositions = []
            $0.draftRevision = 1
            $0.draftPersistenceStatus = .saving
        }
        await store.finish()
    }

    func testArbitraryLinkAssetConvertsToDomain() throws {
        let state = makeValidState(symbol: "link", amount: "42")

        let outcome = state.makeValidatedDraft(locale: posixLocale)

        let position = try XCTUnwrap(outcome.validatedInput?.portfolio.positions.first)
        XCTAssertEqual(position.symbol.rawValue, "LINK")
        XCTAssertEqual(position.amount, 42)
        XCTAssertFalse(outcome.errors.hasErrors)
    }

    func testDuplicateAssetSymbolsAreRejected() {
        let firstID = UUID()
        let secondID = UUID()
        var state = DashboardFeature.State()
        state.assetPositions = [
            AssetPositionDraft(id: firstID, symbol: "btc", amount: "1"),
            AssetPositionDraft(id: secondID, symbol: " BTC ", amount: "2"),
        ]

        let outcome = state.makeValidatedDraft(locale: posixLocale)

        XCTAssertNil(outcome.validatedInput)
        XCTAssertEqual(
            outcome.errors.assetPositions[firstID]?.symbol,
            "Duplicate asset symbol."
        )
        XCTAssertEqual(
            outcome.errors.assetPositions[secondID]?.symbol,
            "Duplicate asset symbol."
        )
    }

    func testTransportIncompatibleAssetSymbolIsRejectedBeforeSubmission() {
        let id = UUID()
        var state = makeValidState(symbol: "BTC/USD")
        state.assetPositions[0] = AssetPositionDraft(
            id: id,
            symbol: "BTC/USD",
            amount: "0.01"
        )

        let outcome = state.makeValidatedDraft(locale: posixLocale)

        XCTAssertNil(outcome.validatedInput)
        XCTAssertEqual(
            outcome.errors.assetPositions[id]?.symbol,
            "Use 1–20 letters, numbers, '.', '_' or '-'."
        )
    }

    func testNegativeAssetAmountIsRejected() {
        let id = UUID()
        var state = DashboardFeature.State()
        state.assetPositions = [AssetPositionDraft(id: id, symbol: "BTC", amount: "-0.1")]

        let outcome = state.makeValidatedDraft(locale: posixLocale)

        XCTAssertNil(outcome.validatedInput)
        XCTAssertEqual(
            outcome.errors.assetPositions[id]?.amount,
            "Amount must be zero or greater."
        )
    }

    func testAddLimitOrderRow() async {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let store = makeEditStore()

        await store.send(.addOrderTapped(id: id, createdAt: createdAt)) {
            $0.limitOrders = [LimitOrderDraft(id: id, createdAt: createdAt)]
            $0.draftRevision = 1
            $0.draftPersistenceStatus = .saving
        }
        await store.finish()
    }

    func testValidBTCBuyLimitOrderConvertsToDomain() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        var state = makeValidState()
        state.limitOrders = [
            LimitOrderDraft(
                id: id,
                symbol: "btc",
                side: .buy,
                amountUSD: "200",
                targetPrice: "76500.",
                status: .open,
                createdAt: createdAt
            )
        ]

        let outcome = state.makeValidatedDraft(locale: posixLocale)

        let order = try XCTUnwrap(outcome.validatedInput?.limitOrders.first)
        XCTAssertEqual(order.id, id)
        XCTAssertEqual(order.symbol, .btc)
        XCTAssertEqual(order.side, .buy)
        XCTAssertEqual(order.amountUSD, 200)
        XCTAssertEqual(order.targetPrice, 76_500)
        XCTAssertEqual(order.status, .open)
        XCTAssertEqual(order.createdAt, createdAt)
    }

    func testZeroOrderAmountIsRejected() {
        let id = UUID()
        var state = makeValidState()
        state.limitOrders = [
            LimitOrderDraft(
                id: id,
                symbol: "BTC",
                amountUSD: "0",
                targetPrice: "76500",
                createdAt: Date(timeIntervalSince1970: 1_750_000_000)
            )
        ]

        let outcome = state.makeValidatedDraft(locale: posixLocale)

        XCTAssertNil(outcome.validatedInput)
        XCTAssertEqual(
            outcome.errors.limitOrders[id]?.amountUSD,
            "Order amount must be greater than zero."
        )
    }

    func testNegativeOrderTargetPriceIsRejected() {
        let id = UUID()
        var state = makeValidState()
        state.limitOrders = [
            LimitOrderDraft(
                id: id,
                symbol: "BTC",
                amountUSD: "200",
                targetPrice: "-1",
                createdAt: Date(timeIntervalSince1970: 1_750_000_000)
            )
        ]

        let outcome = state.makeValidatedDraft(locale: posixLocale)

        XCTAssertNil(outcome.validatedInput)
        XCTAssertEqual(
            outcome.errors.limitOrders[id]?.targetPrice,
            "Target price must be greater than zero."
        )
    }

    func testRiskToleranceChangesToModerate() async {
        let store = makeEditStore()

        await store.send(.riskToleranceChanged(.moderate)) {
            $0.constraints.riskTolerance = .moderate
            $0.draftRevision = 1
            $0.draftPersistenceStatus = .saving
        }
        await store.finish()
    }

    func testLeverageToggleUpdatesState() async {
        let store = makeEditStore()

        await store.send(.leverageChanged(true)) {
            $0.constraints.leverageAllowed = true
            $0.draftRevision = 1
            $0.draftPersistenceStatus = .saving
        }
        await store.finish()
    }

    func testFilledOrderRecordsResolutionWithoutChangingPortfolio() async {
        let orderID = UUID()
        let resolvedAt = Date(timeIntervalSince1970: 1_760_000_000)
        var initialState = makeValidState(symbol: "BTC", amount: "1.5")
        initialState.limitOrders = [
            LimitOrderDraft(
                id: orderID,
                symbol: "BTC",
                amountUSD: "200",
                targetPrice: "70000",
                createdAt: resolvedAt.addingTimeInterval(-3_600)
            )
        ]
        let originalPortfolio = initialState.assetPositions
        let store = makeEditStore(initialState: initialState, now: resolvedAt)

        await store.send(.orderStatusChanged(id: orderID, status: .filled)) {
            $0.limitOrders[0].status = .filled
            $0.limitOrders[0].resolvedAt = resolvedAt
            $0.draftRevision = 1
            $0.draftPersistenceStatus = .saving
        }
        await store.finish()

        XCTAssertEqual(store.state.assetPositions, originalPortfolio)
    }

    func testDraftMutationsAreIgnoredWhileAnalysisIsSubmitting() async {
        let assetID = UUID()
        var state = makeValidState()
        state.assetPositions[0] = AssetPositionDraft(
            id: assetID,
            symbol: "BTC",
            amount: "1"
        )
        state.analysisSubmissionState = .submitting
        let store = makeEditStore(initialState: state)

        await store.send(.assetAmountChanged(id: assetID, value: "2"))
        await store.send(.removeAsset(id: assetID))

        XCTAssertEqual(store.state.assetPositions[0].amount, "1")
        XCTAssertEqual(store.state.analysisButtonTitle, "Analyzing…")
        XCTAssertTrue(store.state.isSubmitting)
    }

    func testNegativeMonthlyIncomeIsRejected() {
        var state = makeValidState()
        state.constraints.additionalMonthlyIncomeUSD = "-1"

        let outcome = state.makeValidatedDraft(locale: posixLocale)

        XCTAssertNil(outcome.validatedInput)
        XCTAssertEqual(
            outcome.errors.constraints.additionalMonthlyIncomeUSD,
            "Monthly income must be zero or greater."
        )
    }

    func testValidFormPassesAnalyzeValidation() async {
        let snapshotID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let initialState = makeValidState()
        let outcome = initialState.makeValidatedDraft()
        let snapshot = PortfolioSnapshot(
            id: snapshotID,
            createdAt: createdAt,
            portfolio: outcome.validatedInput!.portfolio,
            constraints: outcome.validatedInput!.constraints,
            orders: outcome.validatedInput!.limitOrders
        )
        let analysis = PortfolioAnalysis(
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            generatedAt: createdAt,
            snapshotID: snapshotID,
            analysisMode: .deterministic,
            riskLevel: .low,
            portfolioSummary: PortfolioSummary(
                totalValueUSD: 0,
                stableValueUSD: 0,
                investedValueUSD: 0,
                stableAllocationPercentage: 0,
                openBuyOrdersUSD: 0,
                openSellOrdersUSD: 0,
                deployableStableUSD: 0,
                allocations: []
            ),
            marketSummary: MarketSummary(
                asOf: createdAt,
                overview: "Deterministic analysis."
            ),
            actions: [],
            assetAnalysis: [],
            warnings: []
        )
        let store = TestStore(initialState: initialState) {
            DashboardFeature()
        } withDependencies: {
            $0.date.now = createdAt
            $0.portfolioAnalysis.analyze = { _ in analysis }
            $0.portfolioPersistence = .noop
            $0.uuid = .constant(snapshotID)
        }

        await store.send(.analyzeButtonTapped) {
            $0.validationErrors = outcome.errors
            $0.validatedInput = outcome.validatedInput
            $0.snapshotPersistenceStatus = .saving
            $0.analysisSubmissionState = .submitting
            $0.pendingSnapshotForAnalysis = snapshot
        }
        await store.receive(.snapshotSaveFinished(snapshot: snapshot, result: .succeeded)) {
            $0.lastSavedSnapshot = snapshot
            $0.snapshotPersistenceStatus = .saved
        }
        await store.receive(
            .analysisRequestFinished(
                snapshotID: snapshotID,
                result: .succeeded(analysis)
            )
        ) {
            $0.pendingAnalysisForPersistence = analysis
        }
        await store.receive(
            .analysisSaveFinished(analysisID: analysis.id, result: .succeeded)
        ) {
            $0.analysisSubmissionState = .success
            $0.pendingSnapshotForAnalysis = nil
            $0.pendingAnalysisForPersistence = nil
            $0.completedAnalysis = analysis
            $0.analysisReadinessMessage =
                "Deterministic analysis complete."
        }

        XCTAssertNotNil(store.state.validatedInput)
    }

    func testInvalidFormDoesNotPassAnalyzeValidation() async {
        let id = UUID()
        var initialState = DashboardFeature.State()
        initialState.assetPositions = [
            AssetPositionDraft(id: id, symbol: "", amount: "-")
        ]
        let outcome = initialState.makeValidatedDraft()
        let store = TestStore(initialState: initialState) {
            DashboardFeature()
        }

        await store.send(.analyzeButtonTapped) {
            $0.validationErrors = outcome.errors
            $0.validatedInput = nil
            $0.analysisReadinessMessage = nil
        }

        XCTAssertNil(store.state.validatedInput)
        XCTAssertTrue(store.state.validationErrors.hasErrors)
    }

    func testDecimalParserAcceptsCommaDecimalSeparator() {
        let locale = Locale(identifier: "de_DE")

        XCTAssertEqual(
            DashboardDecimalParser.parse("3,45", locale: locale),
            Decimal(string: "3.45", locale: posixLocale)
        )
    }

    private var posixLocale: Locale {
        Locale(identifier: "en_US_POSIX")
    }

    private func makeValidState(
        symbol: String = "BTC",
        amount: String = "0.0198"
    ) -> DashboardFeature.State {
        var state = DashboardFeature.State()
        state.assetPositions = [
            AssetPositionDraft(id: UUID(), symbol: symbol, amount: amount)
        ]
        state.constraints.minimumStableReserveUSD = "1000"
        return state
    }

    private func makeEditStore(
        initialState: DashboardFeature.State = DashboardFeature.State(),
        now: Date = Date(timeIntervalSince1970: 1_750_000_000)
    ) -> TestStoreOf<DashboardFeature> {
        var client = PortfolioPersistenceClient.noop
        client.saveDashboardDraft = { _ in throw CancellationError() }

        return TestStore(initialState: initialState) {
            DashboardFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.date.now = now
            $0.portfolioPersistence = client
        }
    }
}
