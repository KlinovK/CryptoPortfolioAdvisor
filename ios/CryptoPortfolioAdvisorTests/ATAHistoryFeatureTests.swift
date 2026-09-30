import ComposableArchitecture
import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

@MainActor
final class ATAHistoryFeatureTests: XCTestCase {
    private var recent: ATARecentAnalyses {
        get throws {
            let dto = try JSONDecoder().decode(
                ATARecentAnalysesDTO.self, from: Data(ATAFoundationFixtures.list.utf8))
            return try ATAResponseMapper.domain(from: dto)
        }
    }

    private var completed: ATAAnalysisDetail {
        get throws {
            let dto = try JSONDecoder().decode(
                ATAAnalysisDetailDTO.self, from: Data(ATAFoundationFixtures.detail.utf8))
            return try ATAResponseMapper.domain(from: dto)
        }
    }

    private func state() -> ATAHistoryFeature.State {
        ATAHistoryFeature.State(configurationAvailable: true)
    }

    private func notFound() -> ATAClientError {
        .http(
            ATAHTTPFailure(
                statusCode: 404,
                error: ATAServiceError(
                    code: "analysis_not_found", message: "safe", reloadRequired: nil)))
    }

    func testMissingConfigurationDoesNotReadServerOrLocalCPA() async {
        let calls = LockIsolated(0)
        let store = TestStore(initialState: ATAHistoryFeature.State()) {
            ATAHistoryFeature()
        } withDependencies: {
            $0.ataClient.loadAnalyses = { _ in
                calls.withValue { $0 += 1 }
                return ATARecentAnalyses(analyses: [])
            }
            $0.portfolioPersistence.loadAnalyses = {
                calls.withValue { $0 += 1 }
                return []
            }
        }
        store.exhaustivity = .off
        await store.send(.appeared)
        XCTAssertEqual(store.state.loadState, .configurationUnavailable)
        XCTAssertEqual(calls.value, 0)
    }

    func testMissingCredentialStopsBeforeATAAndCPALoads() async {
        let calls = LockIsolated(0)
        let store = TestStore(initialState: state()) {
            ATAHistoryFeature()
        } withDependencies: {
            $0.ataCredentials.load = { throw CredentialStoreError.tokenAbsent }
            $0.ataClient.loadAnalyses = { _ in
                calls.withValue { $0 += 1 }
                return ATARecentAnalyses(analyses: [])
            }
            $0.ataClient.loadLatestAnalysis = {
                calls.withValue { $0 += 1 }
                throw ATAClientError.invalidResponse
            }
            $0.portfolioPersistence.loadAnalyses = {
                calls.withValue { $0 += 1 }
                return []
            }
        }
        store.exhaustivity = .off
        await store.send(.appeared)
        await store.receive(\.listFinished)
        await store.finish()
        XCTAssertEqual(store.state.loadState, .credentialRequired)
        XCTAssertTrue(store.state.runs.isEmpty)
        XCTAssertEqual(calls.value, 0)
    }

    func testInitialRecentAndDedicatedLatestPreserveServerOrderAndBoundedLimit() async throws {
        let recent = try recent
        let completed = try completed
        let limits = LockIsolated<[Int]>([])
        let latestCalls = LockIsolated(0)
        let cpaCalls = LockIsolated(0)
        let latestGate = AsyncGate()
        let store = TestStore(initialState: state()) {
            ATAHistoryFeature()
        } withDependencies: {
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
            $0.ataClient.loadAnalyses = { limit in
                limits.withValue { $0.append(limit) }
                return recent
            }
            $0.ataClient.loadLatestAnalysis = {
                latestCalls.withValue { $0 += 1 }
                await latestGate.wait()
                return completed
            }
            $0.portfolioPersistence.loadAnalyses = {
                cpaCalls.withValue { $0 += 1 }
                return []
            }
        }
        store.exhaustivity = .off
        await store.send(.appeared)
        await store.receive(.listFinished(generation: 1, result: .loaded(recent)))
        await latestGate.open()
        await store.receive(.latestFinished(generation: 1, result: .loaded(completed)))
        await store.finish()
        XCTAssertEqual(store.state.loadState, .loaded)
        XCTAssertEqual(store.state.runs.map(\.runID), recent.analyses.map(\.runID))
        XCTAssertEqual(store.state.latestState, .available)
        XCTAssertEqual(store.state.latest, completed)
        XCTAssertEqual(limits.value, [20])
        XCTAssertEqual(latestCalls.value, 1)
        XCTAssertEqual(cpaCalls.value, 0)
    }

