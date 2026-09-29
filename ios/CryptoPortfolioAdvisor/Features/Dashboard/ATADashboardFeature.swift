import ComposableArchitecture
import Foundation

// The active Dashboard owns transient edits; only server responses confirm portfolio state.
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

    enum PortfolioMutationKind: Equatable, Sendable {
        case create
        case rename(UUID)
        case holdings(UUID)
        case delete(UUID)
        case financialSettings
        case corePosition(AssetSymbol)
    }

    enum MutationIssue: Equatable, Sendable {
        case revisionConflict
        case stateConflict
        case resourceNotFound
        case validation
        case uncertain
        case reviewRequired
        case authentication
        case service
    }

    enum MutationResult: Equatable, Sendable {
        case succeeded(ATACurrentPortfolio)
        case failed(MutationIssue)
    }

    private enum PortfolioRequest: Sendable {
        case create(ATACreateAccountRequestDTO)
        case rename(UUID, ATARenameAccountRequestDTO)
        case holdings(UUID, ATAReplaceAccountHoldingsRequestDTO)
        case delete(UUID, ATADeleteAccountRequestDTO)
        case financialSettings(ATAUpdateFinancialSettingsRequestDTO)
        case corePosition(AssetSymbol, ATAUpdateCorePositionRequestDTO)
    }

    @ObservableState
    struct State: Equatable {
        var configurationAvailable = false
        var hasAppeared = false
        var loadState: LoadState = .configurationUnavailable
        var portfolio: ATACurrentPortfolio?
        var requestGeneration = 0
        var credentialOperation: CredentialOperation = .idle
        var editor: ATAAccountEditor?
        var policyEditor: ATAPolicyEditor?
        var pendingDeletion: UUID?
        var mutationInFlight: PortfolioMutationKind?
        var mutationGeneration = 0
        var reconciliationRequired = false
        var mutationIssue: MutationIssue?

        var isRefreshing: Bool { loadState == .loading && portfolio != nil }
        var canSubmitPortfolioMutation: Bool {
            portfolio != nil && configurationAvailable && credentialOperation == .idle
                && mutationInFlight == nil && !reconciliationRequired
                && (loadState == .loaded || loadState == .loading)
        }
        var canSubmitAccountMutation: Bool { canSubmitPortfolioMutation }
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
        case createAccountTapped
        case renameAccountTapped(UUID)
        case editHoldingsTapped(UUID)
        case editorNameChanged(String)
        case editorTypeChanged(ATAAccountType)
        case holdingAdded(UUID)
        case holdingRemoved(UUID)
        case holdingSymbolChanged(UUID, String)
        case holdingAmountChanged(UUID, String)
        case editorCancelled
        case editorReviewAcknowledged
        case editorSubmitTapped
        case editFinancialSettingsTapped
        case editCorePositionTapped(AssetSymbol)
        case policyFirstValueChanged(String)
        case policySecondValueChanged(String)
        case policyEditorCancelled
        case policyEditorSubmitTapped
        case deleteAccountTapped(UUID)
        case deleteAccountConfirmed(UUID)
        case deleteAccountConfirmationDismissed
        case mutationFinished(generation: Int, result: MutationResult)
    }

    @Dependency(\.ataClient) var client
    @Dependency(\.ataCredentials) var credentials

    private enum CancelID: Hashable { case load, mutation }

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
                    if let accepted = state.portfolio, portfolio.revision < accepted.revision {
                        state.loadState = .loaded
                        return .none
                    }
                    if state.portfolio?.revision != portfolio.revision {
                        state.pendingDeletion = nil
                    }
                    if state.editor != nil && state.portfolio?.revision != portfolio.revision {
                        state.editor?.needsReview = true
                    }
                    if state.policyEditor != nil && state.portfolio?.revision != portfolio.revision
                    {
                        state.policyEditor?.needsReview = true
                    }
                    state.portfolio = portfolio
                    state.loadState = .loaded
                    if state.reconciliationRequired {
                        state.reconciliationRequired = false
                        if state.editor != nil || state.policyEditor != nil {
                            state.mutationIssue = .reviewRequired
                            state.editor?.needsReview = true
                            state.policyEditor?.needsReview = true
                        } else {
                            state.mutationIssue = nil
                        }
                    }
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
                state.mutationGeneration += 1
                let generation = state.requestGeneration
                let interruptedMutation = state.mutationInFlight != nil
                state.portfolio = nil
                state.editor = nil
                state.policyEditor = nil
                state.pendingDeletion = nil
                state.mutationInFlight = nil
                state.mutationIssue = nil
                state.reconciliationRequired = interruptedMutation
                state.loadState = .credentialRequired
                state.credentialOperation = .saving
                return .merge(
                    .cancel(id: CancelID.load),
                    .cancel(id: CancelID.mutation),
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
                state.mutationGeneration += 1
                let generation = state.requestGeneration
                let interruptedMutation = state.mutationInFlight != nil
                state.portfolio = nil
                state.editor = nil
                state.policyEditor = nil
                state.pendingDeletion = nil
                state.mutationInFlight = nil
                state.mutationIssue = nil
                state.reconciliationRequired = interruptedMutation
                state.loadState = .credentialRequired
                state.credentialOperation = .deleting
                return .merge(
                    .cancel(id: CancelID.load),
                    .cancel(id: CancelID.mutation),
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

            case .createAccountTapped:
                guard state.canSubmitPortfolioMutation, state.policyEditor == nil else {
                    return .none
                }
                state.editor = ATAAccountEditor(kind: .create)
                state.mutationIssue = nil
                return .none

            case .renameAccountTapped(let id):
                guard state.canSubmitPortfolioMutation, state.policyEditor == nil,
                    let account = state.portfolio?.accounts.first(where: { $0.id == id })
                else { return .none }
                state.editor = ATAAccountEditor(kind: .rename(id), name: account.name)
                state.mutationIssue = nil
                return .none

            case .editHoldingsTapped(let id):
                guard state.canSubmitPortfolioMutation, state.policyEditor == nil,
                    let account = state.portfolio?.accounts.first(where: { $0.id == id }),
                    let holdings = try? account.positions.map({ position in
                        ATAHoldingDraft(
                            id: uuid(), symbol: position.symbol.rawValue,
                            amount: try ATADecimalCodec.encode(position.amount))
                    })
                else { return .none }
                state.editor = ATAAccountEditor(kind: .holdings(id), holdings: holdings)
                state.mutationIssue = nil
                return .none

            case .editorNameChanged(let name):
                state.editor?.name = name
                state.editor?.inputError = nil
                return .none

            case .editorTypeChanged(let type):
                state.editor?.accountType = type
                return .none

            case .holdingAdded(let id):
                guard state.editor != nil else { return .none }
                state.editor?.holdings.append(ATAHoldingDraft(id: id, symbol: "", amount: ""))
                state.editor?.inputError = nil
                return .none

            case .holdingRemoved(let id):
                state.editor?.holdings.removeAll { $0.id == id }
                state.editor?.inputError = nil
                return .none

            case .holdingSymbolChanged(let id, let symbol):
                if let index = state.editor?.holdings.firstIndex(where: { $0.id == id }) {
                    state.editor?.holdings[index].symbol = symbol
                    state.editor?.inputError = nil
                }
                return .none

            case .holdingAmountChanged(let id, let amount):
                if let index = state.editor?.holdings.firstIndex(where: { $0.id == id }) {
                    state.editor?.holdings[index].amount = amount
                    state.editor?.inputError = nil
                }
                return .none

            case .editorCancelled:
                guard state.mutationInFlight == nil else { return .none }
                state.editor = nil
                return .none

            case .editorReviewAcknowledged:
                guard state.mutationInFlight == nil, !state.reconciliationRequired else {
                    return .none
                }
                state.editor?.needsReview = false
                state.policyEditor?.needsReview = false
                state.mutationIssue = nil
                return .none

            case .editorSubmitTapped:
                guard state.canSubmitPortfolioMutation, var editor = state.editor,
                    !editor.needsReview,
                    let portfolio = state.portfolio
                else { return .none }
                do {
                    let request = try makeAccountRequest(editor: editor, portfolio: portfolio)
                    editor.inputError = nil
                    state.editor = editor
                    return beginMutation(&state, request: request, kind: kind(for: editor.kind))
                } catch let error as ATAAccountEditor.InputError {
                    editor.inputError = error
                    state.editor = editor
                    return .none
                } catch {
                    editor.inputError = .amount
                    state.editor = editor
                    return .none
                }

            case .editFinancialSettingsTapped:
                guard state.canSubmitPortfolioMutation, state.editor == nil,
                    let settings = state.portfolio?.financialSettings,
                    let editor = try? ATAPolicyEditor(financialSettings: settings)
                else { return .none }
                state.policyEditor = editor
                state.mutationIssue = nil
                return .none

            case .editCorePositionTapped(let symbol):
                guard state.canSubmitPortfolioMutation, state.editor == nil,
                    let core = state.portfolio?.corePositions.first(where: { $0.symbol == symbol }),
                    let editor = try? ATAPolicyEditor(corePosition: core)
                else { return .none }
                state.policyEditor = editor
                state.mutationIssue = nil
                return .none

            case .policyFirstValueChanged(let value):
                state.policyEditor?.firstValue = value
                state.policyEditor?.inputError = nil
                return .none

            case .policySecondValueChanged(let value):
                state.policyEditor?.secondValue = value
                state.policyEditor?.inputError = nil
                return .none

            case .policyEditorCancelled:
                guard state.mutationInFlight == nil else { return .none }
                state.policyEditor = nil
                return .none

            case .policyEditorSubmitTapped:
                guard state.canSubmitPortfolioMutation, var editor = state.policyEditor,
                    !editor.needsReview, let portfolio = state.portfolio
                else { return .none }
                do {
                    let request = try makePolicyRequest(editor: editor, portfolio: portfolio)
                    editor.inputError = nil
                    state.policyEditor = editor
                    return beginMutation(&state, request: request, kind: kind(for: editor.kind))
                } catch let error as ATAPolicyEditor.InputError {
                    editor.inputError = error
                    state.policyEditor = editor
                    return .none
                } catch {
                    editor.inputError = .unsupportedCorePolicy
                    state.policyEditor = editor
                    return .none
                }

            case .deleteAccountTapped(let id):
                guard state.canSubmitPortfolioMutation, state.policyEditor == nil,
                    state.portfolio?.accounts.contains(where: { $0.id == id }) == true
                else { return .none }
                state.pendingDeletion = id
                return .none

            case .deleteAccountConfirmationDismissed:
                state.pendingDeletion = nil
                return .none

            case .deleteAccountConfirmed(let id):
                guard state.canSubmitPortfolioMutation, state.policyEditor == nil,
                    state.pendingDeletion == id,
                    state.portfolio?.accounts.contains(where: { $0.id == id }) == true,
                    let revision = state.portfolio?.revision,
                    let body = try? ATADeleteAccountRequestDTO(expectedRevision: revision)
                else { return .none }
                state.pendingDeletion = nil
                return beginMutation(&state, request: .delete(id, body), kind: .delete(id))

            case .mutationFinished(let generation, let result):
                guard generation == state.mutationGeneration, state.mutationInFlight != nil
                else { return .none }
                state.mutationInFlight = nil
                switch result {
                case .succeeded(let portfolio):
                    state.portfolio = portfolio
                    state.loadState = .loaded
                    state.editor = nil
                    state.policyEditor = nil
                    state.mutationIssue = nil
                    state.reconciliationRequired = false
                    return .none
                case .failed(let issue):
                    state.mutationIssue = issue
                    if issue == .authentication {
                        state.portfolio = nil
                        state.loadState = .failed(.authentication)
                        state.reconciliationRequired = true
                        return .none
                    }
                    if issue == .revisionConflict || issue == .resourceNotFound
                        || issue == .uncertain
                    {
                        state.reconciliationRequired = true
                        state.editor?.needsReview = true
                        state.policyEditor?.needsReview = true
                        return beginLoad(&state)
                    }
                    if issue == .stateConflict {
                        state.editor?.needsReview = true
                        state.policyEditor?.needsReview = true
                    }
                    return .none
                }
            }
        }
    }

    @Dependency(\.uuid) var uuid

    private func makeAccountRequest(
        editor: ATAAccountEditor, portfolio: ATACurrentPortfolio
    ) throws -> PortfolioRequest {
        let revision = portfolio.revision
        switch editor.kind {
        case .create:
            guard !editor.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ATAAccountEditor.InputError.name
            }
            return .create(
                try ATACreateAccountRequestDTO(
                    expectedRevision: revision, name: editor.name, accountType: editor.accountType,
                    positions: editor.validatedPositions()))
        case .rename(let id):
            guard portfolio.accounts.contains(where: { $0.id == id }) else {
                throw ATAAccountEditor.InputError.accountMissing
            }
            guard !editor.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ATAAccountEditor.InputError.name
            }
            return .rename(
                id,
                try ATARenameAccountRequestDTO(
                    expectedRevision: revision, name: editor.name))
        case .holdings(let id):
            guard portfolio.accounts.contains(where: { $0.id == id }) else {
                throw ATAAccountEditor.InputError.accountMissing
            }
            return .holdings(
                id,
                try ATAReplaceAccountHoldingsRequestDTO(
                    expectedRevision: revision, positions: editor.validatedPositions()))
        }
    }

    private func kind(for editor: ATAAccountEditor.Kind) -> PortfolioMutationKind {
        switch editor {
        case .create: .create
        case .rename(let id): .rename(id)
        case .holdings(let id): .holdings(id)
        }
    }

    private func makePolicyRequest(
        editor: ATAPolicyEditor, portfolio: ATACurrentPortfolio
    ) throws -> PortfolioRequest {
        switch editor.kind {
        case .financialSettings:
            let values = try editor.financialValues()
            if values.monthlyExpensesUSD == portfolio.financialSettings.monthlyExpensesUSD
                && values.targetRunwayMonths
                    == portfolio.financialSettings.targetExpenseRunwayMonths
            {
                throw ATAPolicyEditor.InputError.unchanged
            }
            return .financialSettings(
                try ATAUpdateFinancialSettingsRequestDTO(
                    expectedRevision: portfolio.revision,
                    monthlyExpensesUSD: values.monthlyExpensesUSD,
                    targetExpenseRunwayMonths: values.targetRunwayMonths))
        case .corePosition(let symbol):
            guard let current = portfolio.corePositions.first(where: { $0.symbol == symbol })
            else { throw ATAPolicyEditor.InputError.policyMissing }
            let holdings =
                portfolio.aggregatePositions.first(where: { $0.symbol == symbol })?
                .amount ?? 0
            let values = try editor.coreValues(aggregateAmount: holdings)
            if values.hardFloor == current.hardFloor
                && values.preferredQuantity == current.preferredQuantity
            {
                throw ATAPolicyEditor.InputError.unchanged
            }
            return .corePosition(
                symbol,
                try ATAUpdateCorePositionRequestDTO(
                    expectedRevision: portfolio.revision, hardFloor: values.hardFloor,
                    preferredQuantity: values.preferredQuantity))
        }
    }

    private func kind(for editor: ATAPolicyEditor.Kind) -> PortfolioMutationKind {
        switch editor {
        case .financialSettings: .financialSettings
        case .corePosition(let symbol): .corePosition(symbol)
        }
    }

    private func beginMutation(
        _ state: inout State, request: PortfolioRequest, kind: PortfolioMutationKind
    ) -> Effect<Action> {
        state.requestGeneration += 1  // Invalidate any earlier GET before the write is sent.
        state.mutationGeneration += 1
        let generation = state.mutationGeneration
        state.mutationInFlight = kind
        state.mutationIssue = nil
        state.loadState = .loaded
        return .merge(
            .cancel(id: CancelID.load),
            .run { [client] send in
                do {
                    let current: ATACurrentPortfolio
                    switch request {
                    case .create(let body): current = try await client.createAccount(body)
                    case .rename(let id, let body):
                        current = try await client.renameAccount(id, body)
                    case .holdings(let id, let body):
                        current = try await client.updateAccountHoldings(id, body)
                    case .delete(let id, let body):
                        current = try await client.deleteAccount(id, body)
                    case .financialSettings(let body):
                        current = try await client.updateFinancialSettings(body)
                    case .corePosition(let symbol, let body):
                        current = try await client.updateCorePosition(symbol, body)
                    }
                    await send(
                        .mutationFinished(generation: generation, result: .succeeded(current)))
                } catch {
                    await send(
                        .mutationFinished(
                            generation: generation, result: .failed(Self.mapMutation(error))))
                }
            }
            .cancellable(id: CancelID.mutation)
        )
    }

    private static func mapMutation(_ error: Error) -> MutationIssue {
        guard let error = error as? ATAClientError else { return .uncertain }
        switch error {
        case .uncertainMutationOutcome, .transport, .invalidResponse:
            return .uncertain
        case .http(let failure):
            switch failure.error.knownCode {
            case .revisionConflict
            where failure.statusCode == 409
                && failure.error.reloadRequired == true:
                return .revisionConflict
            case .stateConflict where failure.statusCode == 409:
                return .stateConflict
            case .resourceNotFound where failure.statusCode == 404:
                return .resourceNotFound
            case .validationError,
                .invalidRequest where failure.statusCode == 422:
                return .validation
            case .unauthorized where failure.statusCode == 401:
                return .authentication
            default:
                return failure.statusCode >= 500 ? .uncertain : .service
            }
        case .missingCredential, .credentialUnavailable:
            return .authentication
        case .invalidConfiguration, .invalidRequest, .cancelled:
            return .service
        }
    }

    private func beginLoad(_ state: inout State) -> Effect<Action> {
        guard state.configurationAvailable else {
            state.portfolio = nil
            state.loadState = .configurationUnavailable
            return .none
        }
        guard state.credentialOperation == .idle, state.mutationInFlight == nil else {
            return .none
        }
        // This generation is the authority boundary: later reads and portfolio writes
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
