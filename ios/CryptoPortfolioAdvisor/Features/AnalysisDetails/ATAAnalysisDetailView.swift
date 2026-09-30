import ComposableArchitecture
import Foundation
import SwiftUI

struct ATAAnalysisDetailView: View {
    let store: StoreOf<ATAAnalysisDetailFeature>

    var body: some View {
        List {
            switch store.loadState {
            case .idle, .loading:
                ProgressView("Loading ATA analysis…")
            case .notFound:
                Text(ATAAnalysisReadIssue.notFound.message)
                retryButton
            case .failed(let issue):
                Text(issue.message).foregroundStyle(.red)
                retryButton
            case .loaded, .loadedWithoutResult:
                if let detail = store.detail {
                    runSection(detail.run, failureCategory: detail.failureCategory)
                    if let result = detail.result {
                        resultSections(result)
                    } else {
                        Section("Result") {
                            Text("No analysis result is available for this run.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Historical Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.send(.appeared).finish() }
    }

    private var retryButton: some View {
        Button("Retry") { store.send(.retryTapped) }
            .accessibilityIdentifier("ataAnalysisDetailRetry")
    }

    private func runSection(_ run: ATAAnalysisRun, failureCategory: String?) -> some View {
        Section("Run") {
            LabeledContent("Status", value: run.status.rawValue.capitalized)
            LabeledContent("Started") {
                Text(run.startedAt, format: .dateTime.year().month().day().hour().minute())
            }
            if let completedAt = run.completedAt {
                LabeledContent("Completed") {
                    Text(completedAt, format: .dateTime.year().month().day().hour().minute())
                }
            }
            if let cutoff = run.marketCutoff {
                LabeledContent("Market cutoff") {
                    Text(cutoff, format: .dateTime.year().month().day().hour().minute())
                }
            }
            LabeledContent("Run ID", value: run.runID.uuidString)
            LabeledContent("Historical snapshot", value: run.snapshotID.uuidString)
            if let failureCategory {
                LabeledContent("Failure category", value: failureCategory)
            }
            Text("This historical analysis does not describe the current Dashboard portfolio.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resultSections(_ result: ATAAnalysisResult) -> some View {
        Section("Analysis") {
            LabeledContent("Generated") {
                Text(result.generatedAt, format: .dateTime.year().month().day().hour().minute())
            }
            if let cutoff = result.marketCutoff {
                LabeledContent("Result cutoff") {
                    Text(cutoff, format: .dateTime.year().month().day().hour().minute())
                }
            }
            LabeledContent("Result snapshot", value: result.snapshotID.uuidString)
            LabeledContent("Market regime", value: label(result.marketRegime.rawValue))
            LabeledContent("Reasoning", value: label(result.reasoningMode.rawValue))
            if let model = result.reasoningModel {
                LabeledContent("Model", value: model)
            }
            if let warning = result.aiWarning {
                LabeledContent("AI diagnostic", value: warning)
            }
        }
        financialSection(result.financial)
        marketSection(result.market)
        Section("Warnings") {
            if result.warnings.isEmpty {
                Text("None reported").foregroundStyle(.secondary)
            } else {
                ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                    Text(label(warning))
                }
            }
        }
        Section("Recommendations · decision support only") {
            if result.recommendations.isEmpty {
                Text("No recommendations in this analysis.").foregroundStyle(.secondary)
            } else {
                ForEach(result.recommendations, id: \.recommendationID) { recommendation in
                    recommendationRow(recommendation)
                }
            }
        }
        if let configuration = result.configuration {
            configurationSection(configuration)
        }
        if let active = result.active {
            activeSections(active)
        }
        Section {
            Text("No trades were executed automatically.")
                .foregroundStyle(.secondary)
        }
    }

    private func financialSection(_ value: ATAFinancialSummary) -> some View {
        Section("Financial summary") {
            decimalRow("Portfolio value (USD)", value.totalPortfolioUSD)
            decimalRow("Cash / stables (USD)", value.currentStablesUSD)
            decimalRow("Stable allocation (%)", value.stableAllocationPercent)
            decimalRow("Required reserve (USD)", value.recommendedMinimumStablesUSD)
            decimalRow("Available to deploy (USD)", value.deployableStablesUSD)
            decimalRow("Reserve deficit (USD)", value.stableReserveDeficitUSD)
            decimalRow("Actual runway (months)", value.actualExpenseRunwayMonths)
            decimalRow("Open BUY commitments (USD)", value.openBuyCommitmentsUSD)
            decimalRow("Recommended deployment (USD)", value.recommendedDeploymentUSD)
        }
    }

    private func marketSection(_ market: ATAMarketSnapshot) -> some View {
        Section("Market data") {
            LabeledContent("As of") {
                Text(market.asOf, format: .dateTime.year().month().day().hour().minute())
            }
            LabeledContent("Source", value: market.isLive ? "Live" : "Not live")
            ForEach(market.assets, id: \.symbol) { asset in
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.symbol.rawValue).font(.headline)
                    Text("Price: \(decimal(asset.priceUSD)) USD")
                    Text("Completeness: \(label(asset.completeness.rawValue))")
                    Text(
                        "Quoted: \(asset.quotedAt, format: .dateTime.year().month().day().hour().minute())"
                    )
                    if let change = asset.technicalFeatures.change24hPct {
                        Text("24h change: \(decimal(change))%")
                    }
                    if let rsi = asset.technicalFeatures.rsi4H {
                        Text("RSI 4h: \(decimal(rsi))")
                    }
                    Text("Daily trend: \(label(asset.dailyContext.trend.rawValue))")
                }
            }
        }
    }

    private func recommendationRow(_ item: ATARecommendation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label(item.actionType.rawValue)) · \(item.asset?.rawValue ?? "Portfolio")")
                .font(.headline)
            Text("Priority: \(item.priority)")
            if let side = item.side { Text("Side: \(side.rawValue.uppercased())") }
            if let quantity = item.quantityAsset { Text("Quantity (asset): \(decimal(quantity))") }
            if let price = item.targetPrice { Text("Target price: \(decimal(price)) USD") }
            if let orderID = item.existingOrderID { Text("Existing order: \(orderID.uuidString)") }
            if let setupID = item.setupID { Text("Setup: \(setupID.uuidString)") }
            if let invalidation = item.invalidationCondition {
                Text("Invalidation: \(invalidation)")
            }
            if let reviewAt = item.reviewAt {
                Text("Review: \(reviewAt, format: .dateTime.year().month().day().hour().minute())")
            }
            if let expiresAt = item.expiresAt {
                Text(
                    "Expires: \(expiresAt, format: .dateTime.year().month().day().hour().minute())")
            }
            Text(item.reason).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func configurationSection(_ value: ATADecisionConfiguration) -> some View {
        Section("Configuration diagnostics") {
            LabeledContent("Market regime policy", value: String(value.marketRegimeVersion))
            LabeledContent("Reserve policy", value: String(value.stableReserveVersion))
            LabeledContent("Whole-plan policy", value: String(value.wholePlanVersion))
            LabeledContent("Market source", value: value.marketSource)
            if let category = value.aiFailureCategory {
                LabeledContent("AI fallback category", value: category)
            }
        }
    }

    @ViewBuilder
    private func activeSections(_ value: ATAActiveAnalysis) -> some View {
        Section("Active management") {
            LabeledContent("Severity", value: label(value.severity.rawValue))
            decimalRow("Recommended deployment (USD)", value.recommendedDeploymentUSD)
            decimalRow("Strategy dry powder (USD)", value.strategyDryPowderUSD)
            ForEach(value.assetDecisions, id: \.asset) { decision in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(decision.asset.rawValue): \(label(decision.decision.rawValue))")
                        .font(.headline)
                    Text(
                        "Quantity: \(decimal(decision.quantity)) · Tradable: \(decimal(decision.tradableQuantity))"
                    )
                    if let setupID = decision.setupID { Text("Setup: \(setupID.uuidString)") }
                }
            }
        }
        Section("Setups and triggers") {
            if value.setups.isEmpty {
                Text("No setups in this analysis.").foregroundStyle(.secondary)
            } else {
                ForEach(value.setups, id: \.id) { setup in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(setup.asset.rawValue): \(label(setup.setupType.rawValue))")
                            .font(.headline)
                        Text(
                            "Status: \(label(setup.status.rawValue)) · \(setup.direction.rawValue.uppercased())"
                        )
                        Text(
                            "Limit: \(decimal(setup.limitPrice)) · Invalidation: \(decimal(setup.invalidationPrice)) · Target: \(decimal(setup.targetPrice))"
                        )
                        Text(
                            "Risk/reward: \(decimal(setup.riskReward)) · Score v\(setup.score.version)"
                        )
                        Text("Maximum capital: \(decimal(setup.maximumCapitalUSD)) USD")
                        ForEach(Array(setup.score.components.enumerated()), id: \.offset) {
                            _, component in
                            Text(
                                "\(label(component.name)): \(component.points)/\(component.maximum) points"
                            )
                        }
                        Text("Setup ID: \(setup.id.uuidString)")
                            .font(.caption)
                        if let trigger = setup.trigger {
                            Text(
                                "Trigger: \(trigger.executionValid ? "execution-valid" : "not execution-valid")"
                            )
                            Text("Zone: \(decimal(trigger.zoneLow))–\(decimal(trigger.zoneHigh))")
                            if let transition = trigger.transitions.last {
                                Text(
                                    "Latest transition: \(label(transition.currentState.rawValue)) · \(label(transition.reason.rawValue))"
                                )
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func decimalRow(_ title: String, _ value: Decimal) -> some View {
        LabeledContent(title, value: decimal(value))
    }

    private func decimal(_ value: Decimal) -> String {
        (try? ATADecimalCodec.encode(value)) ?? NSDecimalNumber(decimal: value).stringValue
    }

    private func label(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
