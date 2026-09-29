import ComposableArchitecture
import Foundation
import SwiftUI

struct ATAPolicyEditorView: View {
    @Bindable var store: StoreOf<ATADashboardFeature>

    var body: some View {
        NavigationStack {
            Form {
                if let editor = store.policyEditor {
                    Section {
                        decimalField(firstLabel(for: editor.kind), first: true)
                        decimalField(secondLabel(for: editor.kind), first: false)
                        if let version = editor.policyVersion {
                            LabeledContent("Policy version", value: String(version))
                        }
                    } header: {
                        Text(title(for: editor.kind))
                    } footer: {
                        Text(
                            "Use a period for decimals. Values are sent exactly; no trades are executed."
                        )
                    }
                    if let error = editor.inputError {
                        Section {
                            Text(error.message)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("ataPolicyInputError")
                        }
                    }
                    if let issue = store.mutationIssue {
                        Section { Text(issue.message).foregroundStyle(.red) }
                    }
                    if editor.needsReview {
                        Section("Review required") {
                            Text(
                                "Compare your draft with the confirmed server values before submitting again."
                            )
                            if let portfolio = store.portfolio {
                                Text("Confirmed revision \(portfolio.revision)")
                                confirmedValues(editor.kind, portfolio: portfolio)
                            }
                            Button("I Reviewed the Portfolio") {
                                store.send(.editorReviewAcknowledged)
                            }
                            .disabled(store.reconciliationRequired)
                            .accessibilityIdentifier("ataPolicyReviewAcknowledged")
                        }
                    }
                }
            }
            .navigationTitle(store.policyEditor.map { title(for: $0.kind) } ?? "Policy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.send(.policyEditorCancelled) }
                        .disabled(store.mutationInFlight != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.send(.policyEditorSubmitTapped) }
                        .disabled(
                            !store.canSubmitPortfolioMutation
                                || store.policyEditor?.needsReview == true
                        )
                        .accessibilityIdentifier("ataPolicySubmit")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if store.mutationInFlight != nil {
                    ProgressView("Saving policy changes…")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
        }
    }

    private func decimalField(_ label: String, first: Bool) -> some View {
        TextField(
            label,
            text: Binding(
                get: {
                    first
                        ? store.policyEditor?.firstValue ?? ""
                        : store.policyEditor?.secondValue ?? ""
                },
                set: {
                    store.send(first ? .policyFirstValueChanged($0) : .policySecondValueChanged($0))
                }
            )
        )
        .keyboardType(.decimalPad)
        .accessibilityIdentifier(first ? "ataPolicyFirstValue" : "ataPolicySecondValue")
    }

    private func title(for kind: ATAPolicyEditor.Kind) -> String {
        switch kind {
        case .financialSettings: "Financial Settings"
        case .corePosition(let symbol): "\(symbol.rawValue) Core Policy"
        }
    }

    private func firstLabel(for kind: ATAPolicyEditor.Kind) -> String {
        switch kind {
        case .financialSettings: "Monthly expenses (USD)"
        case .corePosition: "Hard floor"
        }
    }

    private func secondLabel(for kind: ATAPolicyEditor.Kind) -> String {
        switch kind {
        case .financialSettings: "Target runway (months)"
        case .corePosition: "Preferred quantity"
        }
    }

    @ViewBuilder
    private func confirmedValues(
        _ kind: ATAPolicyEditor.Kind, portfolio: ATACurrentPortfolio
    ) -> some View {
        switch kind {
        case .financialSettings:
            Text("Monthly expenses: \(decimal(portfolio.financialSettings.monthlyExpensesUSD)) USD")
            Text(
                "Target runway: \(decimal(portfolio.financialSettings.targetExpenseRunwayMonths)) months"
            )
        case .corePosition(let symbol):
            if let core = portfolio.corePositions.first(where: { $0.symbol == symbol }) {
                Text("Hard floor: \(decimal(core.hardFloor))")
                Text("Preferred: \(decimal(core.preferredQuantity))")
            } else {
                Text("This core policy is no longer in the confirmed portfolio.")
            }
        }
    }

    private func decimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

extension ATAPolicyEditor.InputError {
    fileprivate var message: String {
        switch self {
        case .monthlyExpenses: "Enter positive monthly expenses as an exact decimal."
        case .targetRunway: "Enter a positive target runway as an exact decimal number of months."
        case .hardFloor: "Enter a positive hard floor as an exact decimal."
        case .preferredQuantity: "Enter a positive preferred quantity as an exact decimal."
        case .preferredBelowFloor: "Preferred quantity must be at least the hard floor."
        case .floorExceedsHoldings: "The hard floor cannot exceed confirmed aggregate holdings."
        case .unsupportedCorePolicy: "This core policy version or asset cannot be edited here."
        case .policyMissing: "This policy is no longer in the loaded portfolio. Refresh first."
        case .unchanged: "No changes to save."
        }
    }
}
