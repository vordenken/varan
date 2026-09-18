import Foundation

struct StoredCredentials: Codable, Equatable, Sendable {
  let authenticationKind: ProfileAuthenticationKind
  let apiKey: String?
  let secret: String

  static func apiKey(_ key: String, secret: String) -> Self {
    Self(authenticationKind: .apiKey, apiKey: key, secret: secret)
  }

  static func bearerToken(_ token: String) -> Self {
    Self(authenticationKind: .bearerToken, apiKey: nil, secret: token)
  }

  var authentication: KomodoAuthentication {
    switch authenticationKind {
    case .apiKey:
      .apiKey(key: apiKey ?? "", secret: secret)
    case .bearerToken:
      .bearerToken(secret)
    }
  }
}

extension KeychainStore {
  func save(_ credentials: StoredCredentials, for account: String) throws {
    let data = try JSONEncoder().encode(credentials)
    guard let value = String(data: data, encoding: .utf8) else {
      throw KeychainStoreError.invalidCredentialData
    }
    try save(value, for: account)
  }

  func credentials(for account: String) throws -> StoredCredentials? {
    guard let value = try secret(for: account), let data = value.data(using: .utf8) else {
      return nil
    }
    do {
      return try JSONDecoder().decode(StoredCredentials.self, from: data)
    } catch {
      throw KeychainStoreError.invalidCredentialData
    }
  }
}