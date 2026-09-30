import ComposableArchitecture
import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class ATAAnalysisDetailFeatureTests: XCTestCase {
    private var completed: ATAAnalysisDetail {
        get throws {
            let dto = try JSONDecoder().decode(
                ATAAnalysisDetailDTO.self, from: Data(ATAFoundationFixtures.detail.utf8))
            return try ATAResponseMapper.domain(from: dto)
        }
    }

    private var pending: ATAAnalysisDetail {
        get throws {
            let dto = try JSONDecoder().decode(
                ATAAnalysisDetailDTO.self, from: Data(ATAFoundationFixtures.pending.utf8))
            return try ATAResponseMapper.domain(from: dto)
        }
    }

    private func notFound() -> ATAClientError {
        .http(
            ATAHTTPFailure(
                statusCode: 404,
                error: ATAServiceError(
                    code: "analysis_not_found", message: "safe", reloadRequired: nil)))
    }

    func testSelectedRunUUIDIsUsedAndCompleteATAResultLoaded() async throws {
        let detail = try completed
        let requested = LockIsolated<[UUID]>([])
        let cpaCalls = LockIsolated(0)
        let store = TestStore(
            initialState: ATAAnalysisDetailFeature.State(
                runID: detail.run.runID, requestIdentity: 3
            )
        ) {
            ATAAnalysisDetailFeature()
        } withDependencies: {
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
            $0.ataClient.loadAnalysis = { runID in
                requested.withValue { $0.append(runID) }
                return detail
            }
            $0.portfolioPersistence.loadAnalysis = { _ in
                cpaCalls.withValue { $0 += 1 }
                return nil
            }
        }
        store.exhaustivity = .off
        await store.send(.appeared)
        await store.receive(.loadFinished(identity: 3, generation: 1, result: .loaded(detail)))
        XCTAssertEqual(requested.value, [detail.run.runID])
        XCTAssertNotEqual(requested.value[0], detail.run.snapshotID)
        XCTAssertEqual(cpaCalls.value, 0)
        XCTAssertEqual(store.state.loadState, .loaded)
        XCTAssertEqual(store.state.detail?.result?.snapshotID, detail.run.snapshotID)
        XCTAssertEqual(
            store.state.detail?.result?.recommendations.first?.actionType, .keepLimitOrder)
        XCTAssertEqual(store.state.detail?.result?.reasoningMode, .aiAssisted)
        XCTAssertEqual(store.state.detail?.result?.marketRegime, .neutral)
        XCTAssertEqual(
            store.state.detail?.result?.warnings, ["stable_reserve_deficit", "future_diagnostic"])
        XCTAssertNotNil(store.state.detail?.result?.configuration)
        XCTAssertNotNil(store.state.detail?.result?.active?.setups.first?.trigger)
    }

    func testNilResultAndFailureCategoryAreLegitimateMetadataOnlyStates() async throws {
        let pending = try pending
        let failed = ATAAnalysisDetail(
            run: pending.run, result: nil, failureCategory: "market_unavailable")
        let store = TestStore(
            initialState: ATAAnalysisDetailFeature.State(
                runID: pending.run.runID, requestIdentity: 1
            )
        ) { ATAAnalysisDetailFeature() }
        store.exhaustivity = .off
        await store.send(.loadFinished(identity: 1, generation: 0, result: .loaded(failed)))
        XCTAssertEqual(store.state.loadState, .loadedWithoutResult)
        XCTAssertNil(store.state.detail?.result)
        XCTAssertEqual(store.state.detail?.failureCategory, "market_unavailable")
        XCTAssertNil(store.state.detail?.run.marketCutoff)
    }

    func testAnalysisNotFoundAndTransportFailureSupportManualRetry() async throws {
        let detail = try completed
        let attempts = LockIsolated(0)
        let missing = notFound()
        let store = TestStore(
            initialState: ATAAnalysisDetailFeature.State(
                runID: detail.run.runID, requestIdentity: 1
            )
        ) {
            ATAAnalysisDetailFeature()
        } withDependencies: {
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
            $0.ataClient.loadAnalysis = { _ in
                let attempt = attempts.withValue { value -> Int in
                    value += 1
                    return value
                }
                if attempt == 1 { throw missing }
                if attempt == 2 { throw ATAClientError.transport(.timeout) }
                return detail
            }
        }
        store.exhaustivity = .off
        await store.send(.appeared)
        await store.receive(.loadFinished(identity: 1, generation: 1, result: .failed(.notFound)))
        XCTAssertEqual(store.state.loadState, .notFound)
        await store.send(.retryTapped)
        await store.receive(.loadFinished(identity: 1, generation: 2, result: .failed(.transport)))
        XCTAssertEqual(store.state.loadState, .failed(.transport))
        await store.send(.retryTapped)
        await store.receive(.loadFinished(identity: 1, generation: 3, result: .loaded(detail)))
        XCTAssertEqual(store.state.loadState, .loaded)
        XCTAssertEqual(attempts.value, 3)
    }

    func testMissingCredentialNeverCallsDetailEndpoint() async throws {
        let detail = try completed
        let calls = LockIsolated(0)
        let store = TestStore(
            initialState: ATAAnalysisDetailFeature.State(
                runID: detail.run.runID, requestIdentity: 1
            )
        ) {
            ATAAnalysisDetailFeature()
        } withDependencies: {
            $0.ataCredentials.load = { throw CredentialStoreError.tokenAbsent }
            $0.ataClient.loadAnalysis = { _ in
                calls.withValue { $0 += 1 }
                return detail
            }
        }
        store.exhaustivity = .off
        await store.send(.appeared)
        await store.receive(
            .loadFinished(
                identity: 1, generation: 1, result: .failed(.credentialRequired)))
        XCTAssertEqual(calls.value, 0)
        XCTAssertNil(store.state.detail)
    }

    func testRapidSelectionIgnoresOldRunAndOlderRetryResponse() async throws {
        let detail = try completed
        let nextID = UUID(uuidString: "00000000-0000-4000-8000-000000000109")!
        let nextRun = ATAAnalysisRun(
            runID: nextID, snapshotID: UUID(), startedAt: detail.run.startedAt,
            status: .running, completedAt: nil, marketCutoff: nil)
        let next = ATAAnalysisDetail(run: nextRun, result: nil, failureCategory: nil)
        let store = TestStore(
            initialState: ATAAnalysisDetailFeature.State(
                runID: nextID, requestIdentity: 2
            )
        ) { ATAAnalysisDetailFeature() }
        store.exhaustivity = .off
        await store.send(.loadFinished(identity: 1, generation: 0, result: .loaded(detail)))
        XCTAssertNil(store.state.detail)
        await store.send(.loadFinished(identity: 2, generation: 0, result: .loaded(next)))
        XCTAssertEqual(store.state.detail?.run.runID, nextID)
        XCTAssertEqual(store.state.loadState, .loadedWithoutResult)
        await store.send(.loadFinished(identity: 2, generation: -1, result: .loaded(detail)))
        XCTAssertEqual(store.state.detail?.run.runID, nextID)
    }

    func testMismatchedServerRunIsRejectedAndHistoricalSnapshotNotSubstituted() async throws {
        let detail = try completed
        let anotherRun = UUID()
        let store = TestStore(
            initialState: ATAAnalysisDetailFeature.State(
                runID: anotherRun, requestIdentity: 5
            )
        ) { ATAAnalysisDetailFeature() }
        store.exhaustivity = .off
        await store.send(.loadFinished(identity: 5, generation: 0, result: .loaded(detail)))
        XCTAssertEqual(store.state.loadState, .failed(.incompatibleResponse))
        XCTAssertNil(store.state.detail)
    }
}
