import ComposableArchitecture

@Reducer
struct AppFeature {
    enum Tab: Hashable {
        case dashboard
        case history
    }

    @ObservableState
    struct State: Equatable {
        var dashboard = ATADashboardFeature.State()
        var history = ATAHistoryFeature.State()
        var selectedTab: Tab = .dashboard
    }

    enum Action: Equatable {
        case dashboard(ATADashboardFeature.Action)
        case history(ATAHistoryFeature.Action)
        case selectedTabChanged(Tab)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.dashboard, action: \.dashboard) {
            ATADashboardFeature()
        }

        Scope(state: \.history, action: \.history) {
            ATAHistoryFeature()
        }

        Reduce { state, action in
            switch action {
            case .selectedTabChanged(let tab):
                state.selectedTab = tab
                return .none

            case .dashboard(.credentialSaveRequested), .dashboard(.credentialDeleteRequested):
                return .send(.history(.credentialContextChanged))

            case .dashboard, .history:
                return .none
            }
        }
    }
}
