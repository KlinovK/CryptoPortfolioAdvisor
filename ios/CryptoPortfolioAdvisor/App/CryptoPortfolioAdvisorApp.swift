import ComposableArchitecture
import SwiftData
import SwiftUI

@main
struct CryptoPortfolioAdvisorApp: App {
    private let modelContainer: ModelContainer
    private let store: StoreOf<AppFeature>

    init() {
        do {
            let modelContainer = try PersistenceContainerFactory.makeModelContainer()
            self.modelContainer = modelContainer
            self.store = Store(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.portfolioAnalysis = .live(
                    baseURL: PortfolioAPIConfiguration.currentBaseURL
                )
                $0.portfolioPersistence = .live(modelContainer: modelContainer)
            }
        } catch {
            fatalError("Unable to configure local persistence: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
                .modelContainer(modelContainer)
        }
    }
}
