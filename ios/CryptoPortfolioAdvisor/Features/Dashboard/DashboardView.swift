import ComposableArchitecture
import SwiftUI

struct DashboardView: View {
    @Bindable var store: StoreOf<DashboardFeature>
    @FocusState private var focusedField: Field?
    @State private var pendingAssetRemoval: UUID?
    @State private var pendingOrderRemoval: UUID?

    private enum Field: Hashable {
        case assetSymbol(UUID)
        case assetAmount(UUID)
        case monthlyIncome
        case stableReserve
        case orderSymbol(UUID)
        case orderAmount(UUID)
        case orderPrice(UUID)
    }

    var body: some View {
        NavigationStack {
            Form {
                portfolioSection.disabled(store.isSubmitting)
                strategySection.disabled(store.isSubmitting)
                limitOrdersSection.disabled(store.isSubmitting)
                analyzeSection
            }
            .navigationTitle("Dashboard")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .confirmationDialog(
                "Remove this asset?",
                isPresented: assetRemovalIsPresented,
                titleVisibility: .visible
            ) {
                Button("Remove Asset", role: .destructive) {
                    if let id = pendingAssetRemoval {
                        store.send(.removeAsset(id: id))
                    }
                    pendingAssetRemoval = nil
                }
                Button("Cancel", role: .cancel) { pendingAssetRemoval = nil }
            } message: {
                Text("The asset will be removed from today's draft.")
            }
            .confirmationDialog(
                "Remove this limit order?",
                isPresented: orderRemovalIsPresented,
                titleVisibility: .visible
            ) {
                Button("Remove Limit Order", role: .destructive) {
                    if let id = pendingOrderRemoval {
                        store.send(.removeOrder(id: id))
                    }
                    pendingOrderRemoval = nil
                }
                Button("Cancel", role: .cancel) { pendingOrderRemoval = nil }
            } message: {
                Text("The order will be removed from today's draft.")
            }
        }
        .onAppear { store.send(.appeared) }
        .task { await store.send(.restoreRequested).finish() }
    }

