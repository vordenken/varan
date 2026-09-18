import SwiftData
import XCTest
@testable import Varan

final class PersistenceTests: XCTestCase {
  func testAppModelContainerCanBePreparedAsynchronously() async throws {
    let container = try await AppModelContainer.make(inMemory: true)
    let context = ModelContext(container)
    let profile = ServerProfile(
      name: "Async Lab",
      address: try ServerAddress("async.komodo.local"),
      authenticationKind: .apiKey
    )

    context.insert(profile)
    try context.save()

    XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServerProfile>()), 1)
  }

  func testServerProfilePersistsWithoutCredentials() throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: ServerProfile.self, configurations: configuration)
    let context = ModelContext(container)
    let profile = ServerProfile(
      name: "Home Lab",
      address: try ServerAddress("komodo.local"),
      authenticationKind: .apiKey
    )

    context.insert(profile)
    try context.save()
    let storedProfiles = try context.fetch(FetchDescriptor<ServerProfile>())

    XCTAssertEqual(storedProfiles.count, 1)
    XCTAssertEqual(storedProfiles[0].name, "Home Lab")
    XCTAssertEqual(storedProfiles[0].baseURL, "https://komodo.local")
    XCTAssertEqual(storedProfiles[0].authenticationKind, .apiKey)
    XCTAssertEqual(storedProfiles[0].credentialAccount, profile.id.uuidString)
  }

  func testStoredCredentialsRoundTripThroughKeychain() async throws {
    let store = KeychainStore(service: "VaranTests.\(UUID().uuidString)")
    let account = UUID().uuidString
    let credentials = StoredCredentials.apiKey("key-id", secret: "secret-value")

    try await store.save(credentials, for: account)
    let restoredCredentials = try await store.credentials(for: account)
    try await store.deleteSecret(for: account)

    XCTAssertEqual(restoredCredentials, credentials)
  }

  func testBearerCredentialsCreateBearerAuthentication() {
    let credentials = StoredCredentials.bearerToken("signed-token")

    switch credentials.authentication {
    case .bearerToken(let token):
      XCTAssertEqual(token, "signed-token")
    case .apiKey:
      XCTFail("Expected bearer-token authentication")
    }
  }

  func testAPIKeyCredentialsCreateAPIKeyAuthentication() {
    let credentials = StoredCredentials.apiKey("key-id", secret: "secret-value")

    switch credentials.authentication {
    case .apiKey(let key, let secret):
      XCTAssertEqual(key, "key-id")
      XCTAssertEqual(secret, "secret-value")
    case .bearerToken:
      XCTFail("Expected API-key authentication")
    }
  }

  func testKeychainErrorsProvideSafeDescriptions() {
    XCTAssertFalse(KeychainStoreError.invalidCredentialData.localizedDescription.isEmpty)
    XCTAssertFalse(KeychainStoreError.unexpectedStatus(-1).localizedDescription.isEmpty)
  }

  func testInvalidStoredCredentialsAreRejected() async throws {
    let store = KeychainStore(service: "VaranTests.\(UUID().uuidString)")
    let account = UUID().uuidString
    try await store.save("not-json", for: account)

    do {
      _ = try await store.credentials(for: account)
      XCTFail("Expected invalid credential data")
    } catch {
      XCTAssertEqual(error as? KeychainStoreError, .invalidCredentialData)
    }
    try await store.deleteSecret(for: account)
  }

  func testProfileCanChangeAuthenticationKindAndRestoreAddress() throws {
    let profile = ServerProfile(
      name: "Home Lab",
      address: try ServerAddress("komodo.local"),
      authenticationKind: .apiKey
    )

    profile.authenticationKind = .bearerToken

    XCTAssertEqual(profile.authenticationKind, .bearerToken)
    XCTAssertEqual(try profile.address.url.absoluteString, "https://komodo.local")
  }

  func testProfileUpdatePreservesIdentityAndCredentialAccount() throws {
    let profile = ServerProfile(
      name: "Home Lab",
      address: try ServerAddress("komodo.local"),
      authenticationKind: .apiKey
    )
    let originalID = profile.id
    let originalCredentialAccount = profile.credentialAccount

    profile.update(
      name: "Production",
      address: try ServerAddress("https://production.example.com"),
      authenticationKind: .bearerToken
    )

    XCTAssertEqual(profile.id, originalID)
    XCTAssertEqual(profile.credentialAccount, originalCredentialAccount)
    XCTAssertEqual(profile.name, "Production")
    XCTAssertEqual(profile.baseURL, "https://production.example.com")
    XCTAssertEqual(profile.authenticationKind, .bearerToken)
  }
}