    func testEmptyListAndNoCompletedLatestAreIndependentStates() async {
        let missing = notFound()
        let latestGate = AsyncGate()
        let store = TestStore(initialState: state()) {
            ATAHistoryFeature()
        } withDependencies: {
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
            $0.ataClient.loadAnalyses = { _ in ATARecentAnalyses(analyses: []) }
            $0.ataClient.loadLatestAnalysis = {
                await latestGate.wait()
                throw missing
            }
        }
        store.exhaustivity = .off
        await store.send(.appeared)
        await store.receive(
            .listFinished(generation: 1, result: .loaded(ATARecentAnalyses(analyses: []))))
        await latestGate.open()
        await store.receive(.latestFinished(generation: 1, result: .unavailable))
        await store.finish()
        XCTAssertEqual(store.state.loadState, .empty)
        XCTAssertEqual(store.state.latestState, .unavailable)
        XCTAssertNil(store.state.latest)
    }

    func testTransientRefreshFailureRetainsOldServerListAsStaleAndRetryRecovers() async throws {
        let recent = try recent
        let completed = try completed
        let attempts = LockIsolated(0)
        let latestGate = AsyncGate()
        let store = TestStore(initialState: state()) {
            ATAHistoryFeature()
        } withDependencies: {
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
            $0.ataClient.loadAnalyses = { _ in
                let attempt = attempts.withValue { value -> Int in
                    value += 1
                    return value
                }
                if attempt == 2 { throw ATAClientError.transport(.connection) }
                return recent
            }
            $0.ataClient.loadLatestAnalysis = {
                await latestGate.wait()
                return completed
            }
        }
        store.exhaustivity = .off
        await store.send(.appeared)
        await store.receive(.listFinished(generation: 1, result: .loaded(recent)))
        await latestGate.open()
        await store.receive(.latestFinished(generation: 1, result: .loaded(completed)))
        await store.finish()
        await store.send(.refreshTapped)
        await store.receive(.listFinished(generation: 2, result: .failed(.transport)))
        await store.finish()
        XCTAssertEqual(store.state.loadState, .failed(.transport))
        XCTAssertEqual(store.state.runs, recent.analyses)
        await store.send(.retryTapped)
        await store.receive(.listFinished(generation: 3, result: .loaded(recent)))
        await store.finish()
        XCTAssertEqual(store.state.loadState, .loaded)
        XCTAssertEqual(attempts.value, 3)
    }

    func testUnauthorizedClearsPreviouslyLoadedAuthenticatedHistory() async throws {
        var initial = state()
        initial.runs = try recent.analyses
        initial.latest = try completed
        initial.loadState = .loaded
        initial.latestState = .available
        initial.listGeneration = 5
        initial.latestGeneration = 5
        let store = TestStore(initialState: initial) { ATAHistoryFeature() }
        store.exhaustivity = .off
        await store.send(.listFinished(generation: 5, result: .failed(.authentication)))
        XCTAssertTrue(store.state.runs.isEmpty)
        XCTAssertNil(store.state.latest)
        XCTAssertEqual(store.state.loadState, .credentialRequired)
        await store.send(.latestFinished(generation: 5, result: .loaded(try completed)))
        XCTAssertNil(store.state.latest)
    }

