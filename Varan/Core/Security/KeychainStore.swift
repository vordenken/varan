import Foundation
import Security

enum KeychainStoreError: LocalizedError, Equatable {
  case unexpectedStatus(OSStatus)
  case invalidCredentialData

  var errorDescription: String? {
    switch self {
    case .unexpectedStatus(let status):
      String(format: String(localized: "error.keychain.unexpectedStatus"), status)
    case .invalidCredentialData:
      String(localized: "error.keychain.invalidCredentials")
    }
  }
}

actor KeychainStore {
  static let shared = KeychainStore()

  private let service: String

  init(service: String = "de.example.Varan.credentials") {
    self.service = service
  }

  func save(_ secret: String, for account: String) throws {
    let secretData = Data(secret.utf8)
    let query = baseQuery(account: account)
    let attributes = [kSecValueData as String: secretData]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

    if updateStatus == errSecItemNotFound {
      var newItem = query
      newItem[kSecValueData as String] = secretData
      let addStatus = SecItemAdd(newItem as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw KeychainStoreError.unexpectedStatus(addStatus)
      }
    } else if updateStatus != errSecSuccess {
      throw KeychainStoreError.unexpectedStatus(updateStatus)
    }
  }

  func secret(for account: String) throws -> String? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess,
          let data = result as? Data,
          let secret = String(data: data, encoding: .utf8) else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
    return secret
  }

  func deleteSecret(for account: String) throws {
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
  }

  private func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
  }
}