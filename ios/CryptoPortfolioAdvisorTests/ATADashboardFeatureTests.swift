import ComposableArchitecture
import Foundation
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class ATADashboardFeatureTests: XCTestCase {
    private var portfolio: ATACurrentPortfolio {
        get throws {
            let dto = try JSONDecoder().decode(
                ATACurrentPortfolioDTO.self, from: Data(ATAFoundationFixtures.portfolio.utf8))
            return try ATAResponseMapper.domain(from: dto)
        }
    }

    private func makeStore(
        configured: Bool = true,
        loadCredential: @escaping @Sendable () async throws -> ATABearerToken = {
            try ATABearerToken("synthetic-offline-token")
        },
        loadPortfolio: @escaping @Sendable () async throws -> ATACurrentPortfolio = {
            throw ATAClientError.invalidResponse
        },
        saveCredential: @escaping @Sendable (ATABearerToken) async throws -> Void = { _ in },
        deleteCredential: @escaping @Sendable () async throws -> Void = {}
    ) -> TestStoreOf<ATADashboardFeature> {
        TestStore(
            initialState: ATADashboardFeature.State(configurationAvailable: configured)
        ) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataCredentials = CredentialStore(
                load: loadCredential, save: saveCredential, delete: deleteCredential)
            $0.ataClient.loadPortfolio = loadPortfolio
        }
    }

    func testMissingConfigurationNeverLoadsCredentialOrPortfolio() async {
        let credentialCalls = LockIsolated(0)
        let portfolioCalls = LockIsolated(0)
        let store = makeStore(
            configured: false,
            loadCredential: {
                credentialCalls.withValue { $0 += 1 }
                throw CredentialStoreError.tokenAbsent
            },
            loadPortfolio: {
                portfolioCalls.withValue { $0 += 1 }
                throw ATAClientError.invalidResponse
            })
        await store.send(.appeared) { $0.hasAppeared = true }
        XCTAssertEqual(store.state.loadState, .configurationUnavailable)
        XCTAssertEqual(credentialCalls.value, 0)
        XCTAssertEqual(portfolioCalls.value, 0)
    }

    func testMissingCredentialMakesNoRequest() async {
        let requests = LockIsolated(0)
        let store = makeStore(
            loadCredential: { throw CredentialStoreError.tokenAbsent },
            loadPortfolio: {
                requests.withValue { $0 += 1 }
                throw ATAClientError.invalidResponse
            })
        await store.send(.appeared) {
            $0.hasAppeared = true
            $0.requestGeneration = 1
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(generation: 1, result: .credentialRequired)) {
            $0.loadState = .credentialRequired
        }
        XCTAssertEqual(requests.value, 0)
    }

    func testInitialReadPreservesServerRevisionAccountsAndAggregates() async throws {
        let expected = try portfolio
        let calls = LockIsolated(0)
        let store = makeStore(loadPortfolio: {
            calls.withValue { $0 += 1 }
            return expected
        })
        await store.send(.appeared) {
            $0.hasAppeared = true
            $0.requestGeneration = 1
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(generation: 1, result: .loaded(expected))) {
            $0.portfolio = expected
            $0.loadState = .loaded
        }
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(store.state.portfolio?.revision, 7)
        XCTAssertEqual(store.state.portfolio?.accounts.count, 2)
        XCTAssertEqual(store.state.portfolio?.accounts[0].positions[0].symbol, .btc)
        XCTAssertEqual(store.state.portfolio?.accounts[1].positions[0].symbol, .btc)
        XCTAssertEqual(store.state.portfolio?.aggregatePositions.count, 3)
        XCTAssertEqual(store.state.portfolio?.financialSettings.monthlyExpensesUSD, 250)
        XCTAssertEqual(store.state.portfolio?.corePositions.count, 1)
        XCTAssertEqual(store.state.portfolio?.limitOrders.count, 2)
    }

    func testActiveDashboardNeverRestoresAutosavesOrSubmitsCPAAnalysis() async throws {
        let expected = try portfolio
        let legacyCalls = LockIsolated(0)
        let store = TestStore(
            initialState: ATADashboardFeature.State(configurationAvailable: true)
        ) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
            $0.ataClient.loadPortfolio = { expected }
            $0.portfolioPersistence.loadDashboardDraft = {
                legacyCalls.withValue { $0 += 1 }
                return nil
            }
            $0.portfolioPersistence.loadLatestSnapshot = {
                legacyCalls.withValue { $0 += 1 }
                return nil
            }
            $0.portfolioPersistence.saveDashboardDraft = { _ in
                legacyCalls.withValue { $0 += 1 }
            }
            $0.portfolioPersistence.saveSnapshot = { _ in
                legacyCalls.withValue { $0 += 1 }
            }
            $0.portfolioAnalysis.analyze = { _ in
                legacyCalls.withValue { $0 += 1 }
                throw PortfolioAnalysisClientError.liveClientNotConfigured
            }
        }
        await store.send(.appeared) {
            $0.hasAppeared = true
            $0.requestGeneration = 1
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(generation: 1, result: .loaded(expected))) {
            $0.portfolio = expected
            $0.loadState = .loaded
        }
        XCTAssertEqual(legacyCalls.value, 0)
    }

    func testPortfolioNotFoundIsUninitialized() async {
        let error = ATAClientError.http(
            ATAHTTPFailure(
                statusCode: 404,
                error: ATAServiceError(
                    code: "portfolio_not_found", message: "sanitized", reloadRequired: nil)))
        let store = makeStore(loadPortfolio: { throw error })
        await store.send(.appeared) {
            $0.hasAppeared = true
            $0.requestGeneration = 1
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(generation: 1, result: .uninitialized)) {
            $0.loadState = .uninitialized
        }
        XCTAssertNil(store.state.portfolio)
    }

    func testUnauthorizedClearsLoadedPortfolio() async throws {
        let previous = try portfolio
        let error = ATAClientError.http(
            ATAHTTPFailure(
                statusCode: 401,
                error: ATAServiceError(
                    code: "unauthorized", message: "sanitized", reloadRequired: nil)))
        var initial = ATADashboardFeature.State(configurationAvailable: true)
        initial.portfolio = previous
        initial.loadState = .loaded
        let store = TestStore(initialState: initial) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
            $0.ataClient.loadPortfolio = { throw error }
        }
        await store.send(.refreshTapped) {
            $0.requestGeneration = 1
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(generation: 1, result: .failed(.authentication))) {
            $0.portfolio = nil
            $0.loadState = .failed(.authentication)
        }
    }

    func testTransportAndMalformedResponsesAreDistinct() async {
        for (error, failure) in [
            (ATAClientError.transport(.connection), ATADashboardFeature.Failure.transport),
            (ATAClientError.invalidResponse, .incompatibleResponse),
        ] {
            let store = makeStore(loadPortfolio: { throw error })
            await store.send(.appeared) {
                $0.hasAppeared = true
                $0.requestGeneration = 1
                $0.loadState = .loading
            }
            await store.receive(.loadFinished(generation: 1, result: .failed(failure))) {
                $0.loadState = .failed(failure)
            }
        }
    }

    func testInvalidClientConfigurationAndServerFailureAreSafeStates() async {
        let serviceError = ATAClientError.http(
            ATAHTTPFailure(
                statusCode: 500,
                error: ATAServiceError(
                    code: "internal_error", message: "untrusted server text", reloadRequired: nil)))
        for (error, result, state) in [
            (
                ATAClientError.invalidConfiguration,
                ATADashboardFeature.LoadResult.configurationUnavailable,
                ATADashboardFeature.LoadState.configurationUnavailable
            ),
            (serviceError, .failed(.service), .failed(.service)),
        ] {
            let store = makeStore(loadPortfolio: { throw error })
            await store.send(.appeared) {
                $0.hasAppeared = true
                $0.requestGeneration = 1
                $0.loadState = .loading
            }
            await store.receive(.loadFinished(generation: 1, result: result)) {
                if result == .configurationUnavailable { $0.configurationAvailable = false }
                $0.loadState = state
            }
        }
    }

    func testRetryAfterFailureLoadsPortfolio() async throws {
        let expected = try portfolio
        let calls = LockIsolated(0)
        let store = makeStore(loadPortfolio: {
            let count = calls.withValue { value in
                value += 1
                return value
            }
            if count == 1 { throw ATAClientError.transport(.timeout) }
            return expected
        })
        await store.send(.appeared) {
            $0.hasAppeared = true
            $0.requestGeneration = 1
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(generation: 1, result: .failed(.transport))) {
            $0.loadState = .failed(.transport)
        }
        await store.send(.retryTapped) {
            $0.requestGeneration = 2
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(generation: 2, result: .loaded(expected))) {
            $0.portfolio = expected
            $0.loadState = .loaded
        }
        XCTAssertEqual(calls.value, 2)
    }

    func testRefreshFailureKeepsLastConfirmedPortfolio() async throws {
        let expected = try portfolio
        var initial = ATADashboardFeature.State(configurationAvailable: true)
        initial.portfolio = expected
        initial.loadState = .loaded
        let store = TestStore(initialState: initial) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
            $0.ataClient.loadPortfolio = { throw ATAClientError.transport(.timeout) }
        }
        await store.send(.refreshTapped) {
            $0.requestGeneration = 1
            $0.loadState = .loading
        }
        XCTAssertEqual(store.state.portfolio, expected)
        XCTAssertTrue(store.state.isRefreshing)
        await store.receive(.loadFinished(generation: 1, result: .failed(.transport))) {
            $0.loadState = .failed(.transport)
        }
        XCTAssertEqual(store.state.portfolio, expected)
    }

    func testRefreshReplacesOnlyWithNewServerPortfolio() async throws {
        let previous = try portfolio
        let updated = ATACurrentPortfolio(
            revision: 13, snapshotID: previous.snapshotID, confirmedAt: previous.confirmedAt,
            accounts: previous.accounts, aggregatePositions: previous.aggregatePositions,
            financialSettings: previous.financialSettings, corePositions: previous.corePositions,
            limitOrders: previous.limitOrders)
        var initial = ATADashboardFeature.State(configurationAvailable: true)
        initial.portfolio = previous
        initial.loadState = .loaded
        let store = TestStore(initialState: initial) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataCredentials.load = { try ATABearerToken("synthetic-offline-token") }
            $0.ataClient.loadPortfolio = { updated }
        }
        await store.send(.refreshTapped) {
            $0.requestGeneration = 1
            $0.loadState = .loading
        }
        XCTAssertEqual(store.state.portfolio?.revision, 7)
        await store.receive(.loadFinished(generation: 1, result: .loaded(updated))) {
            $0.portfolio = updated
            $0.loadState = .loaded
        }
        XCTAssertEqual(store.state.portfolio?.revision, 13)
    }

    func testLateEarlierResponseCannotOverwriteLaterResult() async throws {
        let earlier = try portfolio
        let later = ATACurrentPortfolio(
            revision: 8, snapshotID: earlier.snapshotID, confirmedAt: earlier.confirmedAt,
            accounts: earlier.accounts, aggregatePositions: earlier.aggregatePositions,
            financialSettings: earlier.financialSettings, corePositions: earlier.corePositions,
            limitOrders: earlier.limitOrders)
        var initial = ATADashboardFeature.State(configurationAvailable: true)
        initial.requestGeneration = 2
        initial.loadState = .loading
        let store = TestStore(initialState: initial) { ATADashboardFeature() }
        await store.send(.loadFinished(generation: 2, result: .loaded(later))) {
            $0.portfolio = later
            $0.loadState = .loaded
        }
        await store.send(.loadFinished(generation: 1, result: .loaded(earlier)))
        XCTAssertEqual(store.state.portfolio?.revision, 8)
    }

    func testCredentialSaveThenDeleteClearsPortfolio() async throws {
        let expected = try portfolio
        let saved = LockIsolated(0)
        let deleted = LockIsolated(0)
        let store = makeStore(
            loadPortfolio: { expected },
            saveCredential: { _ in saved.withValue { $0 += 1 } },
            deleteCredential: { deleted.withValue { $0 += 1 } })
        let token = try ATABearerToken("synthetic-offline-token")
        await store.send(.credentialSaveRequested(token)) {
            $0.requestGeneration = 1
            $0.loadState = .credentialRequired
            $0.credentialOperation = .saving
        }
        await store.receive(.credentialSaved(generation: 1, succeeded: true)) {
            $0.credentialOperation = .idle
            $0.requestGeneration = 2
            $0.loadState = .loading
        }
        await store.receive(.loadFinished(generation: 2, result: .loaded(expected))) {
            $0.portfolio = expected
            $0.loadState = .loaded
        }
        await store.send(.credentialDeleteRequested) {
            $0.requestGeneration = 3
            $0.portfolio = nil
            $0.loadState = .credentialRequired
            $0.credentialOperation = .deleting
        }
        await store.receive(.credentialDeleted(generation: 3, succeeded: true)) {
            $0.credentialOperation = .idle
        }
        XCTAssertEqual(saved.value, 1)
        XCTAssertEqual(deleted.value, 1)
        XCTAssertNil(store.state.portfolio)
    }

    func testCredentialReplacementHidesPreviousPortfolioBeforeLoad() async throws {
        let previous = try portfolio
        var initial = ATADashboardFeature.State(configurationAvailable: true)
        initial.portfolio = previous
        initial.loadState = .loaded
        let store = TestStore(initialState: initial) {
            ATADashboardFeature()
        } withDependencies: {
            $0.ataCredentials.save = { _ in throw CredentialStoreError.writeFailed }
        }
        await store.send(.credentialSaveRequested(try ATABearerToken("new-synthetic-token"))) {
            $0.requestGeneration = 1
            $0.portfolio = nil
            $0.loadState = .credentialRequired
            $0.credentialOperation = .saving
        }
        await store.receive(.credentialSaved(generation: 1, succeeded: false)) {
            $0.credentialOperation = .idle
            $0.loadState = .failed(.credentialStorage)
        }
        XCTAssertNil(store.state.portfolio)
    }
}
