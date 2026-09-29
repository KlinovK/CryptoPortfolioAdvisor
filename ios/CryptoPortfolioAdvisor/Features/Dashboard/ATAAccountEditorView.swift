import ComposableArchitecture
import SwiftUI

struct ATAAccountEditorView: View {
    @Bindable var store: StoreOf<ATADashboardFeature>

    var body: some View {
        NavigationStack {
            Form {
                if let editor = store.editor {
                    nameSection(editor)
                    if editor.kind == .create || isHoldings(editor.kind) {
                        holdingsSection(editor)
                    }
                    if let inputError = editor.inputError {
                        Section {
                            Text(message(for: inputError))
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("ataAccountInputError")
                        }
                    }
                    if let issue = store.mutationIssue {
                        Section {
                            Text(issue.message)
                                .foregroundStyle(.red)
                        }
                    }
                    if editor.needsReview {
                        Section("Review required") {
                            Text(
                                "Compare these draft values with the confirmed state before submitting again."
                            )
                            if let portfolio = store.portfolio {
                                Text("Confirmed revision \(portfolio.revision)")
                                confirmedAccountSummary(editor, portfolio: portfolio)
                            }
                            Button("I Reviewed the Portfolio") {
                                store.send(.editorReviewAcknowledged)
                            }
                            .disabled(store.reconciliationRequired)
                            .accessibilityIdentifier("ataAccountReviewAcknowledged")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.send(.editorCancelled) }
                        .disabled(store.mutationInFlight != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.send(.editorSubmitTapped) }
                        .disabled(
                            !store.canSubmitAccountMutation
                                || store.editor?.needsReview == true
                        )
                        .accessibilityIdentifier("ataAccountSubmit")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if store.mutationInFlight != nil {
                    ProgressView("Saving account changes…")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
        }
    }

    private var title: String {
        switch store.editor?.kind {
        case .create: "Create Account"
        case .rename: "Rename Account"
        case .holdings: "Replace Holdings"
        case nil: "Account"
        }
    }

    @ViewBuilder
    private func nameSection(_ editor: ATAAccountEditor) -> some View {
        if editor.kind == .create || isRename(editor.kind) {
            Section("Account") {
                TextField(
                    "Name",
                    text: Binding(
                        get: { store.editor?.name ?? "" },
                        set: { store.send(.editorNameChanged($0)) }
                    )
                )
                .accessibilityIdentifier("ataAccountName")
                if editor.kind == .create {
                    Picker(
                        "Account type",
                        selection: Binding(
                            get: { store.editor?.accountType ?? .manual },
                            set: { store.send(.editorTypeChanged($0)) }
                        )
                    ) {
                        Text("Binance").tag(ATAAccountType.binance)
                        Text("External wallet").tag(ATAAccountType.externalWallet)
                        Text("Other exchange").tag(ATAAccountType.otherExchange)
                        Text("Manual").tag(ATAAccountType.manual)
                    }
                    .accessibilityIdentifier("ataAccountType")
                }
            }
        }
    }

    private func holdingsSection(_ editor: ATAAccountEditor) -> some View {
        Section {
            ForEach(editor.holdings) { row in
                VStack(alignment: .leading) {
                    TextField(
                        "Symbol",
                        text: Binding(
                            get: {
                                store.editor?.holdings.first(where: { $0.id == row.id })?.symbol
                                    ?? ""
                            },
                            set: { store.send(.holdingSymbolChanged(row.id, $0)) }
                        )
                    )
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    TextField(
                        "Quantity",
                        text: Binding(
                            get: {
                                store.editor?.holdings.first(where: { $0.id == row.id })?.amount
                                    ?? ""
                            },
                            set: { store.send(.holdingAmountChanged(row.id, $0)) }
                        )
                    )
                    .keyboardType(.decimalPad)
                    Button("Remove Row", role: .destructive) {
                        store.send(.holdingRemoved(row.id))
                    }
                }
            }
            Button("Add Holding", systemImage: "plus") {
                store.send(.holdingAdded(UUID()))
            }
            .accessibilityIdentifier("ataHoldingAdd")
        } header: {
            Text("Complete account holdings")
        } footer: {
            Text(
                "Save replaces this account's complete holdings list. Use 0 or remove a row to omit a holding. Use a period for decimals; no trades are executed."
            )
        }
    }

    private func isRename(_ kind: ATAAccountEditor.Kind) -> Bool {
        if case .rename = kind { return true }
        return false
    }

    @ViewBuilder
    private func confirmedAccountSummary(
        _ editor: ATAAccountEditor, portfolio: ATACurrentPortfolio
    ) -> some View {
        switch editor.kind {
        case .create:
            Text("Current accounts: \(portfolio.accounts.count)")
        case .rename(let id), .holdings(let id):
            if let account = portfolio.accounts.first(where: { $0.id == id }) {
                Text("Current name: \(account.name)")
                ForEach(account.positions, id: \.symbol) { position in
                    Text(
                        "\(position.symbol.rawValue): \(NSDecimalNumber(decimal: position.amount).stringValue)"
                    )
                }
                if account.positions.isEmpty { Text("Current holdings: none") }
            } else {
                Text("This account is no longer in the confirmed portfolio.")
            }
        }
    }

    private func isHoldings(_ kind: ATAAccountEditor.Kind) -> Bool {
        if case .holdings = kind { return true }
        return false
    }

    private func message(for error: ATAAccountEditor.InputError) -> String {
        switch error {
        case .name: "Enter an account name."
        case .symbol: "Use a canonical asset symbol (1–20 letters, numbers, '.', '_' or '-')."
        case .amount: "Enter a positive exact decimal quantity, or 0 to omit the holding."
        case .duplicateSymbol: "Each symbol may appear only once in this account."
        case .accountMissing: "This account is no longer in the loaded portfolio. Refresh first."
        }
    }
}

extension ATADashboardFeature.MutationIssue {
    var message: String {
        switch self {
        case .revisionConflict:
            "Portfolio changed on the server. Reloading; review your draft before resubmitting."
        case .stateConflict:
            "The server rejected this change against the current portfolio. Review it before resubmitting."
        case .resourceNotFound: "This account was not found on the server. Reloading for review."
        case .validation: "The server rejected the account details. Review the draft and try again."
        case .uncertain:
            "The update outcome is uncertain. Waiting for a server reload before further changes."
        case .reviewRequired:
            "Server portfolio reloaded. Review your draft before another submission."
        case .authentication: "ATA rejected the credential. Replace it before editing accounts."
        case .service: "The account update was not accepted. Review before trying again."
        }
    }
}
