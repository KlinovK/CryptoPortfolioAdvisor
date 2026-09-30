import ComposableArchitecture
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class AppFeatureTests: XCTestCase {
    func testInitialSelectedTabIsDashboard() {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        XCTAssertEqual(store.state.selectedTab, .dashboard)
    }

    func testChangingSelectedTabToHistoryUpdatesState() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.selectedTabChanged(.history)) {
            $0.selectedTab = .history
        }
    }

    func testDashboardActionIsRoutedToChildReducer() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.dashboard(.appeared)) {
            $0.dashboard.hasAppeared = true
        }
    }

    func testHistoryActionIsRoutedToChildReducer() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.history(.appeared)) {
            $0.history.hasAppeared = true
            $0.history.listGeneration = 1
            $0.history.latestGeneration = 1
            $0.history.selectionGeneration = 1
            $0.history.loadState = .configurationUnavailable
        }
    }

    func testDashboardCredentialDeletionInvalidatesActiveHistoryContext() async {
        var initial = AppFeature.State()
        initial.dashboard.configurationAvailable = true
        initial.history.configurationAvailable = true
        initial.history.loadState = .loaded
        initial.history.hasAppeared = true
        let store = TestStore(initialState: initial) {
            AppFeature()
        } withDependencies: {
            $0.ataCredentials.delete = { throw CredentialStoreError.tokenAbsent }
        }
        store.exhaustivity = .off
        await store.send(.dashboard(.credentialDeleteRequested))
        await store.receive(.history(.credentialContextChanged))
        XCTAssertEqual(store.state.history.loadState, .credentialRequired)
        XCTAssertFalse(store.state.history.hasAppeared)
        await store.finish()
    }

    func testActiveRootDoesNotInvokeLegacyAnalysisOrPersistence() async {
        var initial = AppFeature.State()
        initial.dashboard.configurationAvailable = true
        initial.history.configurationAvailable = true
        let legacyCalls = LockIsolated(0)
        let store = TestStore(initialState: initial) {
            AppFeature()
        } withDependencies: {
            $0.ataCredentials.load = { throw CredentialStoreError.tokenAbsent }
            $0.portfolioAnalysis.analyze = { _ in
                legacyCalls.withValue { $0 += 1 }
                throw PortfolioAnalysisClientError.liveClientNotConfigured
            }
            $0.portfolioPersistence.loadDashboardDraft = {
                legacyCalls.withValue { $0 += 1 }
                return nil
            }
            $0.portfolioPersistence.loadAnalyses = {
                legacyCalls.withValue { $0 += 1 }
                return []
            }
        }
        store.exhaustivity = .off
        await store.send(.dashboard(.appeared))
        await store.send(.history(.appeared))
        await store.finish()
        XCTAssertEqual(legacyCalls.value, 0)
    }
}
