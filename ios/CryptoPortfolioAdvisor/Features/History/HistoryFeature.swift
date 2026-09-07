import ComposableArchitecture
import Foundation

@Reducer
struct HistoryFeature {
    enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed
    }

    enum LoadResult: Equatable, Sendable {
        case success([PortfolioAnalysis])
        case failure
    }

    @ObservableState
    struct State: Equatable {
        @Presents var destination: AnalysisDetailsFeature.State?
        var hasAppeared = false
        var analyses: [PortfolioAnalysis] = []
        var loadState = LoadState.idle
    }

    enum Action: Equatable {
        case appeared
        case retryTapped
        case loadFinished(LoadResult)
        case analysisTapped(UUID)
        case destination(PresentationAction<AnalysisDetailsFeature.Action>)
    }

    @Dependency(\.portfolioPersistence) var persistence

    private enum CancelID: Hashable {
        case load
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                state.hasAppeared = true
                state.loadState = .loading
                return loadAnalyses()

            case .retryTapped:
                state.loadState = .loading
                return loadAnalyses()

            case let .loadFinished(.success(analyses)):
                state.analyses = analyses
                state.loadState = .loaded
                return .none

            case .loadFinished(.failure):
                state.loadState = .failed
                return .none

            case let .analysisTapped(id):
                guard let analysis = state.analyses.first(where: { $0.id == id }) else {
                    return .none
                }
                state.destination = AnalysisDetailsFeature.State(analysis: analysis)
                return .none

            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination) {
            AnalysisDetailsFeature()
        }
    }

    private func loadAnalyses() -> Effect<Action> {
        .run { [persistence] send in
            do {
                let analyses = try await persistence.loadAnalyses()
                try Task.checkCancellation()
                await send(.loadFinished(.success(analyses)))
            } catch is CancellationError {
                return
            } catch {
                await send(.loadFinished(.failure))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