    private var portfolioSection: some View {
        Section {
            if store.isPortfolioEmpty && store.draftPersistenceStatus != .loading {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Start with your current balances", systemImage: "wallet.pass")
                        .font(.headline)
                    Text("Add the crypto assets and stablecoins you currently hold.")
                    Text("Portfolio data is entered manually.")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            ForEach(store.assetPositions) { draft in
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("Asset symbol")
                    TextField("For example, BTC", text: assetSymbolBinding(for: draft.id))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .assetSymbol(draft.id))
                        .accessibilityHint("For example, BTC or USDC")
                    validationMessage(store.validationErrors.assetPositions[draft.id]?.symbol)

                    fieldLabel("Current balance")
                    TextField("0", text: assetAmountBinding(for: draft.id))
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .assetAmount(draft.id))
                    validationMessage(store.validationErrors.assetPositions[draft.id]?.amount)

                    Button(role: .destructive) {
                        focusedField = nil
                        pendingAssetRemoval = draft.id
                    } label: {
                        Label("Remove Asset", systemImage: "trash")
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 4)
            }

            Button {
                let id = UUID()
                store.send(.addAssetTapped(id: id))
                focusedField = .assetSymbol(id)
            } label: {
                Label("Add Asset", systemImage: "plus")
            }
        } header: {
            Text("Portfolio")
        } footer: {
            Text("Enter balances exactly as held. Small fractional amounts are supported.")
        }
    }

    private var strategySection: some View {
        Section {
            Picker("Trading Style", selection: tradingStyleBinding) {
                Text("Active trading").tag(TradingStyle.active)
            }

            Picker("Risk Tolerance", selection: riskToleranceBinding) {
                Text("Conservative").tag(RiskTolerance.conservative)
                Text("Moderate").tag(RiskTolerance.moderate)
                Text("Aggressive").tag(RiskTolerance.aggressive)
            }

            Toggle(isOn: leverageBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leverage")
                    Text(store.constraints.leverageAllowed ? "Enabled" : "Spot only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Additional monthly income (USD)")
                TextField("0", text: monthlyIncomeBinding)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .monthlyIncome)
                    .accessibilityLabel("Additional monthly income in US dollars")
                validationMessage(
                    store.validationErrors.constraints.additionalMonthlyIncomeUSD
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Minimum stable reserve (USD)")
                TextField("0", text: stableReserveBinding)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .stableReserve)
                    .accessibilityLabel("Minimum stable reserve in US dollars")
                validationMessage(
                    store.validationErrors.constraints.minimumStableReserveUSD
                )
            }
        } header: {
            Text("Trading Constraints")
        } footer: {
            Text("Recommendations must stay within these limits. No trade is placed by this app.")
        }
    }

    private var limitOrdersSection: some View {
        Section {
            if store.limitOrders.isEmpty {
                Text("No active or recent limit orders.")
                    .foregroundStyle(.secondary)
            }

            ForEach(store.limitOrders) { draft in
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("Asset symbol")
                    TextField("For example, BTC", text: orderSymbolBinding(for: draft.id))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .orderSymbol(draft.id))
                    validationMessage(store.validationErrors.limitOrders[draft.id]?.symbol)

                    Picker("Side", selection: orderSideBinding(for: draft.id)) {
                        Text("BUY").tag(OrderSide.buy)
                        Text("SELL").tag(OrderSide.sell)
                    }
                    .pickerStyle(.segmented)

                    fieldLabel("Order amount (USD)")
                    TextField("0", text: orderAmountBinding(for: draft.id))
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .orderAmount(draft.id))
                    validationMessage(store.validationErrors.limitOrders[draft.id]?.amountUSD)

                    fieldLabel("Limit price (USD)")
                    TextField("0", text: orderPriceBinding(for: draft.id))
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .orderPrice(draft.id))
                    validationMessage(store.validationErrors.limitOrders[draft.id]?.targetPrice)

                    Picker("Status", selection: orderStatusBinding(for: draft.id)) {
                        Text("Open").tag(OrderStatus.open)
                        Text("Filled").tag(OrderStatus.filled)
                        Text("Cancelled").tag(OrderStatus.cancelled)
                    }

                    Button(role: .destructive) {
                        focusedField = nil
                        pendingOrderRemoval = draft.id
                    } label: {
                        Label("Remove Limit Order", systemImage: "trash")
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 4)
            }

            Button {
                let id = UUID()
                store.send(.addOrderTapped(id: id, createdAt: Date()))
                focusedField = .orderSymbol(id)
            } label: {
                Label("Add Limit Order", systemImage: "plus")
            }
        } header: {
            Text("Active / Recent Limit Orders")
        } footer: {
            Text("After an order fills, update your portfolio balance manually.")
        }
    }

    private var analyzeSection: some View {
        Section {
            Button {
                focusedField = nil
                if store.shouldRetryAnalysis {
                    store.send(.retryAnalysisTapped)
                } else {
                    store.send(.analyzeButtonTapped)
                }
            } label: {
                HStack(spacing: 8) {
                    if store.isSubmitting { ProgressView() }
                    Text(store.analysisButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isSubmitting)
            .accessibilityHint("Saves today's snapshot and requests portfolio analysis")

            submissionStatusView

            if let message = store.validationErrors.form {
                validationMessage(message)
            }

            if let message = store.analysisReadinessMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Analysis complete. \(message)")
            }
        } header: {
            Text("Daily Analysis")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "This app provides analytical information and does not execute trades. "
                        + "Crypto markets are volatile; you remain responsible for investment decisions."
                )
                Text(
                    "Your manually entered portfolio is sent to the backend for analysis. "
                        + "No exchange credentials are used. When AI is enabled, only a minimized "
                        + "calculated context—not raw candles or personal identifiers—is sent to OpenAI."
                )
            }
        }
    }

    @ViewBuilder
    private var submissionStatusView: some View {
        switch store.analysisSubmissionState {
        case .submitting:
            statusMessage("Saving today's snapshot and requesting analysis…")

        case let .failed(failure):
            statusMessage(submissionFailureMessage(failure), isError: true)

        case .idle, .success:
            switch store.draftPersistenceStatus {
            case .loading:
                statusMessage("Loading your saved draft…")
            case .saving:
                statusMessage("Saving draft…")
            case .saved:
                statusMessage("Draft saved on this device")
            case let .failed(message):
                statusMessage(message, isError: true)
            case .idle:
                EmptyView()
            }
        }
    }

    private func submissionFailureMessage(
        _ failure: DashboardFeature.SubmissionFailure
    ) -> String {
        switch failure {
        case let .snapshotPersistence(message),
             let .request(message),
             let .analysisPersistence(message):
            message
        }
    }

    private func statusMessage(_ message: String, isError: Bool = false) -> some View {
        Label(
            message,
            systemImage: isError ? "exclamationmark.triangle.fill" : "info.circle"
        )
        .font(.caption)
        .foregroundStyle(isError ? Color.red : Color.secondary)
        .accessibilityLabel(isError ? "Error: \(message)" : message)
    }

    @ViewBuilder
    private func validationMessage(_ message: String?) -> some View {
        if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityLabel("Error: \(message)")
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var assetRemovalIsPresented: Binding<Bool> {
        Binding(
            get: { pendingAssetRemoval != nil },
            set: { if !$0 { pendingAssetRemoval = nil } }
        )
    }

    private var orderRemovalIsPresented: Binding<Bool> {
        Binding(
            get: { pendingOrderRemoval != nil },
            set: { if !$0 { pendingOrderRemoval = nil } }
        )
    }

    private func assetSymbolBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { store.assetPositions.first { $0.id == id }?.symbol ?? "" },
            set: { store.send(.assetSymbolChanged(id: id, value: $0)) }
        )
    }

    private func assetAmountBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { store.assetPositions.first { $0.id == id }?.amount ?? "" },
            set: { store.send(.assetAmountChanged(id: id, value: $0)) }
        )
    }

    private var tradingStyleBinding: Binding<TradingStyle> {
        Binding(
            get: { store.constraints.tradingStyle },
            set: { store.send(.tradingStyleChanged($0)) }
        )
    }

    private var riskToleranceBinding: Binding<RiskTolerance> {
        Binding(
            get: { store.constraints.riskTolerance },
            set: { store.send(.riskToleranceChanged($0)) }
        )
    }

    private var leverageBinding: Binding<Bool> {
        Binding(
            get: { store.constraints.leverageAllowed },
            set: { store.send(.leverageChanged($0)) }
        )
    }

    private var monthlyIncomeBinding: Binding<String> {
        Binding(
            get: { store.constraints.additionalMonthlyIncomeUSD },
            set: { store.send(.monthlyIncomeChanged($0)) }
        )
    }

    private var stableReserveBinding: Binding<String> {
        Binding(
            get: { store.constraints.minimumStableReserveUSD },
            set: { store.send(.stableReserveChanged($0)) }
        )
    }

    private func orderSymbolBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { store.limitOrders.first { $0.id == id }?.symbol ?? "" },
            set: { store.send(.orderSymbolChanged(id: id, value: $0)) }
        )
    }

    private func orderSideBinding(for id: UUID) -> Binding<OrderSide> {
        Binding(
            get: { store.limitOrders.first { $0.id == id }?.side ?? .buy },
            set: { store.send(.orderSideChanged(id: id, side: $0)) }
        )
    }

    private func orderAmountBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { store.limitOrders.first { $0.id == id }?.amountUSD ?? "" },
            set: { store.send(.orderAmountChanged(id: id, value: $0)) }
        )
    }

    private func orderPriceBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { store.limitOrders.first { $0.id == id }?.targetPrice ?? "" },
            set: { store.send(.orderPriceChanged(id: id, value: $0)) }
        )
    }

    private func orderStatusBinding(for id: UUID) -> Binding<OrderStatus> {
        Binding(
            get: { store.limitOrders.first { $0.id == id }?.status ?? .open },
            set: { store.send(.orderStatusChanged(id: id, status: $0)) }
        )
    }
}
