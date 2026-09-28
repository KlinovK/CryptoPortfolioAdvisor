import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        TabView(selection: $store.selectedTab.sending(\.selectedTabChanged)) {
            ATADashboardView(
                store: store.scope(state: \.dashboard, action: \.dashboard)
            )
            .tabItem {
                Label("Dashboard", systemImage: "chart.pie")
            }
            .tag(AppFeature.Tab.dashboard)

            HistoryView(
                store: store.scope(state: \.history, action: \.history)
            )
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .tag(AppFeature.Tab.history)
        }
    }
}
