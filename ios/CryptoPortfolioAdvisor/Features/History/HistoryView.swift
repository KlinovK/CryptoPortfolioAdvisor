import ComposableArchitecture
import SwiftUI

struct HistoryView: View {
    @Bindable var store: StoreOf<HistoryFeature>
    private let financialFormatter = PortfolioFinancialFormatter()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("History")
                .navigationDestination(
                    item: $store.scope(state: \.destination, action: \.destination)
                ) { detailStore in
                    AnalysisDetailsView(store: detailStore)
                }
        }
        .task {
            await store.send(.appeared).finish()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .idle, .loading:
            ProgressView("Loading analysis history…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded where store.analyses.isEmpty:
            ContentUnavailableView {
                Label("No analyses yet", systemImage: "clock")
            } description: {
                Text("Run your first portfolio analysis from the Dashboard.")
            }

        case .loaded:
            List(store.analyses, id: \.id) { analysis in
                Button {
                    store.send(.analysisTapped(analysis.id))
                } label: {
                    analysisRow(analysis)
                }
                .buttonStyle(.plain)
            }

        case .failed:
            ContentUnavailableView {
                Label(
                    "Unable to load analysis history.",
                    systemImage: "exclamationmark.triangle"
                )
            } actions: {
                Button("Retry") {
                    store.send(.retryTapped)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func analysisRow(_ analysis: PortfolioAnalysis) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(
                    analysis.generatedAt,
                    format: .dateTime.year().month(.abbreviated).day().hour().minute()
                )
                    .font(.headline)
                Text(
                    "\(RiskPresentation.title(for: analysis.riskLevel)) · "
                        + financialFormatter.usd(analysis.portfolioSummary.totalValueUSD)
                )
                    .foregroundStyle(.secondary)
                Text(count(analysis.actions.count, singular: "action"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(AnalysisModePresentation.title(for: analysis.analysisMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the full analysis")
    }

    private func count(_ value: Int, singular: String) -> String {
        "\(value) \(value == 1 ? singular : singular + "s")"
    }
}
