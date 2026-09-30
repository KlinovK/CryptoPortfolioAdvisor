import ComposableArchitecture
import SwiftUI

struct ATAHistoryView: View {
    @Bindable var store: StoreOf<ATAHistoryFeature>

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if store.loadState != .configurationUnavailable
                    && store.loadState != .credentialRequired
                {
                    latestSection
                    recentSection
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        store.send(.refreshTapped)
                    }
                    .disabled(!store.configurationAvailable || store.loadState == .loading)
                    .accessibilityIdentifier("ataHistoryRefresh")
                }
            }
            .navigationDestination(
                item: $store.scope(state: \.destination, action: \.destination)
            ) { detailStore in
                ATAAnalysisDetailView(store: detailStore)
            }
        }
        .task { await store.send(.appeared).finish() }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch store.loadState {
        case .idle,
            .loading where store.runs.isEmpty:
            Section { ProgressView("Loading ATA analysis history…") }
        case .loading:
            Section { ProgressView("Refreshing history…") }
        case .configurationUnavailable:
            Section { Text(ATAAnalysisReadIssue.configuration.message) }
        case .credentialRequired:
            Section { Text(ATAAnalysisReadIssue.credentialRequired.message) }
        case .failed(let issue):
            Section {
                Text(issue.message).foregroundStyle(.red)
                if !store.runs.isEmpty {
                    Text("Showing the last loaded server list; refresh did not complete.")
                        .foregroundStyle(.secondary)
                }
                Button("Retry") { store.send(.retryTapped) }
            }
        case .empty:
            Section { Text("No ATA analyses yet. Scheduled analyses will appear here.") }
        case .loaded:
            EmptyView()
        }
    }

    private var latestSection: some View {
        Section("Latest completed analysis") {
            switch store.latestState {
            case .idle, .loading:
                ProgressView("Loading latest…")
            case .available:
                if let detail = store.latest {
                    Button {
                        store.send(.latestTapped)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                detail.run.startedAt,
                                format: .dateTime.year().month().day().hour().minute()
                            )
                            .font(.headline)
                            Text("Run \(detail.run.runID.uuidString)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("ataLatestAnalysis")
                }
            case .unavailable:
                Text("No completed analysis is available yet.")
                    .foregroundStyle(.secondary)
            case .failed(let issue):
                Text(issue.message).foregroundStyle(.red)
                if store.latest != nil {
                    Text("Previously loaded latest analysis may be stale.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recentSection: some View {
        Section("Recent runs") {
            ForEach(store.runs, id: \.runID) { run in
                Button {
                    store.send(.runTapped(run.runID))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(
                                run.startedAt,
                                format: .dateTime.year().month().day().hour().minute()
                            )
                            .font(.headline)
                            Spacer()
                            Text(run.status.rawValue.capitalized)
                                .foregroundStyle(.secondary)
                        }
                        if let completedAt = run.completedAt {
                            Text(
                                "Completed: \(completedAt, format: .dateTime.year().month().day().hour().minute())"
                            )
                        }
                        if let cutoff = run.marketCutoff {
                            Text(
                                "Market cutoff: \(cutoff, format: .dateTime.year().month().day().hour().minute())"
                            )
                        }
                        Text("Historical snapshot: \(run.snapshotID.uuidString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                .accessibilityIdentifier("ataHistoryRun_\(run.runID.uuidString)")
            }
        }
    }
}
