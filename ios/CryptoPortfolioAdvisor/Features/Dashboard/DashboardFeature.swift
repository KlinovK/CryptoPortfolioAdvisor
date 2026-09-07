import ComposableArchitecture
import Foundation

@Reducer
struct DashboardFeature {
    enum PersistenceStatus: Equatable, Sendable {
        case idle
        case loading
        case saving
        case saved
        case failed(String)
    }

    enum RestorationResult: Equatable, Sendable {
        case draft(PersistedDashboardDraft)
        case snapshot(PortfolioSnapshot)
        case none
        case failed
    }

    enum SaveResult: Equatable, Sendable {
        case succeeded
        case failed
    }

    enum SubmissionFailure: Equatable, Sendable {
        case snapshotPersistence(String)
        case request(String)
        case analysisPersistence(String)
    }

    enum AnalysisSubmissionState: Equatable, Sendable {
        case idle
        case submitting
        case success
        case failed(SubmissionFailure)
    }

    enum AnalysisRequestResult: Equatable, Sendable {
        case succeeded(PortfolioAnalysis)
        case failed(String)
    }

    @ObservableState
    struct State: Equatable {
        var hasAppeared = false
        var hasAttemptedRestore = false
        var assetPositions: [AssetPositionDraft] = []
        var constraints = TradingConstraintsDraft()
        var limitOrders: [LimitOrderDraft] = []
        var validationErrors = DashboardValidationErrors()
        var validatedInput: ValidatedDashboardInput?
        var analysisReadinessMessage: String?
        var draftRevision = 0
        var draftPersistenceStatus = PersistenceStatus.idle
        var snapshotPersistenceStatus = PersistenceStatus.idle
        var lastSavedSnapshot: PortfolioSnapshot?
        var analysisSubmissionState = AnalysisSubmissionState.idle
        var pendingSnapshotForAnalysis: PortfolioSnapshot?
        var pendingAnalysisForPersistence: PortfolioAnalysis?
        var completedAnalysis: PortfolioAnalysis?

        var isPortfolioEmpty: Bool {
            assetPositions.isEmpty
        }

        var isSubmitting: Bool {
            analysisSubmissionState == .submitting
        }

        var analysisButtonTitle: String {
            switch analysisSubmissionState {
            case .submitting:
                "Analyzing…"
            case .failed:
                "Retry Analysis"
            case .idle, .success:
                "Analyze Portfolio"
            }
        }

        var shouldRetryAnalysis: Bool {
            if case .failed = analysisSubmissionState {
                return true
            }
            return false
        }
    }

    enum Action: Equatable {
        case appeared
        case restoreRequested
        case restorationFinished(revision: Int, result: RestorationResult)
        case addAssetTapped(id: UUID)
        case removeAsset(id: UUID)
        case assetSymbolChanged(id: UUID, value: String)
        case assetAmountChanged(id: UUID, value: String)
        case tradingStyleChanged(TradingStyle)
        case riskToleranceChanged(RiskTolerance)
        case leverageChanged(Bool)
        case monthlyIncomeChanged(String)
        case stableReserveChanged(String)
        case addOrderTapped(id: UUID, createdAt: Date)
        case removeOrder(id: UUID)
        case orderSymbolChanged(id: UUID, value: String)
        case orderSideChanged(id: UUID, side: OrderSide)
        case orderAmountChanged(id: UUID, value: String)
        case orderPriceChanged(id: UUID, value: String)
        case orderStatusChanged(id: UUID, status: OrderStatus)
        case analyzeButtonTapped
        case retryAnalysisTapped
        case draftSaveFinished(revision: Int, result: SaveResult)
        case snapshotSaveFinished(snapshot: PortfolioSnapshot, result: SaveResult)
        case analysisRequestFinished(snapshotID: UUID, result: AnalysisRequestResult)
        case analysisSaveFinished(analysisID: UUID, result: SaveResult)
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.portfolioAnalysis) var analysisClient
    @Dependency(\.portfolioPersistence) var persistence
    @Dependency(\.uuid) var uuid

    private enum CancelID: Hashable {
        case draftAutosave
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            guard !state.isSubmitting || !action.isDraftMutation else {
                return .none
            }

