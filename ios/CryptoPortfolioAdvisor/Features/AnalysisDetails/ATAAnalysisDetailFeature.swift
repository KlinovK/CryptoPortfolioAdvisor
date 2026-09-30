import ComposableArchitecture
import Foundation

@Reducer
struct ATAAnalysisDetailFeature {
    enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case loadedWithoutResult
        case notFound
        case failed(ATAAnalysisReadIssue)
    }

    enum Result: Equatable, Sendable {
        case loaded(ATAAnalysisDetail)
        case failed(ATAAnalysisReadIssue)
    }

    @ObservableState
    struct State: Equatable {
        let runID: UUID
        let requestIdentity: Int
        var requestGeneration = 0
        var hasAppeared = false
        var loadState: LoadState = .idle
        var detail: ATAAnalysisDetail?
    }

    enum Action: Equatable {
        case appeared
        case retryTapped
        case loadFinished(identity: Int, generation: Int, result: Result)
    }

    @Dependency(\.ataClient) var client
    @Dependency(\.ataCredentials) var credentials

    private enum CancelID: Hashable { case detail }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                guard !state.hasAppeared else { return .none }
                state.hasAppeared = true
                return beginLoad(&state)
            case .retryTapped:
                return beginLoad(&state)
            case .loadFinished(let identity, let generation, let result):
                guard identity == state.requestIdentity,
                    generation == state.requestGeneration
                else { return .none }
                switch result {
                case .loaded(let detail):
                    guard detail.run.runID == state.runID else {
                        state.detail = nil
                        state.loadState = .failed(.incompatibleResponse)
                        return .none
                    }
                    state.detail = detail
                    state.loadState = detail.result == nil ? .loadedWithoutResult : .loaded
                case .failed(let issue):
                    state.detail = nil
                    state.loadState = issue == .notFound ? .notFound : .failed(issue)
                }
                return .none
            }
        }
    }

    private func beginLoad(_ state: inout State) -> Effect<Action> {
        state.requestGeneration += 1
        let generation = state.requestGeneration
        let identity = state.requestIdentity
        let runID = state.runID
        state.detail = nil  // A previous run's result is never presented as this request.
        state.loadState = .loading
        return .run { [client, credentials] send in
            do {
                _ = try await credentials.load()
                let detail = try await client.loadAnalysis(runID)
                try Task.checkCancellation()
                await send(
                    .loadFinished(
                        identity: identity, generation: generation, result: .loaded(detail)))
            } catch is CancellationError {
                return
            } catch {
                await send(
                    .loadFinished(
                        identity: identity, generation: generation,
                        result: .failed(ATAAnalysisReadIssue.map(error))))
            }
        }
        .cancellable(id: CancelID.detail, cancelInFlight: true)
    }
}
