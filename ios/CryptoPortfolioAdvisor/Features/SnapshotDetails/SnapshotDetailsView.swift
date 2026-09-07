import ComposableArchitecture
import SwiftUI

struct SnapshotDetailsView: View {
    let store: StoreOf<SnapshotDetailsFeature>
    private let financialFormatter = PortfolioFinancialFormatter()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.snapshot.createdAt, format: .dateTime.year().month(.wide).day())
                    Text(store.snapshot.createdAt, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                }
            }

            Section("Portfolio") {
                ForEach(store.snapshot.portfolio.positions, id: \.symbol) { position in
                    LabeledContent(position.symbol.rawValue) {
                        Text(financialFormatter.quantity(position.amount))
                            .monospacedDigit()
                    }
                }
            }

            Section("Strategy") {
                LabeledContent(
                    "Trading Style",
                    value: store.snapshot.constraints.tradingStyle.rawValue.capitalized
                )
                LabeledContent(
                    "Risk",
                    value: store.snapshot.constraints.riskTolerance.rawValue.capitalized
                )
                LabeledContent(
                    "Leverage",
                    value: store.snapshot.constraints.leverageAllowed ? "Enabled" : "Spot only"
                )
                LabeledContent(
                    "Monthly Income",
                    value: financialFormatter.usd(
                        store.snapshot.constraints.additionalMonthlyIncomeUSD
                    )
                )
                LabeledContent(
                    "Stable Reserve",
                    value: financialFormatter.usd(
                        store.snapshot.constraints.minimumStableReserveUSD
                    )
                )
            }

            Section("Orders") {
                if store.snapshot.orders.isEmpty {
                    Text("No limit orders in this snapshot.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.snapshot.orders, id: \.id) { order in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(order.symbol.rawValue)
                                .font(.headline)
                            Text(
                                "\(order.side.rawValue.capitalized) · "
                                    + order.status.rawValue.capitalized
                            )
                                .foregroundStyle(.secondary)
                            Text(
                                "\(financialFormatter.usd(order.amountUSD)) @ "
                                    + financialFormatter.usd(order.targetPrice)
                            )
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Portfolio Snapshot")
        .navigationBarTitleDisplayMode(.inline)
    }
}
