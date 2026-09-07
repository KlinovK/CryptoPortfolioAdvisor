import ComposableArchitecture

@Reducer
struct SnapshotDetailsFeature {
    @ObservableState
    struct State: Equatable {
        let snapshot: PortfolioSnapshot
    }

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}
