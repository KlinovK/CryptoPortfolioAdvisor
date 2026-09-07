import ComposableArchitecture
import SwiftUI

struct AnalysisDetailsView: View {
    let store: StoreOf<AnalysisDetailsFeature>
    private let financialFormatter = PortfolioFinancialFormatter()

    var body: some View {
        List {
            overviewSection
            riskSection
            actionsSection
            warningsSection
            metricsSection
            allocationsSection
            marketSection
            assetAnalysisSection
            aboutSection
        }
        .navigationTitle("Analysis Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var overviewSection: some View {
        Section {
            Label(
                AnalysisModePresentation.title(for: store.analysis.analysisMode),
                systemImage: "sparkles"
            )
            .font(.callout.weight(.semibold))

            LabeledContent("Generated") {
                Text(
                    store.analysis.generatedAt,
                    format: .dateTime.year().month(.wide).day().hour().minute()
                )
            }
        } header: {
            Text("Overview")
        }
    }

    private var riskSection: some View {
        Section("Risk Assessment") {
            Label(
                RiskPresentation.title(for: store.analysis.riskLevel),
                systemImage: RiskPresentation.systemImage(for: store.analysis.riskLevel)
            )
            .font(.title3.weight(.semibold))
            .accessibilityLabel(
                "Risk assessment: \(RiskPresentation.title(for: store.analysis.riskLevel))"
            )
        }
    }

    private var actionsSection: some View {
        Section("Recommended Actions") {
            if orderedActions.isEmpty {
                Text("No actions recommended today.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(orderedActions, id: \.id) { action in
                    actionView(action)
                }
            }
        }
    }

    private var warningsSection: some View {
        Section("Important Warnings") {
            if orderedWarnings.isEmpty {
                Label("No warnings reported.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(orderedWarnings.enumerated()), id: \.offset) { _, warning in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(
                            AnalysisDetailsPresentation.warningTitle(warning.severity),
                            systemImage: AnalysisDetailsPresentation.warningSystemImage(
                                warning.severity
                            )
                        )
                        .font(.headline)
                        if let asset = warning.asset {
                            Text(asset.rawValue)
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(warning.message)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var metricsSection: some View {
        Section("Portfolio Metrics") {
            moneyRow("Total Value", store.analysis.portfolioSummary.totalValueUSD)
            moneyRow("Stable Reserve", store.analysis.portfolioSummary.stableValueUSD)
            moneyRow("Invested", store.analysis.portfolioSummary.investedValueUSD)
            LabeledContent(
                "Stable Allocation",
                value: financialFormatter.percentage(
                    store.analysis.portfolioSummary.stableAllocationPercentage
                )
            )
            moneyRow("Open BUY Orders", store.analysis.portfolioSummary.openBuyOrdersUSD)
            moneyRow("Open SELL Orders", store.analysis.portfolioSummary.openSellOrdersUSD)
            moneyRow(
                "Deployable Capital",
                store.analysis.portfolioSummary.deployableStableUSD
            )
        }
    }

    private var allocationsSection: some View {
        Section("Allocation Breakdown") {
            if store.analysis.portfolioSummary.allocations.isEmpty {
                Text("No allocation data.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.analysis.portfolioSummary.allocations, id: \.asset) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.asset.rawValue)
                            .font(.headline)
                        Text(
                            "\(financialFormatter.usd(item.valueUSD)) · "
                                + financialFormatter.percentage(item.allocationPercentage)
                        )
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var marketSection: some View {
        Section("Market Summary") {
            Text(store.analysis.marketSummary.overview)
            LabeledContent("Market data as of") {
                Text(
                    store.analysis.marketSummary.asOf,
                    format: .dateTime.year().month().day().hour().minute()
                )
            }
        }
    }

    private var assetAnalysisSection: some View {
        Section("Asset Observations") {
            if store.analysis.assetAnalysis.isEmpty {
                Text("No asset observations.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.analysis.assetAnalysis, id: \.asset) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.asset.rawValue)
                                .font(.headline)
                            Spacer()
                            Text(financialFormatter.percentage(item.allocationPercentage))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(item.assessment)
                        Text(item.recommendation)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About This Analysis") {
            Text(
                "This app provides analytical information and does not execute trades. "
                    + "Crypto markets are volatile; you remain responsible for investment decisions."
            )
            .foregroundStyle(.secondary)

            Text(
                "Portfolio metrics and risk checks are calculated by code. "
                    + "AI may reason over minimized calculated context, but it does not replace "
                    + "deterministic validation."
            )
            .foregroundStyle(.secondary)
        }
    }

    private var orderedActions: [PortfolioAction] {
        AnalysisDetailsPresentation.orderedActions(store.analysis.actions)
    }

    private var orderedWarnings: [PortfolioWarning] {
        AnalysisDetailsPresentation.orderedWarnings(store.analysis.warnings)
    }

    private func moneyRow(_ title: String, _ value: Decimal) -> some View {
        LabeledContent(title, value: financialFormatter.usd(value))
    }

    private func actionView(_ action: PortfolioAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(AnalysisDetailsPresentation.actionTitle(action))
                    .font(.headline)
                Spacer(minLength: 8)
                Text(AnalysisDetailsPresentation.priorityTitle(action.priority))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let side = action.side {
                Text("Side: \(side.rawValue.uppercased())")
                    .font(.subheadline)
            }

            if let amount = action.amountUSD, let price = action.price {
                Text("\(financialFormatter.usd(amount)) at \(financialFormatter.usd(price))")
                    .font(.subheadline)
                    .monospacedDigit()
            } else {
                if let amount = action.amountUSD {
                    Text("Amount: \(financialFormatter.usd(amount))")
                        .font(.subheadline)
                        .monospacedDigit()
                }
                if let price = action.price {
                    Text("Price: \(financialFormatter.usd(price))")
                        .font(.subheadline)
                        .monospacedDigit()
                }
            }

            Text(action.reason)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
