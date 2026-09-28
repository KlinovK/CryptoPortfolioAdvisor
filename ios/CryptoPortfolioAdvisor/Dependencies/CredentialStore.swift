import ComposableArchitecture
import Foundation

// Not Codable or feature state. Ordinary printing/reflection never renders the secret.
struct ATABearerToken: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let value: String

    init(_ value: String) throws {
        guard !value.isEmpty,
            !value.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || CharacterSet.controlCharacters.contains($0)
            })
        else { throw CredentialStoreError.invalidToken }
        self.value = value
    }

    var description: String { "ATABearerToken(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["credential": "<redacted>"]) }

    // Only transport and secure-storage adapters need these representations.
    var authorizationHeader: String { "Bearer " + value }
    var keychainData: Data { Data(value.utf8) }

    func redacting(from text: String) -> String {
        text.replacingOccurrences(of: value, with: "<redacted>")
    }
}

enum CredentialStoreError: Error, Equatable, Sendable {
    case tokenAbsent
    case readFailed
    case writeFailed
    case deleteFailed
    case invalidToken
    case notConfigured
}

struct CredentialStore: Sendable {
    var load: @Sendable () async throws -> ATABearerToken
    var save: @Sendable (ATABearerToken) async throws -> Void
    var delete: @Sendable () async throws -> Void
}

extension CredentialStore: DependencyKey {
    // Future composition explicitly selects an ATA origin; no Keychain access at registration.
    static let liveValue = Self(
        load: { throw CredentialStoreError.notConfigured },
        save: { _ in throw CredentialStoreError.notConfigured },
        delete: { throw CredentialStoreError.notConfigured }
    )
    static let testValue: Self = liveValue
    static let previewValue: Self = liveValue
}

extension DependencyValues {
    var ataCredentials: CredentialStore {
        get { self[CredentialStore.self] }
        set { self[CredentialStore.self] = newValue }
    }
}
