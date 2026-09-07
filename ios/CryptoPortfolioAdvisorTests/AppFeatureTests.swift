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
        } withDependencies: {
            $0.portfolioPersistence = .noop
        }

        await store.send(.history(.appeared)) {
            $0.history.hasAppeared = true
            $0.history.loadState = .loading
        }
        await store.receive(.history(.loadFinished(.success([])))) {
            $0.history.loadState = .loaded
        }
    }
}
