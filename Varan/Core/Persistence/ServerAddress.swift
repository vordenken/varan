import Foundation

enum ServerAddressError: LocalizedError, Equatable {
  case empty
  case invalid
  case insecureRemoteHost

  var errorDescription: String? {
    switch self {
    case .empty:
      String(localized: "error.serverAddress.empty")
    case .invalid:
      String(localized: "error.serverAddress.invalid")
    case .insecureRemoteHost:
      String(localized: "error.serverAddress.insecureRemote")
    }
  }
}

struct ServerAddress: Codable, Equatable, Sendable {
  let url: URL

  init(_ input: String) throws {
    let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedInput.isEmpty else {
      throw ServerAddressError.empty
    }

    let value = trimmedInput.contains("://") ? trimmedInput : "https://\(trimmedInput)"
    guard var components = URLComponents(string: value),
          let scheme = components.scheme?.lowercased(),
          let host = components.host?.lowercased(),
          !host.isEmpty,
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil else {
      throw ServerAddressError.invalid
    }

    guard scheme == "https" || (scheme == "http" && Self.isLocal(host)) else {
      throw ServerAddressError.insecureRemoteHost
    }

    components.scheme = scheme
    components.host = host
    components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard components.path.isEmpty, let normalizedURL = components.url else {
      throw ServerAddressError.invalid
    }

    url = normalizedURL
  }

  private static func isLocal(_ host: String) -> Bool {
    host == "localhost"
      || host == "::1"
      || host.hasSuffix(".local")
      || host.hasPrefix("127.")
      || host.hasPrefix("10.")
      || host.hasPrefix("192.168.")
      || isPrivate172Address(host)
  }

  private static func isPrivate172Address(_ host: String) -> Bool {
    let parts = host.split(separator: ".")
    guard parts.count == 4, parts[0] == "172", let secondOctet = Int(parts[1]) else {
      return false
    }
    return (16...31).contains(secondOctet)
  }
}