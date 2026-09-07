import ComposableArchitecture
import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class DashboardPersistenceTests: XCTestCase {
    func testDashboardRestoresSavedDraft() async {
        let draft = makePersistedDraft()
        var client = PortfolioPersistenceClient.noop
        client.loadDashboardDraft = { draft }
        client.loadLatestSnapshot = {
            XCTFail("Latest snapshot should not load when a draft exists.")
            return nil
        }
        let store = TestStore(initialState: DashboardFeature.State()) {
            DashboardFeature()
        } withDependencies: {
            $0.portfolioPersistence = client
        }

        await store.send(.restoreRequested) {
            $0.hasAttemptedRestore = true
            $0.draftPersistenceStatus = .loading
        }
        await store.receive(
            .restorationFinished(revision: 0, result: .draft(draft))
        ) {
            $0.restore(from: draft)
            $0.draftPersistenceStatus = .saved
        }
    }

    func testDashboardUsesDefaultsWhenPersistenceIsEmpty() async {
        let store = TestStore(initialState: DashboardFeature.State()) {
            DashboardFeature()
        } withDependencies: {
            $0.portfolioPersistence = .noop
        }

        await store.send(.restoreRequested) {
            $0.hasAttemptedRestore = true
            $0.draftPersistenceStatus = .loading
        }
        await store.receive(.restorationFinished(revision: 0, result: .none)) {
            $0.draftPersistenceStatus = .idle
        }

        XCTAssertEqual(store.state.constraints, TradingConstraintsDraft())
        XCTAssertTrue(store.state.assetPositions.isEmpty)
        XCTAssertTrue(store.state.limitOrders.isEmpty)
    }

    func testLatestSnapshotInitializesNewDraftWhenCurrentDraftIsMissing() async throws {
        let positionID = UUID(uuidString: "99999999-AAAA-BBBB-CCCC-DDDDDDDDDDDD")!
        let orderID = UUID(uuidString: "EEEEEEEE-FFFF-AAAA-BBBB-CCCCCCCCCCCC")!
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let resolvedAt = Date(timeIntervalSince1970: 1_750_086_400)
        let snapshot = PortfolioSnapshot(
            id: UUID(),
            createdAt: createdAt,
            portfolio: try Portfolio(
                positions: [
                    try AssetPosition(
                        symbol: AssetSymbol("LINK"),
                        amount: Decimal(string: "42.125")!
                    )
                ]
            ),
            constraints: try TradingConstraints(
                tradingStyle: .active,
                riskTolerance: .moderate,
                leverageAllowed: false,
                additionalMonthlyIncomeUSD: 0,
                minimumStableReserveUSD: Decimal(string: "1000.50")!
            ),
            orders: [
                try LimitOrder(
                    id: orderID,
                    symbol: .btc,
                    side: .sell,
                    amountUSD: Decimal(string: "200.25")!,
                    targetPrice: Decimal(string: "76500.125")!,
                    status: .filled,
                    createdAt: createdAt,
                    resolvedAt: resolvedAt
                )
            ]
        )
        var client = PortfolioPersistenceClient.noop
        client.loadLatestSnapshot = { snapshot }
        let store = TestStore(initialState: DashboardFeature.State()) {
            DashboardFeature()
        } withDependencies: {
            $0.portfolioPersistence = client
            $0.uuid = .constant(positionID)
        }

        await store.send(.restoreRequested) {
            $0.hasAttemptedRestore = true
            $0.draftPersistenceStatus = .loading
        }
        await store.receive(
            .restorationFinished(revision: 0, result: .snapshot(snapshot))
        ) {
            $0.assetPositions = [
                AssetPositionDraft(id: positionID, symbol: "LINK", amount: "42.125")
            ]
            $0.constraints = TradingConstraintsDraft(
                tradingStyle: .active,
                riskTolerance: .moderate,
                leverageAllowed: false,
                additionalMonthlyIncomeUSD: "0",
                minimumStableReserveUSD: "1000.5"
            )
            $0.limitOrders = [
                LimitOrderDraft(
                    id: orderID,
                    symbol: "BTC",
                    side: .sell,
                    amountUSD: "200.25",
                    targetPrice: "76500.125",
                    status: .filled,
                    createdAt: createdAt,
                    resolvedAt: resolvedAt
                )
            ]
            $0.draftPersistenceStatus = .saved
        }
    }

    func testEditingSchedulesAutosave() async {
        let clock = TestClock()
        let savedDrafts = LockIsolated<[PersistedDashboardDraft]>([])
        var client = PortfolioPersistenceClient.noop
        client.saveDashboardDraft = { draft in
            savedDrafts.withValue { $0.append(draft) }
        }
        var initialState = DashboardFeature.State()
        initialState.assetPositions = [
            AssetPositionDraft(id: assetID, symbol: "BTC", amount: "1")
        ]
        let store = TestStore(initialState: initialState) {
            DashboardFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.portfolioPersistence = client
        }

        await store.send(.assetSymbolChanged(id: assetID, value: "link")) {
            $0.assetPositions[0].symbol = "LINK"
            $0.draftRevision = 1
            $0.draftPersistenceStatus = .saving
        }
        await clock.advance(by: .milliseconds(399))
        XCTAssertTrue(savedDrafts.value.isEmpty)

        await clock.advance(by: .milliseconds(1))
        await store.receive(.draftSaveFinished(revision: 1, result: .succeeded)) {
            $0.draftPersistenceStatus = .saved
        }
        XCTAssertEqual(savedDrafts.value.first?.assetPositions.first?.symbol, "LINK")
    }

    func testNewEditCancelsPreviousPendingAutosave() async {
        let clock = TestClock()
        let savedDrafts = LockIsolated<[PersistedDashboardDraft]>([])
        var client = PortfolioPersistenceClient.noop
        client.saveDashboardDraft = { draft in
            savedDrafts.withValue { $0.append(draft) }
        }
        var initialState = DashboardFeature.State()
        initialState.assetPositions = [AssetPositionDraft(id: assetID)]
        let store = TestStore(initialState: initialState) {
            DashboardFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.portfolioPersistence = client
        }

        await store.send(.assetAmountChanged(id: assetID, value: "0.")) {
            $0.assetPositions[0].amount = "0."
            $0.draftRevision = 1
            $0.draftPersistenceStatus = .saving
        }
        await clock.advance(by: .milliseconds(200))

        await store.send(.assetAmountChanged(id: assetID, value: "0.0198")) {
            $0.assetPositions[0].amount = "0.0198"
            $0.draftRevision = 2
        }
        await clock.advance(by: .milliseconds(399))
        XCTAssertTrue(savedDrafts.value.isEmpty)

        await clock.advance(by: .milliseconds(1))
        await store.receive(.draftSaveFinished(revision: 2, result: .succeeded)) {
            $0.draftPersistenceStatus = .saved
        }
        XCTAssertEqual(savedDrafts.value.count, 1)
        XCTAssertEqual(savedDrafts.value[0].assetPositions[0].amount, "0.0198")
    }

    func testValidAnalyzeCreatesAndSavesSnapshot() async throws {
        let snapshotID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let savedSnapshots = LockIsolated<[PortfolioSnapshot]>([])
        var client = PortfolioPersistenceClient.noop
        client.saveSnapshot = { snapshot in
            savedSnapshots.withValue { $0.append(snapshot) }
        }
        let initialState = makeValidState()
        let validation = initialState.makeValidatedDraft()
        let validatedInput = try XCTUnwrap(validation.validatedInput)
        let expectedSnapshot = PortfolioSnapshot(
            id: snapshotID,
            createdAt: createdAt,
            portfolio: validatedInput.portfolio,
            constraints: validatedInput.constraints,
            orders: validatedInput.limitOrders
        )
        let expectedAnalysis = makeAnalysis(
            snapshotID: snapshotID,
            generatedAt: createdAt
        )
        let store = TestStore(initialState: initialState) {
            DashboardFeature()
        } withDependencies: {
            $0.date.now = createdAt
            $0.portfolioAnalysis.analyze = { _ in expectedAnalysis }
            $0.portfolioPersistence = client
            $0.uuid = .constant(snapshotID)
        }

        await store.send(.analyzeButtonTapped) {
            $0.validationErrors = validation.errors
            $0.validatedInput = validatedInput
            $0.snapshotPersistenceStatus = .saving
            $0.analysisSubmissionState = .submitting
            $0.pendingSnapshotForAnalysis = expectedSnapshot
        }
        await store.receive(
            .snapshotSaveFinished(snapshot: expectedSnapshot, result: .succeeded)
        ) {
            $0.lastSavedSnapshot = expectedSnapshot
            $0.snapshotPersistenceStatus = .saved
        }
        await store.receive(
            .analysisRequestFinished(
                snapshotID: snapshotID,
                result: .succeeded(expectedAnalysis)
            )
        ) {
            $0.pendingAnalysisForPersistence = expectedAnalysis
        }
        await store.receive(
            .analysisSaveFinished(analysisID: expectedAnalysis.id, result: .succeeded)
        ) {
            $0.completedAnalysis = expectedAnalysis
            $0.analysisSubmissionState = .success
            $0.analysisReadinessMessage =
                "Deterministic analysis complete."
            $0.pendingSnapshotForAnalysis = nil
            $0.pendingAnalysisForPersistence = nil
        }

        XCTAssertEqual(savedSnapshots.value, [expectedSnapshot])
    }

    func testInvalidAnalyzeDoesNotSaveSnapshot() async {
        let savedSnapshots = LockIsolated<[PortfolioSnapshot]>([])
        var client = PortfolioPersistenceClient.noop
        client.saveSnapshot = { snapshot in
            savedSnapshots.withValue { $0.append(snapshot) }
        }
        var initialState = DashboardFeature.State()
        initialState.assetPositions = [AssetPositionDraft(id: assetID, symbol: "", amount: "-")]
        let validation = initialState.makeValidatedDraft()
        let store = TestStore(initialState: initialState) {
            DashboardFeature()
        } withDependencies: {
            $0.portfolioPersistence = client
        }

        await store.send(.analyzeButtonTapped) {
            $0.validationErrors = validation.errors
            $0.validatedInput = nil
        }

        XCTAssertTrue(savedSnapshots.value.isEmpty)
    }

    func testAutosaveFailureLeavesInMemoryDraftUsable() async {
        let clock = TestClock()
        var client = PortfolioPersistenceClient.noop
        client.saveDashboardDraft = { _ in throw TestPersistenceError.expected }
        var initialState = DashboardFeature.State()
        initialState.assetPositions = [AssetPositionDraft(id: assetID)]
        let store = TestStore(initialState: initialState) {
            DashboardFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.portfolioPersistence = client
        }

        await store.send(.assetSymbolChanged(id: assetID, value: "link")) {
            $0.assetPositions[0].symbol = "LINK"
            $0.draftRevision = 1
            $0.draftPersistenceStatus = .saving
        }
        await clock.advance(by: .milliseconds(400))
        await store.receive(.draftSaveFinished(revision: 1, result: .failed)) {
            $0.draftPersistenceStatus = .failed("Unable to save changes locally.")
        }

        XCTAssertEqual(store.state.assetPositions[0].symbol, "LINK")
    }

    func testLoadingFailureLeavesProductDefaultsUsable() async {
        var client = PortfolioPersistenceClient.noop
        client.loadDashboardDraft = { throw TestPersistenceError.expected }
        let store = TestStore(initialState: DashboardFeature.State()) {
            DashboardFeature()
        } withDependencies: {
            $0.portfolioPersistence = client
        }

        await store.send(.restoreRequested) {
            $0.hasAttemptedRestore = true
            $0.draftPersistenceStatus = .loading
        }
        await store.receive(.restorationFinished(revision: 0, result: .failed)) {
            $0.draftPersistenceStatus = .failed("Unable to load saved portfolio.")
        }

        XCTAssertEqual(store.state.constraints, TradingConstraintsDraft())
        XCTAssertTrue(store.state.assetPositions.isEmpty)
    }

    private let assetID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func makePersistedDraft() -> PersistedDashboardDraft {
        PersistedDashboardDraft(
            assetPositions: [
                PersistedAssetDraft(id: assetID, symbol: "LINK", amount: "0.")
            ],
            constraints: PersistedTradingConstraintsDraft(
                tradingStyle: .active,
                riskTolerance: .moderate,
                leverageAllowed: false,
                additionalMonthlyIncomeUSD: "-",
                minimumStableReserveUSD: "1000."
            ),
            limitOrders: []
        )
    }

    private func makeValidState() -> DashboardFeature.State {
        var state = DashboardFeature.State()
        state.assetPositions = [
            AssetPositionDraft(id: assetID, symbol: "LINK", amount: "42.125")
        ]
        state.constraints.minimumStableReserveUSD = "1000"
        return state
    }

    private func makeAnalysis(snapshotID: UUID, generatedAt: Date) -> PortfolioAnalysis {
        PortfolioAnalysis(
            id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
            generatedAt: generatedAt,
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
                asOf: generatedAt,
                overview: "Deterministic analysis."
            ),
            actions: [],
            assetAnalysis: [],
            warnings: []
        )
    }
}

private enum TestPersistenceError: Error {
    case expected
}