    func testMalformedLatestIsDistinctFromNoCompletedLatestAndAuthenticationClearsIt() async throws
    {
        var initial = state()
        initial.runs = try recent.analyses
        initial.latest = try completed
        initial.loadState = .loaded
        initial.latestState = .available
        initial.latestGeneration = 2
        let store = TestStore(initialState: initial) { ATAHistoryFeature() }
        store.exhaustivity = .off
        await store.send(
            .latestFinished(
                generation: 2,
                result: .failed(ATAAnalysisReadIssue.map(ATAClientError.invalidResponse))))
        XCTAssertEqual(store.state.latestState, .failed(.incompatibleResponse))
        XCTAssertEqual(store.state.latest, try completed)
        await store.send(.latestFinished(generation: 2, result: .failed(.authentication)))
        XCTAssertEqual(store.state.loadState, .credentialRequired)
        XCTAssertTrue(store.state.runs.isEmpty)
        XCTAssertNil(store.state.latest)
    }

    func testDetailAuthenticationFailureClearsHistoryAfterChildHandlesResponse() async throws {
        let runID = try recent.analyses[0].runID
        var initial = state()
        initial.runs = try recent.analyses
        initial.loadState = .loaded
        initial.destination = ATAAnalysisDetailFeature.State(runID: runID, requestIdentity: 1)
        let store = TestStore(initialState: initial) { ATAHistoryFeature() }
        store.exhaustivity = .off
        await store.send(
            .destination(
                .presented(
                    .loadFinished(
                        identity: 1, generation: 0, result: .failed(.authentication)))))
        await store.receive(.detailContextFailed(.authentication))
        XCTAssertNil(store.state.destination)
        XCTAssertTrue(store.state.runs.isEmpty)
        XCTAssertEqual(store.state.loadState, .credentialRequired)
    }

    func testOlderListReadCannotOverwriteNewerAcceptedHistory() async throws {
        var initial = state()
        initial.runs = try recent.analyses
        initial.loadState = .loaded
        initial.listGeneration = 8
        let store = TestStore(initialState: initial) { ATAHistoryFeature() }
        store.exhaustivity = .off
        await store.send(
            .listFinished(generation: 7, result: .loaded(ATARecentAnalyses(analyses: []))))
        XCTAssertEqual(store.state.runs, try recent.analyses)
        XCTAssertEqual(store.state.loadState, .loaded)
    }

    func testOlderListResponseAndCredentialChangeCannotRestoreOldContext() async throws {
        var initial = state()
        initial.runs = try recent.analyses
        initial.latest = try completed
        initial.listGeneration = 4
        initial.latestGeneration = 4
        initial.loadState = .loaded
        let store = TestStore(initialState: initial) { ATAHistoryFeature() }
        store.exhaustivity = .off
        await store.send(.credentialContextChanged)
        XCTAssertTrue(store.state.runs.isEmpty)
        XCTAssertNil(store.state.latest)
        await store.send(.listFinished(generation: 4, result: .loaded(try recent)))
        await store.send(.latestFinished(generation: 4, result: .loaded(try completed)))
        XCTAssertTrue(store.state.runs.isEmpty)
        XCTAssertNil(store.state.latest)
    }

    func testRunAndLatestSelectionUseRunIdentityNotSnapshotIdentity() async throws {
        var initial = state()
        initial.runs = try recent.analyses
        initial.latest = try completed
        initial.loadState = .loaded
        initial.latestState = .available
        let store = TestStore(initialState: initial) { ATAHistoryFeature() }
        store.exhaustivity = .off
        let selected = try recent.analyses[1]
        await store.send(.runTapped(selected.runID))
        XCTAssertEqual(store.state.destination?.runID, selected.runID)
        XCTAssertNotEqual(store.state.destination?.runID, selected.snapshotID)
        await store.send(.latestTapped)
        XCTAssertEqual(store.state.destination?.runID, try completed.run.runID)
    }
}
