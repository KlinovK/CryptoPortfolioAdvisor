import ComposableArchitecture
import Foundation
import SwiftUI

struct ATAOrderEditorView: View {
    @Bindable var store: StoreOf<ATADashboardFeature>

    var body: some View {
        NavigationStack {
            Form {
                if let editor = store.orderEditor {
                    switch editor.kind {
                    case .create: createFields(editor)
                    case .externalFill(let id): fillFields(editor, orderID: id)
                    }
                    if let error = editor.inputError {
                        Section { Text(message(error)).foregroundStyle(.red) }
                    }
                    if let issue = store.mutationIssue {
                        Section { Text(issue.message).foregroundStyle(.red) }
                    }
                    if editor.needsReview {
                        Section("Review required") {
                            Text(
                                "Compare this draft with the refreshed server portfolio before submitting again."
                            )
                            if let portfolio = store.portfolio {
                                Text("Confirmed revision \(portfolio.revision)")
                                if case .externalFill(let id) = editor.kind {
                                    if let order = portfolio.limitOrders.first(where: {
                                        $0.id == id
                                    }) {
                                        Text("Order status: \(order.status.rawValue.capitalized)")
                                        if let account = portfolio.accounts.first(where: {
                                            $0.id == order.accountID
                                        }) {
                                            Text("Current \(account.name) holdings:")
                                            ForEach(account.positions, id: \.symbol) { position in
                                                Text(
                                                    "\(position.symbol.rawValue): \(NSDecimalNumber(decimal: position.amount).stringValue)"
                                                )
                                            }
                                        } else {
                                            Text("The owning account is no longer present.")
                                        }
                                    } else {
                                        Text("The order is no longer present.")
                                    }
                                }
                            }
                            Button("I Reviewed the Portfolio") {
                                store.send(.editorReviewAcknowledged)
                            }
                            .disabled(store.reconciliationRequired)
                            .accessibilityIdentifier("ataOrderReviewAcknowledged")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.send(.orderEditorCancelled) }
                        .disabled(store.mutationInFlight != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitLabel) { store.send(.orderEditorSubmitTapped) }
                        .disabled(
                            !store.canSubmitPortfolioMutation
                                || store.orderEditor?.needsReview == true
                        )
                        .accessibilityIdentifier("ataOrderSubmit")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if store.mutationInFlight != nil {
                    ProgressView("Saving order changes…")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
        }
    }

    private var title: String {
        switch store.orderEditor?.kind {
        case .create: "Create Limit Order"
        case .externalFill: "Record External Fill"
        case nil: "Limit Order"
        }
    }

    private var submitLabel: String {
        if case .externalFill = store.orderEditor?.kind { return "Record External Fill" }
        return "Create Limit Order"
    }

    private func createFields(_ editor: ATAOrderEditor) -> some View {
        Section {
            Picker(
                "Account",
                selection: Binding(
                    get: { store.orderEditor?.accountID },
                    set: { if let id = $0 { store.send(.orderAccountChanged(id)) } }
                )
            ) {
                Text("Select account").tag(UUID?.none)
                ForEach(store.portfolio?.accounts ?? [], id: \.id) { account in
                    Text("\(account.name) · \(account.id.uuidString)").tag(Optional(account.id))
                }
            }
            .accessibilityIdentifier("ataOrderAccount")
            Picker(
                "Asset",
                selection: Binding(
                    get: { store.orderEditor?.asset ?? .btc },
                    set: { store.send(.orderAssetChanged($0)) }
                )
            ) {
                ForEach(ATAOrderEditor.supportedAssets, id: \.self) { asset in
                    Text(asset.rawValue).tag(asset)
                }
            }
            Picker(
                "Side",
                selection: Binding(
                    get: { store.orderEditor?.side ?? .buy },
                    set: { store.send(.orderSideChanged($0)) }
                )
            ) {
                Text("BUY").tag(ATAOrderSide.buy)
                Text("SELL").tag(ATAOrderSide.sell)
            }
            TextField(
                "Target price (USD)",
                text: Binding(
                    get: { store.orderEditor?.targetPrice ?? "" },
                    set: {
                        store.send(.orderTargetPriceChanged(ATAEditableDecimalText.normalized($0)))
                    }
                )
            )
            .keyboardType(.decimalPad)
            .accessibilityIdentifier("ataOrderTargetPrice")
            TextField(
                "Quantity (asset units)",
                text: Binding(
                    get: { store.orderEditor?.quantityAsset ?? "" },
                    set: {
                        store.send(.orderQuantityChanged(ATAEditableDecimalText.normalized($0)))
                    }
                )
            )
            .keyboardType(.decimalPad)
            .accessibilityIdentifier("ataOrderQuantity")
        } header: {
            Text("Limit order")
        } footer: {
            Text(
                "This records a limit order in ATA. It does not place or execute an exchange order. Use exact decimal quantities."
            )
        }
    }

    private func fillFields(_ editor: ATAOrderEditor, orderID: UUID) -> some View {
        Group {
            Section("External execution") {
                Text(
                    "The order must already have been executed externally. This action only reconciles ATA's confirmed portfolio state; it does not execute a trade."
                )
                Text("Order ID: \(orderID.uuidString)")
                    .font(.caption)
                if let account = store.portfolio?.accounts.first(where: {
                    $0.id == editor.accountID
                }) {
                    Text("Owning account: \(account.name) · \(account.id.uuidString)")
                }
                Picker(
                    "Settlement asset",
                    selection: Binding(
                        get: { store.orderEditor?.settlementAsset },
                        set: { if let asset = $0 { store.send(.orderSettlementChanged(asset)) } }
                    )
                ) {
                    Text("Select settlement asset").tag(AssetSymbol?.none)
                    Text("USDT").tag(Optional(AssetSymbol.usdt))
                    Text("USDC").tag(Optional(AssetSymbol.usdc))
                }
                .accessibilityIdentifier("ataOrderSettlement")
            }
            Section {
                ForEach(editor.holdings) { row in
                    VStack(alignment: .leading) {
                        TextField(
                            "Symbol",
                            text: Binding(
                                get: {
                                    store.orderEditor?.holdings.first(where: { $0.id == row.id })?
                                        .symbol ?? ""
                                },
                                set: { store.send(.orderHoldingSymbolChanged(row.id, $0)) }
                            )
                        )
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        TextField(
                            "Quantity",
                            text: Binding(
                                get: {
                                    store.orderEditor?.holdings.first(where: { $0.id == row.id })?
                                        .amount ?? ""
                                },
                                set: {
                                    store.send(
                                        .orderHoldingAmountChanged(
                                            row.id, ATAEditableDecimalText.normalized($0)))
                                }
                            )
                        )
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(
                            "Quantity for \(row.symbol.isEmpty ? "new holding" : row.symbol)")
                        Button("Remove Row", role: .destructive) {
                            store.send(.orderHoldingRemoved(row.id))
                        }
                        .accessibilityLabel(
                            "Remove \(row.symbol.isEmpty ? "new holding" : row.symbol) holding")
                    }
                }
                Button("Add Holding", systemImage: "plus") {
                    store.send(.orderHoldingAdded(UUID()))
                }
            } header: {
                Text("Complete actual post-fill holdings")
            } footer: {
                Text(
                    "Enter every resulting holding for this account, not just the traded pair. Use 0 or remove a row to omit a holding. ATA will validate the final balances and core floors."
                )
            }
        }
    }

    private func message(_ error: ATAOrderEditor.InputError) -> String {
        switch error {
        case .accountMissing:
            "The selected account is no longer in the confirmed portfolio. Refresh and review."
        case .orderNotOpen: "This order is no longer open. Refresh and review before any action."
        case .unsupportedAsset: "Choose a supported order asset."
        case .targetPrice: "Enter a positive exact decimal target price using a period."
        case .quantity: "Enter a positive exact decimal asset quantity using a period."
        case .settlementAsset: "Select USDT or USDC as the actual settlement asset."
        case .holdings(let issue):
            switch issue {
            case .symbol: "Use a canonical symbol for every holding."
            case .amount: "Use an exact nonnegative decimal; 0 omits a holding."
            case .duplicateSymbol: "Each symbol may appear only once in this account."
            case .accountMissing: "The owning account is missing. Refresh and review."
            case .name: "Invalid holding."
            }
        }
    }
}
