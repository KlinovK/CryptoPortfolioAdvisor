import ComposableArchitecture
import Foundation
import Security
import Synchronization
import XCTest

@testable import CryptoPortfolioAdvisor

@MainActor
final class CredentialStoreTests: XCTestCase {
    private func namespace(_ url: String = "https://ata.example.com") throws -> ATAKeychainNamespace
    {
        try ATAKeychainNamespace(configuredBaseURL: url, environment: .release)
    }

    func testAbsentCredentialIsDistinctAndDeletionIsIdempotent() async throws {
        let fake = FakeATAKeychain()
        let store = KeychainCredentialStore(namespace: try namespace(), operations: fake.operations)
            .client
        do {
            _ = try await store.load()
            XCTFail("Expected absent credential")
        } catch { XCTAssertEqual(error as? CredentialStoreError, .tokenAbsent) }
        try await store.delete()
        try await store.delete()
    }

    func testSaveLoadReplaceDeleteThroughDependencyBoundary() async throws {
        let fake = FakeATAKeychain()
        let store = KeychainCredentialStore(namespace: try namespace(), operations: fake.operations)
            .client
        try await withDependencies {
            $0.ataCredentials = store
        } operation: {
            @Dependency(\.ataCredentials) var credentials
            let first = try ATABearerToken("synthetic-first")
            let second = try ATABearerToken("synthetic-second")
            try await credentials.save(first)
            let loaded = try await credentials.load()
            XCTAssertTrue(loaded.keychainData == first.keychainData)
            try await credentials.save(second)
            let replaced = try await credentials.load()
            XCTAssertTrue(replaced.keychainData == second.keychainData)
            try await credentials.delete()
            do {
                _ = try await credentials.load()
                XCTFail("Expected absent credential")
            } catch { XCTAssertEqual(error as? CredentialStoreError, .tokenAbsent) }
        }
        XCTAssertEqual(fake.state.withLock { $0.adds }, 1)
        XCTAssertEqual(fake.state.withLock { $0.updates }, 2)
    }

    func testNamespaceIsATASpecificAndOriginScoped() throws {
        XCTAssertEqual(ATAKeychainNamespace.service, "com.cryptoportfolioadvisor.ata.bearer")
        XCTAssertEqual(try namespace().account, "bearer:https://ata.example.com:443")
        XCTAssertEqual(try namespace(), try namespace("https://ATA.example.com:443/prefix"))
        XCTAssertNotEqual(try namespace(), try namespace("https://other.example.com"))
        XCTAssertNotEqual(try namespace(), try namespace("https://ata.example.com:8443"))
        XCTAssertThrowsError(try namespace("http://127.0.0.2"))
    }

    func testKeychainAttributesAreNonMigratingAndNonSynchronizing() throws {
        let query = try namespace().query
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(query[kSecAttrService as String] as? String, ATAKeychainNamespace.service)
        let attributes = ATAKeychainOperations.attributes(Data())
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    func testReadWriteDeleteFailuresAreSanitized() async throws {
        let fake = FakeATAKeychain()
        let store = KeychainCredentialStore(namespace: try namespace(), operations: fake.operations)
            .client
        fake.state.withLock { $0.failure = errSecAuthFailed }
        do {
            _ = try await store.load()
            XCTFail("Expected read failure")
        } catch { XCTAssertEqual(error as? CredentialStoreError, .readFailed) }
        do {
            try await store.save(ATABearerToken("synthetic-secret"))
            XCTFail("Expected write failure")
        } catch { XCTAssertEqual(error as? CredentialStoreError, .writeFailed) }
        do {
            try await store.delete()
            XCTFail("Expected delete failure")
        } catch { XCTAssertEqual(error as? CredentialStoreError, .deleteFailed) }
    }

    func testAddFailureDoesNotBecomeSuccessfulSave() async throws {
        let fake = FakeATAKeychain()
        fake.state.withLock { $0.addFailure = errSecDuplicateItem }
        let store = KeychainCredentialStore(namespace: try namespace(), operations: fake.operations)
            .client
        do {
            try await store.save(ATABearerToken("synthetic-secret"))
            XCTFail("Expected failure")
        } catch { XCTAssertEqual(error as? CredentialStoreError, .writeFailed) }
        XCTAssertNil(fake.state.withLock { $0.data })
    }

    func testCorruptStoredDataProducesReadFailureWithoutRenderingIt() async throws {
        for data in [Data([0xff]), Data(), Data("Bearer synthetic-secret".utf8)] {
            let fake = FakeATAKeychain()
            fake.state.withLock { $0.data = data }
            let store = KeychainCredentialStore(
                namespace: try namespace(), operations: fake.operations
            ).client
            do {
                _ = try await store.load()
                XCTFail("Expected corrupt credential failure")
            } catch { XCTAssertEqual(error as? CredentialStoreError, .readFailed) }
        }
    }

    func testTokenValidationAndDescriptionDoNotExposeSecret() throws {
        for invalid in ["", " ", "token with-space", "token\r\nheader", "token\u{0}"] {
            XCTAssertThrowsError(try ATABearerToken(invalid)) {
                XCTAssertEqual($0 as? CredentialStoreError, .invalidToken)
            }
        }
        let secret = "synthetic-secret"
        let token = try ATABearerToken(secret)
        XCTAssertFalse(String(describing: token).contains(secret))
        XCTAssertFalse(String(reflecting: token).contains(secret))
        XCTAssertFalse(
            Mirror(reflecting: token).children.contains {
                String(describing: $0.value).contains(secret)
            })
        for error in [
            CredentialStoreError.tokenAbsent, .readFailed, .writeFailed, .deleteFailed,
            .invalidToken,
        ] {
            XCTAssertFalse(String(reflecting: error).contains(secret))
        }
    }

    func testUnconfiguredDependencyDoesNotAccessKeychain() async {
        do {
            _ = try await CredentialStore.testValue.load()
            XCTFail("Expected configuration failure")
        } catch { XCTAssertEqual(error as? CredentialStoreError, .notConfigured) }
    }
}

// All credential adapter tests use this in-memory seam, never the login/simulator Keychain.
private final class FakeATAKeychain: Sendable {
    struct State {
        var data: Data?
        var failure: OSStatus?
        var addFailure: OSStatus?
        var adds = 0
        var updates = 0
    }
    let state = Mutex(State())

    var operations: ATAKeychainOperations {
        ATAKeychainOperations(
            read: { _ in
                self.state.withLock { state in
                    if let failure = state.failure { return (failure, nil) }
                    return (state.data == nil ? errSecItemNotFound : errSecSuccess, state.data)
                }
            },
            update: { _, data in
                self.state.withLock { state in
                    state.updates += 1
                    if let failure = state.failure { return failure }
                    guard state.data != nil else { return errSecItemNotFound }
                    state.data = data
                    return errSecSuccess
                }
            },
            add: { _, data in
                self.state.withLock { state in
                    state.adds += 1
                    if let failure = state.addFailure { return failure }
                    state.data = data
                    return errSecSuccess
                }
            },
            delete: { _ in
                self.state.withLock { state in
                    if let failure = state.failure { return failure }
                    guard state.data != nil else { return errSecItemNotFound }
                    state.data = nil
                    return errSecSuccess
                }
            }
        )
    }
}
