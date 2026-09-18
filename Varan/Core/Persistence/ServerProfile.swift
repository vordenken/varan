import Foundation
import SwiftData

enum ProfileAuthenticationKind: String, Codable, Sendable {
  case apiKey
  case bearerToken
}

@Model
final class ServerProfile {
  @Attribute(.unique) var id: UUID
  var name: String
  var baseURL: String
  var authenticationKindRawValue: String
  var credentialAccount: String

  var authenticationKind: ProfileAuthenticationKind {
    get { ProfileAuthenticationKind(rawValue: authenticationKindRawValue) ?? .apiKey }
    set { authenticationKindRawValue = newValue.rawValue }
  }

  var address: ServerAddress {
    get throws { try ServerAddress(baseURL) }
  }

  init(
    id: UUID = UUID(),
    name: String,
    address: ServerAddress,
    authenticationKind: ProfileAuthenticationKind
  ) {
    self.id = id
    self.name = name
    baseURL = address.url.absoluteString
    authenticationKindRawValue = authenticationKind.rawValue
    credentialAccount = id.uuidString
  }

  func update(
    name: String,
    address: ServerAddress,
    authenticationKind: ProfileAuthenticationKind
  ) {
    self.name = name
    baseURL = address.url.absoluteString
    self.authenticationKind = authenticationKind
  }
}