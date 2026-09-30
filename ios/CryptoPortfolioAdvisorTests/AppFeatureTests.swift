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
}