            switch action {
            case .appeared:
                state.hasAppeared = true
                return .none

            case .restoreRequested:
                guard !state.hasAttemptedRestore else {
                    return .none
                }

                state.hasAttemptedRestore = true
                state.draftPersistenceStatus = .loading
                let revision = state.draftRevision

                return .run { [persistence] send in
                    do {
                        if let draft = try await persistence.loadDashboardDraft() {
                            await send(
                                .restorationFinished(revision: revision, result: .draft(draft))
                            )
                        } else if let snapshot = try await persistence.loadLatestSnapshot() {
                            await send(
                                .restorationFinished(
                                    revision: revision,
                                    result: .snapshot(snapshot)
                                )
                            )
                        } else {
                            await send(
                                .restorationFinished(revision: revision, result: .none)
                            )
                        }
                    } catch {
                        await send(
                            .restorationFinished(revision: revision, result: .failed)
                        )
                    }
                }

            case let .restorationFinished(revision, result):
                guard revision == state.draftRevision else {
                    return .none
                }

                switch result {
                case let .draft(draft):
                    state.restore(from: draft)
                    state.draftPersistenceStatus = .saved

                case let .snapshot(snapshot):
                    state.restore(from: snapshot, makePositionID: { uuid() })
                    state.draftPersistenceStatus = .saved

                case .none:
                    state.draftPersistenceStatus = .idle

                case .failed:
                    state.draftPersistenceStatus = .failed(
                        "Unable to load saved portfolio."
                    )
                }
                return .none

            case let .addAssetTapped(id):
                state.assetPositions.append(AssetPositionDraft(id: id))
                return scheduleAutosave(for: &state)

            case let .removeAsset(id):
                state.assetPositions.removeAll { $0.id == id }
                return scheduleAutosave(for: &state)

            case let .assetSymbolChanged(id, value):
                state.assetPositions[id: id]?.symbol = value.uppercased()
                return scheduleAutosave(for: &state)

            case let .assetAmountChanged(id, value):
                state.assetPositions[id: id]?.amount = value
                return scheduleAutosave(for: &state)

            case let .tradingStyleChanged(style):
                state.constraints.tradingStyle = style
                return scheduleAutosave(for: &state)

            case let .riskToleranceChanged(riskTolerance):
                state.constraints.riskTolerance = riskTolerance
                return scheduleAutosave(for: &state)

            case let .leverageChanged(isAllowed):
                state.constraints.leverageAllowed = isAllowed
                return scheduleAutosave(for: &state)

            case let .monthlyIncomeChanged(value):
                state.constraints.additionalMonthlyIncomeUSD = value
                return scheduleAutosave(for: &state)

            case let .stableReserveChanged(value):
                state.constraints.minimumStableReserveUSD = value
                return scheduleAutosave(for: &state)

            case let .addOrderTapped(id, createdAt):
                state.limitOrders.append(LimitOrderDraft(id: id, createdAt: createdAt))
                return scheduleAutosave(for: &state)

            case let .removeOrder(id):
                state.limitOrders.removeAll { $0.id == id }
                return scheduleAutosave(for: &state)

            case let .orderSymbolChanged(id, value):
                state.limitOrders[id: id]?.symbol = value.uppercased()
                return scheduleAutosave(for: &state)

            case let .orderSideChanged(id, side):
                state.limitOrders[id: id]?.side = side
                return scheduleAutosave(for: &state)

            case let .orderAmountChanged(id, value):
                state.limitOrders[id: id]?.amountUSD = value
                return scheduleAutosave(for: &state)

            case let .orderPriceChanged(id, value):
                state.limitOrders[id: id]?.targetPrice = value
                return scheduleAutosave(for: &state)

            case let .orderStatusChanged(id, status):
                let previousStatus = state.limitOrders[id: id]?.status
                state.limitOrders[id: id]?.status = status
                if status == .open {
                    state.limitOrders[id: id]?.resolvedAt = nil
                } else if previousStatus != status {
                    state.limitOrders[id: id]?.resolvedAt = now
                }
                return scheduleAutosave(for: &state)

            case .analyzeButtonTapped:
                guard state.analysisSubmissionState != .submitting else {
                    return .none
                }

                let outcome = state.makeValidatedDraft()
                state.validationErrors = outcome.errors
                state.validatedInput = outcome.validatedInput
                state.analysisReadinessMessage = nil

                guard let validatedInput = outcome.validatedInput else {
                    state.snapshotPersistenceStatus = .idle
                    state.analysisSubmissionState = .idle
                    return .none
                }

                let snapshot = PortfolioSnapshot(
                    id: uuid(),
                    createdAt: now,
                    portfolio: validatedInput.portfolio,
                    constraints: validatedInput.constraints,
                    orders: validatedInput.limitOrders
                )
                state.snapshotPersistenceStatus = .saving
                state.analysisSubmissionState = .submitting
                state.pendingSnapshotForAnalysis = snapshot
                state.pendingAnalysisForPersistence = nil
                state.completedAnalysis = nil

                return saveSnapshot(snapshot)

            case .retryAnalysisTapped:
                guard state.analysisSubmissionState != .submitting,
                      let snapshot = state.pendingSnapshotForAnalysis,
                      case let .failed(failure) = state.analysisSubmissionState
                else {
                    return .none
                }

                state.analysisSubmissionState = .submitting
                state.analysisReadinessMessage = nil

                switch failure {
                case .snapshotPersistence:
                    state.snapshotPersistenceStatus = .saving
                    return saveSnapshot(snapshot)
                case .request:
                    return requestAnalysis(for: snapshot)
                case .analysisPersistence:
                    guard let analysis = state.pendingAnalysisForPersistence else {
                        state.analysisSubmissionState = .failed(
                            .analysisPersistence("The completed analysis is unavailable.")
                        )
                        return .none
                    }
                    return saveAnalysis(analysis)
                }

            case let .draftSaveFinished(revision, result):
                guard revision == state.draftRevision else {
                    return .none
                }

                switch result {
                case .succeeded:
                    state.draftPersistenceStatus = .saved
                case .failed:
                    state.draftPersistenceStatus = .failed(
                        "Unable to save changes locally."
                    )
                }
                return .none

            case let .snapshotSaveFinished(snapshot, result):
                guard snapshot.id == state.pendingSnapshotForAnalysis?.id else {
                    return .none
                }

                switch result {
                case .succeeded:
                    state.lastSavedSnapshot = snapshot
                    state.snapshotPersistenceStatus = .saved
                    return requestAnalysis(for: snapshot)
                case .failed:
                    let message = "Unable to save portfolio snapshot locally."
                    state.snapshotPersistenceStatus = .failed(message)
                    state.analysisSubmissionState = .failed(
                        .snapshotPersistence(message)
                    )
                }
                return .none

            case let .analysisRequestFinished(snapshotID, result):
                guard snapshotID == state.pendingSnapshotForAnalysis?.id else {
                    return .none
                }

                switch result {
                case let .succeeded(analysis):
                    guard analysis.snapshotID == snapshotID else {
                        state.analysisSubmissionState = .failed(
                            .request("The server returned an analysis for a different snapshot.")
                        )
                        return .none
                    }
                    state.pendingAnalysisForPersistence = analysis
                    return saveAnalysis(analysis)

                case let .failed(message):
                    state.analysisSubmissionState = .failed(.request(message))
                    return .none
                }

            case let .analysisSaveFinished(analysisID, result):
                guard let analysis = state.pendingAnalysisForPersistence,
                      analysis.id == analysisID
                else {
                    return .none
                }

                switch result {
                case .succeeded:
                    state.completedAnalysis = analysis
                    state.analysisSubmissionState = .success
                    state.analysisReadinessMessage = Self.completionMessage(
                        for: analysis.analysisMode
                    )
                    state.pendingSnapshotForAnalysis = nil
                    state.pendingAnalysisForPersistence = nil

                case .failed:
                    state.analysisSubmissionState = .failed(
                        .analysisPersistence("Unable to save completed analysis locally.")
                    )
                }
                return .none
            }
        }
    }

    private func saveSnapshot(_ snapshot: PortfolioSnapshot) -> Effect<Action> {
        .run { [persistence] send in
            do {
                try await persistence.saveSnapshot(snapshot)
                await send(.snapshotSaveFinished(snapshot: snapshot, result: .succeeded))
            } catch is CancellationError {
                await send(.snapshotSaveFinished(snapshot: snapshot, result: .failed))
            } catch {
                await send(.snapshotSaveFinished(snapshot: snapshot, result: .failed))
            }
        }
    }

    private func requestAnalysis(for snapshot: PortfolioSnapshot) -> Effect<Action> {
        .run { [analysisClient] send in
            do {
                let analysis = try await analysisClient.analyze(snapshot)
                try Task.checkCancellation()
                await send(
                    .analysisRequestFinished(
                        snapshotID: snapshot.id,
                        result: .succeeded(analysis)
                    )
                )
            } catch is CancellationError {
                await send(
                    .analysisRequestFinished(
                        snapshotID: snapshot.id,
                        result: .failed("Analysis request was cancelled.")
                    )
                )
            } catch {
                await send(
                    .analysisRequestFinished(
                        snapshotID: snapshot.id,
                        result: .failed(Self.requestFailureMessage(for: error))
                    )
                )
            }
        }
    }

    private func saveAnalysis(_ analysis: PortfolioAnalysis) -> Effect<Action> {
        .run { [persistence] send in
            do {
                try await persistence.saveAnalysis(analysis)
                await send(.analysisSaveFinished(analysisID: analysis.id, result: .succeeded))
            } catch is CancellationError {
                await send(.analysisSaveFinished(analysisID: analysis.id, result: .failed))
            } catch {
                await send(.analysisSaveFinished(analysisID: analysis.id, result: .failed))
            }
        }
    }

    private static func completionMessage(for mode: AnalysisMode) -> String {
        switch mode {
        case .deterministic:
            "Deterministic analysis complete."
        case .aiAssisted:
            "AI-assisted analysis complete. Recommendations passed deterministic risk checks."
        case .aiFallback:
            "AI unavailable — deterministic analysis used."
        }
    }

    static func requestFailureMessage(for error: Error) -> String {
        guard let apiError = error as? PortfolioAPIClientError else {
            return "Unable to reach the analysis service."
        }

        switch apiError {
        case let .server(_, code, message) where code == "invalid_request":
            return message
        case let .server(_, code, _) where code == "analysis_timeout":
            return "Analysis took too long. Try again."
        case let .server(_, code, _) where [
            "unsupported_symbol",
            "provider_unavailable",
            "provider_rate_limited",
            "stale_market_data",
            "malformed_market_data"
        ].contains(code ?? ""):
            return "Market data is temporarily unavailable. Try again later."
        case .server:
            return "Analysis service is temporarily unavailable."
        case .timeout:
            return "Analysis took too long. Try again."
        case .transport:
            return "Unable to reach the analysis service."
        case .invalidResponse, .decoding:
            return "Analysis service is temporarily unavailable."
        }
    }

    private func scheduleAutosave(for state: inout State) -> Effect<Action> {
        state.clearValidationResult()
        state.draftRevision += 1
        state.draftPersistenceStatus = .saving

        let draft = state.persistedDraft
        let revision = state.draftRevision

        return .run { [clock, persistence] send in
            do {
                try await clock.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                try await persistence.saveDashboardDraft(draft)
                try Task.checkCancellation()
                await send(.draftSaveFinished(revision: revision, result: .succeeded))
            } catch is CancellationError {
                return
            } catch {
                await send(.draftSaveFinished(revision: revision, result: .failed))
            }
        }
        .cancellable(id: CancelID.draftAutosave, cancelInFlight: true)
    }
}

