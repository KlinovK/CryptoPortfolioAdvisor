import ComposableArchitecture
import Foundation

enum ATAAnalysisReadIssue: Equatable, Sendable {
    case configuration
    case credentialRequired
    case authentication
    case notFound
    case transport
    case incompatibleResponse
    case service

    static func map(_ error: Error) -> Self {
        if let credential = error as? CredentialStoreError {
            return credential == .tokenAbsent ? .credentialRequired : .authentication
        }
        guard let error = error as? ATAClientError else { return .service }
        switch error {
        case .invalidConfiguration: return .configuration
        case .missingCredential: return .credentialRequired
        case .credentialUnavailable: return .authentication
        case .transport, .cancelled: return .transport
        case .invalidResponse: return .incompatibleResponse
        case .http(let failure) where failure.statusCode == 401: return .authentication
        case .http(let failure)
        where failure.statusCode == 404 && failure.error.knownCode == .analysisNotFound:
            return .notFound
        case .http, .invalidRequest, .uncertainMutationOutcome: return .service
        }
    }

    var message: String {
        switch self {
        case .configuration: "ATA backend URL is not configured for this build."
        case .credentialRequired: "An ATA credential is required. Configure it on Dashboard."
        case .authentication: "ATA rejected the credential. Replace it on Dashboard."
        case .notFound: "This analysis is no longer available."
        case .transport: "Unable to reach ATA. Try again."
        case .incompatibleResponse: "ATA returned an incompatible analysis response."
        case .service: "ATA could not load the analysis. Try again."
        }
    }
}

@Reducer
struct ATAHistoryFeature {
    static let recentLimit = 20

    enum LoadState: Equatable, Sendable {
        case idle
        case configurationUnavailable
        case credentialRequired
        case loading
        case loaded
        case empty
        case failed(ATAAnalysisReadIssue)
    }

    enum LatestState: Equatable, Sendable {
        case idle
        case loading
        case available
        case unavailable
        case failed(ATAAnalysisReadIssue)
    }

    enum ListResult: Equatable, Sendable {
        case loaded(ATARecentAnalyses)
        case failed(ATAAnalysisReadIssue)
    }

    enum LatestResult: Equatable, Sendable {
        case loaded(ATAAnalysisDetail)
        case unavailable
        case failed(ATAAnalysisReadIssue)
    }

    @ObservableState
    struct State: Equatable {
        @Presents var destination: ATAAnalysisDetailFeature.State?
        var configurationAvailable = false
        var hasAppeared = false
        var runs: [ATAAnalysisRun] = []
        var latest: ATAAnalysisDetail?
        var loadState: LoadState = .idle
        var latestState: LatestState = .idle
        var listGeneration = 0
        var latestGeneration = 0
        var selectionGeneration = 0
        var isRefreshing: Bool { loadState == .loading && !runs.isEmpty }
    }

    enum Action: Equatable {
        case appeared
        case refreshTapped
        case retryTapped
        case credentialContextChanged
        case listFinished(generation: Int, result: ListResult)
        case latestFinished(generation: Int, result: LatestResult)
        case runTapped(UUID)
        case latestTapped
        case detailContextFailed(ATAAnalysisReadIssue)
        case destination(PresentationAction<ATAAnalysisDetailFeature.Action>)
    }

    @Dependency(\.ataClient) var client
    @Dependency(\.ataCredentials) var credentials

