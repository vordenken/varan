import Foundation
import XCTest
@testable import Varan

final class KeychainStoreTests: XCTestCase {
  func testSecretLifecycleIsScopedByAccount() async throws {
    let store = KeychainStore(service: "VaranTests.\(UUID().uuidString)")
    let firstAccount = "first"
    let secondAccount = "second"

    let missingSecret = try await store.secret(for: firstAccount)
    XCTAssertNil(missingSecret)
    try await store.save("initial-secret", for: firstAccount)
    try await store.save("other-secret", for: secondAccount)
    let firstSecret = try await store.secret(for: firstAccount)
    let secondSecret = try await store.secret(for: secondAccount)
    XCTAssertEqual(firstSecret, "initial-secret")
    XCTAssertEqual(secondSecret, "other-secret")

    try await store.save("updated-secret", for: firstAccount)
    let updatedSecret = try await store.secret(for: firstAccount)
    XCTAssertEqual(updatedSecret, "updated-secret")

    try await store.deleteSecret(for: firstAccount)
    try await store.deleteSecret(for: secondAccount)
    let deletedFirstSecret = try await store.secret(for: firstAccount)
    let deletedSecondSecret = try await store.secret(for: secondAccount)
    XCTAssertNil(deletedFirstSecret)
    XCTAssertNil(deletedSecondSecret)
  }
}