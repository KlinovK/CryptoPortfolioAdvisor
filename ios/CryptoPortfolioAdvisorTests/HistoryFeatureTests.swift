import ComposableArchitecture
import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class HistoryFeatureTests: XCTestCase {
    func testHistoryLoadsAnalyses() async throws {
        let newer = try makeAnalysis(generatedAt: Date(timeIntervalSince1970: 200))
        let older = try makeAnalysis(generatedAt: Date(timeIntervalSince1970: 100))
        var client = PortfolioPersistenceClient.noop
        client.loadAnalyses = { [newer, older] }
        let store = makeStore(client: client)

        await store.send(.appeared) {
            $0.hasAppeared = true
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(.success([newer, older]))) {
            $0.analyses = [newer, older]
            $0.loadState = .loaded
        }
    }

    func testEmptyPersistenceProducesEmptyLoadedState() async {
        let store = makeStore(client: .noop)

        await store.send(.appeared) {
            $0.hasAppeared = true
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(.success([]))) {
            $0.loadState = .loaded
        }

        XCTAssertTrue(store.state.analyses.isEmpty)
    }

    func testPersistenceFailureProducesFailedState() async {
        var client = PortfolioPersistenceClient.noop
        client.loadAnalyses = { throw HistoryTestError.expected }
        let store = makeStore(client: client)

        await store.send(.appeared) {
            $0.hasAppeared = true
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(.failure)) {
            $0.loadState = .failed
        }
    }

    func testRetryTriggersAnotherLoad() async throws {
        let analysis = try makeAnalysis()
        let attempts = LockIsolated(0)
        var client = PortfolioPersistenceClient.noop
        client.loadAnalyses = {
            let attempt = attempts.withValue {
                $0 += 1
                return $0
            }
            if attempt == 1 {
                throw HistoryTestError.expected
            }
            return [analysis]
        }
        let store = makeStore(client: client)

        await store.send(.appeared) {
            $0.hasAppeared = true
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(.failure)) {
            $0.loadState = .failed
        }
        await store.send(.retryTapped) {
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(.success([analysis]))) {
            $0.analyses = [analysis]
            $0.loadState = .loaded
        }

        XCTAssertEqual(attempts.value, 2)
    }

    func testSelectingAnalysisOpensExactDetailsWithActionsAndWarnings() async throws {
        let first = try makeAnalysis(generatedAt: Date(timeIntervalSince1970: 200))
        let selected = try makeAnalysis(generatedAt: Date(timeIntervalSince1970: 100))
        var state = HistoryFeature.State()
        state.analyses = [first, selected]
        state.loadState = .loaded
        let store = TestStore(initialState: state) {
            HistoryFeature()
        }

        await store.send(.analysisTapped(selected.id)) {
            $0.destination = AnalysisDetailsFeature.State(analysis: selected)
        }

        XCTAssertEqual(store.state.destination?.analysis.actions, selected.actions)
        XCTAssertEqual(store.state.destination?.analysis.warnings, selected.warnings)
    }

    func testReappearingRefreshesAnalyses() async throws {
        let first = try makeAnalysis(generatedAt: Date(timeIntervalSince1970: 100))
        let addedLater = try makeAnalysis(generatedAt: Date(timeIntervalSince1970: 200))
        let attempts = LockIsolated(0)
        var client = PortfolioPersistenceClient.noop
        client.loadAnalyses = {
            let attempt = attempts.withValue {
                $0 += 1
                return $0
            }
            return attempt == 1 ? [first] : [addedLater, first]
        }
        let store = makeStore(client: client)

        await store.send(.appeared) {
            $0.hasAppeared = true
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(.success([first]))) {
            $0.analyses = [first]
            $0.loadState = .loaded
        }
        await store.send(.appeared) {
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(.success([addedLater, first]))) {
            $0.analyses = [addedLater, first]
            $0.loadState = .loaded
        }

        XCTAssertEqual(attempts.value, 2)
    }

    func testSnapshotWithoutAnalysisDoesNotAppearInHistory() async {
        let snapshotLoads = LockIsolated(0)
        var client = PortfolioPersistenceClient.noop
        client.loadSnapshots = {
            snapshotLoads.withValue { $0 += 1 }
            return []
        }
        client.loadAnalyses = { [] }
        let store = makeStore(client: client)

        await store.send(.appeared) {
            $0.hasAppeared = true
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(.success([]))) {
            $0.loadState = .loaded
        }

        XCTAssertTrue(store.state.analyses.isEmpty)
        XCTAssertEqual(snapshotLoads.value, 0)
    }

    private func makeStore(
        client: PortfolioPersistenceClient
    ) -> TestStoreOf<HistoryFeature> {
        TestStore(initialState: HistoryFeature.State()) {
            HistoryFeature()
        } withDependencies: {
            $0.portfolioPersistence = client
        }
    }

    private func makeAnalysis(
        id: UUID = UUID(),
        generatedAt: Date = Date(timeIntervalSince1970: 100)
    ) throws -> PortfolioAnalysis {
        let link = try AssetSymbol("LINK")
        return PortfolioAnalysis(
            id: id,
            generatedAt: generatedAt,
            snapshotID: UUID(),
            analysisMode: .deterministic,
            riskLevel: .low,
            portfolioSummary: PortfolioSummary(
                totalValueUSD: decimal("0"),
                stableValueUSD: decimal("0"),
                investedValueUSD: decimal("0"),
                stableAllocationPercentage: decimal("0"),
                openBuyOrdersUSD: decimal("0"),
                openSellOrdersUSD: decimal("0"),
                deployableStableUSD: decimal("0"),
                allocations: [
                    PortfolioAllocation(
                        asset: link,
                        valueUSD: decimal("0"),
                        allocationPercentage: decimal("0")
                    )
                ]
            ),
            marketSummary: MarketSummary(
                asOf: generatedAt,
                overview: "Deterministic analysis."
            ),
            actions: [
                PortfolioAction(
                    id: UUID(),
                    asset: link,
                    type: .wait,
                    side: nil,
                    price: nil,
                    amountUSD: nil,
                    priority: 1,
                    reason: "Wait for live data."
                )
            ],
            assetAnalysis: [
                AssetAnalysis(
                    asset: link,
                    valueUSD: 0,
                    allocationPercentage: 0,
                    assessment: "Quantity received.",
                    recommendation: "No AI recommendation."
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

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}

private enum HistoryTestError: Error, Sendable {
    case expected
}
