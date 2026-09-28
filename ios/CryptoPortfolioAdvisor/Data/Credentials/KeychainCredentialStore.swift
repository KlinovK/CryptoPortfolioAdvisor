import Foundation
import Security

struct ATAKeychainNamespace: Equatable, Sendable {
    static let service = "com.cryptoportfolioadvisor.ata.bearer"
    let account: String

    init(configuredBaseURL: String?, environment: ATAAPIEnvironment) throws {
        let url = try ATAAPIConfiguration.baseURL(
            configuredValue: configuredBaseURL, environment: environment)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let scheme = components.scheme!.lowercased()
        let host = components.host!.lowercased()
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        // Distinct from CPA and scoped to the approved ATA origin, not a global bearer slot.
        account = "bearer:\(scheme)://\(host):\(port)"
    }

    var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }
}

// A narrow synchronous Security seam. CF dictionaries never cross an actor boundary.
struct ATAKeychainOperations: Sendable {
    var read: @Sendable (ATAKeychainNamespace) -> (OSStatus, Data?)
    var update: @Sendable (ATAKeychainNamespace, Data) -> OSStatus
    var add: @Sendable (ATAKeychainNamespace, Data) -> OSStatus
    var delete: @Sendable (ATAKeychainNamespace) -> OSStatus

    static let security = Self(
        read: { namespace in
            var query = namespace.query
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? Data)
        },
        update: { namespace, data in
            SecItemUpdate(namespace.query as CFDictionary, attributes(data) as CFDictionary)
        },
        add: { namespace, data in
            let query = namespace.query.merging(attributes(data)) { _, new in new }
            return SecItemAdd(query as CFDictionary, nil)
        },
        delete: { namespace in SecItemDelete(namespace.query as CFDictionary) }
    )

    static func attributes(_ data: Data) -> [String: Any] {
        [
            kSecValueData as String: data,
            // Foreground API access only. No iCloud synchronization or migration to another device.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
    }
}

actor KeychainCredentialStore {
    private let namespace: ATAKeychainNamespace
    private let operations: ATAKeychainOperations

    init(namespace: ATAKeychainNamespace, operations: ATAKeychainOperations = .security) {
        self.namespace = namespace
        self.operations = operations
    }

    nonisolated var client: CredentialStore {
        CredentialStore(
            load: { try await self.load() },
            save: { try await self.save($0) },
            delete: { try await self.delete() }
        )
    }

    private func load() throws -> ATABearerToken {
        try Task.checkCancellation()
        let (status, data) = operations.read(namespace)
        if status == errSecItemNotFound { throw CredentialStoreError.tokenAbsent }
        guard status == errSecSuccess, let data,
            let text = String(data: data, encoding: .utf8),
            let token = try? ATABearerToken(text)
        else { throw CredentialStoreError.readFailed }
        return token
    }

    private func save(_ token: ATABearerToken) throws {
        try Task.checkCancellation()
        let data = token.keychainData
        let status = operations.update(namespace, data)
        if status == errSecItemNotFound {
            guard operations.add(namespace, data) == errSecSuccess else {
                throw CredentialStoreError.writeFailed
            }
        } else if status != errSecSuccess {
            throw CredentialStoreError.writeFailed
        }
    }

    private func delete() throws {
        try Task.checkCancellation()
        let status = operations.delete(namespace)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.deleteFailed
        }
    }
}

extension CredentialStore {
    static func keychain(
        configuredBaseURL: String?, environment: ATAAPIEnvironment
    ) throws -> Self {
        KeychainCredentialStore(
            namespace: try ATAKeychainNamespace(
                configuredBaseURL: configuredBaseURL, environment: environment)
        ).client
    }
}
