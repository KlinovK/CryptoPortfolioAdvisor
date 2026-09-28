import ComposableArchitecture
import Foundation

// The active Dashboard is a server read model. The CPA editor remains isolated for legacy tests.
@Reducer
struct ATADashboardFeature {
    enum Failure: Equatable, Sendable {
        case authentication
        case transport
        case incompatibleResponse
        case service
        case credentialStorage
    }

    enum LoadState: Equatable, Sendable {
        case configurationUnavailable
        case credentialRequired
        case loading
        case loaded
        case uninitialized
        case failed(Failure)
    }

    enum CredentialOperation: Equatable, Sendable {
        case idle
        case saving
        case deleting
    }

    @ObservableState
    struct State: Equatable {
        var configurationAvailable = false
        var hasAppeared = false
        var loadState: LoadState = .configurationUnavailable
        var portfolio: ATACurrentPortfolio?
        var requestGeneration = 0
        var credentialOperation: CredentialOperation = .idle

        var isRefreshing: Bool { loadState == .loading && portfolio != nil }
    }

    enum LoadResult: Equatable, Sendable {
        case loaded(ATACurrentPortfolio)
        case configurationUnavailable
        case credentialRequired
        case uninitialized
        case failed(Failure)
    }

    enum Action: Equatable {
        case appeared
        case refreshTapped
        case retryTapped
        case loadFinished(generation: Int, result: LoadResult)
        case credentialSaveRequested(ATABearerToken)
        case credentialSaved(generation: Int, succeeded: Bool)
        case credentialDeleteRequested
        case credentialDeleted(generation: Int, succeeded: Bool)
    }

    @Dependency(\.ataClient) var client
    @Dependency(\.ataCredentials) var credentials

    private enum CancelID: Hashable { case load }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                guard !state.hasAppeared else { return .none }
                state.hasAppeared = true
                return beginLoad(&state)

            case .refreshTapped, .retryTapped:
                return beginLoad(&state)

            case .loadFinished(let generation, let result):
                guard generation == state.requestGeneration,
                    state.credentialOperation == .idle
                else { return .none }
                switch result {
                case .loaded(let portfolio):
                    state.portfolio = portfolio
                    state.loadState = .loaded
                case .configurationUnavailable:
                    state.configurationAvailable = false
                    state.portfolio = nil
                    state.loadState = .configurationUnavailable
                case .credentialRequired:
                    state.portfolio = nil
                    state.loadState = .credentialRequired
                case .uninitialized:
                    state.portfolio = nil
                    state.loadState = .uninitialized
                case .failed(let failure):
                    if failure == .authentication || failure == .credentialStorage {
                        state.portfolio = nil
                    }
                    state.loadState = .failed(failure)
                }
                return .none

            case .credentialSaveRequested(let token):
                guard state.configurationAvailable, state.credentialOperation == .idle else {
                    return .none
                }
                state.requestGeneration += 1
                let generation = state.requestGeneration
                state.portfolio = nil
                state.loadState = .credentialRequired
                state.credentialOperation = .saving
                return .merge(
                    .cancel(id: CancelID.load),
                    .run { [credentials] send in
                        do {
                            try await credentials.save(token)
                            await send(.credentialSaved(generation: generation, succeeded: true))
                        } catch {
                            await send(.credentialSaved(generation: generation, succeeded: false))
                        }
                    }
                )

            case .credentialSaved(let generation, let succeeded):
                guard generation == state.requestGeneration,
                    state.credentialOperation == .saving
                else { return .none }
                state.credentialOperation = .idle
                if succeeded { return beginLoad(&state) }
                state.loadState = .failed(.credentialStorage)
                return .none

            case .credentialDeleteRequested:
                guard state.configurationAvailable, state.credentialOperation == .idle else {
                    return .none
                }
                state.requestGeneration += 1
                let generation = state.requestGeneration
                state.portfolio = nil
                state.loadState = .credentialRequired
                state.credentialOperation = .deleting
                return .merge(
                    .cancel(id: CancelID.load),
                    .run { [credentials] send in
                        do {
                            try await credentials.delete()
                            await send(.credentialDeleted(generation: generation, succeeded: true))
                        } catch {
                            await send(.credentialDeleted(generation: generation, succeeded: false))
                        }
                    }
                )

            case .credentialDeleted(let generation, let succeeded):
                guard generation == state.requestGeneration,
                    state.credentialOperation == .deleting
                else { return .none }
                state.credentialOperation = .idle
                state.loadState = succeeded ? .credentialRequired : .failed(.credentialStorage)
                return .none
            }
        }
    }

    private func beginLoad(_ state: inout State) -> Effect<Action> {
        guard state.configurationAvailable else {
            state.portfolio = nil
            state.loadState = .configurationUnavailable
            return .none
        }
        guard state.credentialOperation == .idle else { return .none }
        // This generation is the authority boundary: later reads (and Step 9E mutations)
        // invalidate every earlier GET, irrespective of completion order or timestamp.
        state.requestGeneration += 1
        let generation = state.requestGeneration
        state.loadState = .loading
        return .run { [client, credentials] send in
            do {
                _ = try await credentials.load()
            } catch {
                let result: LoadResult =
                    error as? CredentialStoreError == .tokenAbsent
                    ? .credentialRequired : .failed(.credentialStorage)
                await send(.loadFinished(generation: generation, result: result))
                return
            }
            do {
                let portfolio = try await client.loadPortfolio()
                await send(.loadFinished(generation: generation, result: .loaded(portfolio)))
            } catch {
                await send(.loadFinished(generation: generation, result: Self.map(error)))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    private static func map(_ error: Error) -> LoadResult {
        guard let error = error as? ATAClientError else { return .failed(.service) }
        switch error {
        case .missingCredential:
            return .credentialRequired
        case .credentialUnavailable:
            return .failed(.credentialStorage)
        case .invalidConfiguration:
            return .configurationUnavailable
        case .transport, .cancelled:
            return .failed(.transport)
        case .invalidResponse:
            return .failed(.incompatibleResponse)
        case .http(let failure) where failure.statusCode == 401:
            return .failed(.authentication)
        case .http(let failure)
        where failure.statusCode == 404 && failure.error.knownCode == .portfolioNotFound:
            return .uninitialized
        case .http, .invalidRequest, .uncertainMutationOutcome:
            return .failed(.service)
        }
    }
}
