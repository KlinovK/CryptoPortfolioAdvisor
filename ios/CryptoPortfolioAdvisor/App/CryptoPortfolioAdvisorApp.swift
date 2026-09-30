import ComposableArchitecture
import SwiftUI

@main
struct CryptoPortfolioAdvisorApp: App {
    private let store: StoreOf<AppFeature>

    init() {
        let ata = Self.configureATA()
        self.store = Store(
            initialState: AppFeature.State(
                dashboard: ATADashboardFeature.State(configurationAvailable: ata != nil),
                history: ATAHistoryFeature.State(configurationAvailable: ata != nil)
            )
        ) {
            AppFeature()
        } withDependencies: {
            if let ata {
                $0.ataCredentials = ata.credentials
                $0.ataClient = ata.client
            }
        }
    }

    private static func configureATA() -> (client: ATAClient, credentials: CredentialStore)? {
        let configuredURL =
            Bundle.main.object(
                forInfoDictionaryKey: ATAAPIConfiguration.infoDictionaryKey) as? String
        #if DEBUG
            let environment: ATAAPIEnvironment = .debug
        #else
            let environment: ATAAPIEnvironment = .release
        #endif
        guard
            let credentials = try? CredentialStore.keychain(
                configuredBaseURL: configuredURL, environment: environment),
            let client = try? ATAClient.live(
                configuredBaseURL: configuredURL, environment: environment,
                credentials: credentials)
        else { return nil }
        return (client, credentials)
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
        }
    }
}
