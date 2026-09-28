import ComposableArchitecture
import Foundation
import SwiftUI

struct ATADashboardView: View {
    @Bindable var store: StoreOf<ATADashboardFeature>
    @State private var showsCredentialSheet = false
    @State private var showsDeleteConfirmation = false
    @State private var credentialInput = ""
    @State private var invalidCredentialInput = false

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                if let portfolio = store.portfolio {
                    portfolioSections(portfolio)
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                if store.configurationAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            store.send(.refreshTapped)
                        }
                        .disabled(store.credentialOperation != .idle)
                        .accessibilityIdentifier("ataPortfolioRefresh")
                    }
                }
            }
            .sheet(isPresented: $showsCredentialSheet, onDismiss: clearCredentialInput) {
                credentialSheet
            }
            .confirmationDialog(
                "Remove ATA credential?", isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Credential", role: .destructive) {
                    store.send(.credentialDeleteRequested)
                }
            } message: {
                Text("The confirmed portfolio will be hidden until a credential is saved.")
            }
        }
        .onAppear { store.send(.appeared) }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Confirmed portfolio") {
            switch store.loadState {
            case .configurationUnavailable:
                Label("ATA backend URL is not configured for this build.", systemImage: "gear")
                    .accessibilityIdentifier("ataConfigurationUnavailable")
            case .credentialRequired:
                Label("An ATA credential is required.", systemImage: "lock")
                configureCredentialButton
            case .loading:
                HStack {
                    ProgressView()
                    Text(
                        store.isRefreshing
                            ? "Refreshing confirmed portfolio…" : "Loading portfolio…")
                }
                .accessibilityIdentifier("ataPortfolioLoading")
            case .loaded:
                if let portfolio = store.portfolio {
                    Text("Server-confirmed revision \(portfolio.revision)")
                        .accessibilityIdentifier("ataPortfolioRevision")
                    Text(
                        "Confirmed \(portfolio.confirmedAt, format: .dateTime.year().month().day().hour().minute())"
                    )
                    .foregroundStyle(.secondary)
                }
            case .uninitialized:
                Label("No confirmed portfolio exists on the ATA server.", systemImage: "tray")
                Text("Initial portfolio setup is not available in this version.")
                    .foregroundStyle(.secondary)
            case .failed(let failure):
                Label(message(for: failure), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("ataPortfolioError")
                if store.portfolio != nil {
                    Text("Showing the last loaded server portfolio; refresh did not complete.")
                        .foregroundStyle(.secondary)
                }
                Button("Retry") { store.send(.retryTapped) }
                    .accessibilityIdentifier("ataPortfolioRetry")
                if failure == .authentication || failure == .credentialStorage {
                    configureCredentialButton
                }
            }

            if store.configurationAvailable && store.loadState != .credentialRequired {
                Button("Replace Credential") { showsCredentialSheet = true }
                    .disabled(store.credentialOperation != .idle)
                    .accessibilityIdentifier("ataCredentialReplace")
                Button("Delete Credential", role: .destructive) {
                    showsDeleteConfirmation = true
                }
                .disabled(store.credentialOperation != .idle)
                .accessibilityIdentifier("ataCredentialDelete")
            }
            if store.credentialOperation != .idle {
                ProgressView("Updating credential…")
            }
        }
    }

    private var configureCredentialButton: some View {
        Button("Configure Credential") { showsCredentialSheet = true }
            .disabled(store.credentialOperation != .idle)
            .accessibilityIdentifier("ataCredentialConfigure")
    }

    private var credentialSheet: some View {
        NavigationStack {
            Form {
                Section("ATA bearer credential") {
                    SecureField("Bearer token", text: $credentialInput)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("ataCredentialEntry")
                    Text("The saved credential is never shown here.")
                        .foregroundStyle(.secondary)
                    if invalidCredentialInput {
                        Text("Enter a token without whitespace or control characters.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("ATA Credential")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showsCredentialSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Credential") { saveCredential() }
                        .accessibilityIdentifier("ataCredentialSave")
                }
            }
        }
    }

    private func saveCredential() {
        guard let token = try? ATABearerToken(credentialInput) else {
            credentialInput = ""
            invalidCredentialInput = true
            return
        }
        clearCredentialInput()
        showsCredentialSheet = false
        store.send(.credentialSaveRequested(token))
    }

    private func clearCredentialInput() {
        credentialInput = ""
        invalidCredentialInput = false
    }

    @ViewBuilder
    private func portfolioSections(_ portfolio: ATACurrentPortfolio) -> some View {
        Section("Accounts") {
            if portfolio.accounts.isEmpty { Text("No accounts") }
            ForEach(portfolio.accounts, id: \.id) { account in
                VStack(alignment: .leading, spacing: 6) {
                    Text(account.name).font(.headline)
                    Text("\(accountType(account.type)) · \(account.id.uuidString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(account.positions, id: \.symbol) { position in
                        Text("\(position.symbol.rawValue): \(decimal(position.amount))")
                    }
                    if account.positions.isEmpty { Text("No holdings") }
                }
                .padding(.vertical, 4)
            }
        }

        Section("Aggregate positions") {
            ForEach(portfolio.aggregatePositions, id: \.symbol) { position in
                Text("\(position.symbol.rawValue): \(decimal(position.amount))")
            }
            if portfolio.aggregatePositions.isEmpty { Text("No positions") }
        }

        Section("Financial settings") {
            LabeledContent(
                "Monthly expenses",
                value: "$\(decimal(portfolio.financialSettings.monthlyExpensesUSD))")
            LabeledContent(
                "Target runway",
                value: "\(decimal(portfolio.financialSettings.targetExpenseRunwayMonths)) months")
        }

        Section("Core positions") {
            ForEach(portfolio.corePositions, id: \.symbol) { core in
                VStack(alignment: .leading, spacing: 4) {
                    Text(core.symbol.rawValue).font(.headline)
                    Text("Hard floor: \(decimal(core.hardFloor))")
                    Text("Preferred: \(decimal(core.preferredQuantity))")
                    Text("Policy version: \(core.policyVersion)")
                }
            }
            if portfolio.corePositions.isEmpty { Text("No core-position policies") }
        }

        Section("Limit orders") {
            ForEach(portfolio.limitOrders, id: \.id) { order in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(order.side.rawValue.uppercased()) \(order.asset.rawValue)")
                        .font(.headline)
                    Text(
                        "Account: \(portfolio.accounts.first(where: { $0.id == order.accountID })?.name ?? order.accountID.uuidString)"
                    )
                    Text(
                        "Quantity: \(decimal(order.quantityAsset)) · Limit: $\(decimal(order.targetPrice))"
                    )
                    Text("Status: \(order.status.rawValue.capitalized)")
                    Text("Order ID: \(order.id.uuidString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if portfolio.limitOrders.isEmpty { Text("No limit orders") }
        }
    }

    private func decimal(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }

    private func accountType(_ type: ATAAccountType) -> String {
        switch type {
        case .binance: "Binance"
        case .externalWallet: "External wallet"
        case .otherExchange: "Other exchange"
        case .manual: "Manual"
        }
    }

    private func message(for failure: ATADashboardFeature.Failure) -> String {
        switch failure {
        case .authentication: "ATA rejected the credential. Replace or delete it to continue."
        case .transport: "Unable to reach ATA. Try again."
        case .incompatibleResponse: "ATA returned an incompatible portfolio response."
        case .service: "ATA could not load the portfolio. Try again."
        case .credentialStorage: "Unable to access the ATA credential on this device."
        }
    }
}