    private enum CancelID: Hashable { case list, latest }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                guard !state.hasAppeared else { return .none }
                state.hasAppeared = true
                return beginLoad(&state)
            case .refreshTapped, .retryTapped:
                return beginLoad(&state)
            case .credentialContextChanged:
                state.listGeneration += 1
                state.latestGeneration += 1
                state.selectionGeneration += 1
                state.hasAppeared = false
                state.runs = []
                state.latest = nil
                state.destination = nil
                state.loadState =
                    state.configurationAvailable ? .credentialRequired : .configurationUnavailable
                state.latestState = .idle
                return .merge(.cancel(id: CancelID.list), .cancel(id: CancelID.latest))
            case .listFinished(let generation, let result):
                guard generation == state.listGeneration else { return .none }
                switch result {
                case .loaded(let recent):
                    // Server order is authoritative.
                    state.runs = recent.analyses
                    state.loadState = recent.analyses.isEmpty ? .empty : .loaded
                case .failed(let issue):
                    if issue == .authentication || issue == .credentialRequired
                        || issue == .configuration
                    {
                        clearAuthenticatedState(&state, issue: issue)
                    } else {
                        // Retain prior list as stale, never as fresh.
                        state.loadState = .failed(issue)
                    }
                }
                return .none
            case .latestFinished(let generation, let result):
                guard generation == state.latestGeneration else { return .none }
                switch result {
                case .loaded(let detail):
                    state.latest = detail
                    state.latestState = .available
                case .unavailable:
                    state.latest = nil
                    state.latestState = .unavailable
                case .failed(let issue):
                    if issue == .authentication || issue == .credentialRequired
                        || issue == .configuration
                    {
                        clearAuthenticatedState(&state, issue: issue)
                    } else {
                        state.latestState = .failed(issue)
                    }
                }
                return .none
            case .runTapped(let id):
                guard state.runs.contains(where: { $0.runID == id }) else { return .none }
                state.selectionGeneration += 1
                state.destination = ATAAnalysisDetailFeature.State(
                    runID: id, requestIdentity: state.selectionGeneration)
                return .none
            case .latestTapped:
                guard let latest = state.latest else { return .none }
                state.selectionGeneration += 1
                state.destination = ATAAnalysisDetailFeature.State(
                    runID: latest.run.runID, requestIdentity: state.selectionGeneration)
                return .none
            case .destination(.presented(.loadFinished(_, _, .failed(let issue))))
            where issue == .authentication || issue == .credentialRequired
                || issue == .configuration:
                // Let the child consume its response before dismissing the destination.
                return .send(.detailContextFailed(issue))
            case .detailContextFailed(let issue):
                clearAuthenticatedState(&state, issue: issue)
                return .none
            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination) {
            ATAAnalysisDetailFeature()
        }
    }

    private func clearAuthenticatedState(_ state: inout State, issue: ATAAnalysisReadIssue) {
        state.listGeneration += 1
        state.latestGeneration += 1
        state.selectionGeneration += 1
        state.runs = []
        state.latest = nil
        state.destination = nil
        state.loadState = issue == .configuration ? .configurationUnavailable : .credentialRequired
        state.latestState = .idle
    }

    private func beginLoad(_ state: inout State) -> Effect<Action> {
        guard state.configurationAvailable else {
            clearAuthenticatedState(&state, issue: .configuration)
            return .none
        }
        state.listGeneration += 1
        state.latestGeneration += 1
        let listGeneration = state.listGeneration
        let latestGeneration = state.latestGeneration
        state.loadState = .loading
        state.latestState = .loading
        return .merge(
            .run { [client, credentials] send in
                do {
                    _ = try await credentials.load()
                    let recent = try await client.loadAnalyses(Self.recentLimit)
                    try Task.checkCancellation()
                    await send(.listFinished(generation: listGeneration, result: .loaded(recent)))
                } catch is CancellationError {
                    return
                } catch {
                    await send(
                        .listFinished(
                            generation: listGeneration,
                            result: .failed(ATAAnalysisReadIssue.map(error))))
                }
            }
            .cancellable(id: CancelID.list, cancelInFlight: true),
            .run { [client, credentials] send in
                do {
                    _ = try await credentials.load()
                    let detail = try await client.loadLatestAnalysis()
                    try Task.checkCancellation()
                    await send(
                        .latestFinished(generation: latestGeneration, result: .loaded(detail)))
                } catch is CancellationError {
                    return
                } catch {
                    let issue = ATAAnalysisReadIssue.map(error)
                    await send(
                        .latestFinished(
                            generation: latestGeneration,
                            result: issue == .notFound ? .unavailable : .failed(issue)))
                }
            }
            .cancellable(id: CancelID.latest, cancelInFlight: true)
        )
    }
}