private extension DashboardFeature.Action {
    var isDraftMutation: Bool {
        switch self {
        case .addAssetTapped,
             .removeAsset,
             .assetSymbolChanged,
             .assetAmountChanged,
             .tradingStyleChanged,
             .riskToleranceChanged,
             .leverageChanged,
             .monthlyIncomeChanged,
             .stableReserveChanged,
             .addOrderTapped,
             .removeOrder,
             .orderSymbolChanged,
             .orderSideChanged,
             .orderAmountChanged,
             .orderPriceChanged,
             .orderStatusChanged:
            true

        case .appeared,
             .restoreRequested,
             .restorationFinished,
             .analyzeButtonTapped,
             .retryAnalysisTapped,
             .draftSaveFinished,
             .snapshotSaveFinished,
             .analysisRequestFinished,
             .analysisSaveFinished:
            false
        }
    }
}

private extension DashboardFeature.State {
    mutating func clearValidationResult() {
        validationErrors = DashboardValidationErrors()
        validatedInput = nil
        analysisReadinessMessage = nil
        snapshotPersistenceStatus = .idle
        if analysisSubmissionState != .submitting {
            analysisSubmissionState = .idle
            pendingSnapshotForAnalysis = nil
            pendingAnalysisForPersistence = nil
        }
    }
}

private extension Array where Element == AssetPositionDraft {
    subscript(id id: UUID) -> Element? {
        get { first { $0.id == id } }
        set {
            guard let index = firstIndex(where: { $0.id == id }), let newValue else {
                return
            }
            self[index] = newValue
        }
    }
}

private extension Array where Element == LimitOrderDraft {
    subscript(id id: UUID) -> Element? {
        get { first { $0.id == id } }
        set {
            guard let index = firstIndex(where: { $0.id == id }), let newValue else {
                return
            }
            self[index] = newValue
        }
    }
}
