import Combine
import Foundation

enum LiveConnectionStatus: Equatable, Sendable {
  case offline
  case connecting
  case live
}

enum KomodoResourceKind: String, Decodable, Sendable {
  case system = "System"
  case server = "Server"
  case stack = "Stack"
  case deployment = "Deployment"
  case swarm = "Swarm"
  case other

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .other
  }
}

struct KomodoUpdateEvent: Decodable, Equatable, Sendable {
  struct Target: Decodable, Equatable, Sendable {
    let type: KomodoResourceKind
    let id: String
  }

  let id: String
  let operation: String
  let target: Target
  let status: String
  let success: Bool

  enum CodingKeys: String, CodingKey {
    case id, operation, target, status, success
  }
}

protocol LiveWebSocketConnection: Sendable {
  func send(_ text: String) async throws
  func receive() async throws -> Data
  func close() async
}

protocol LiveWebSocketTransport: Sendable {
  func connect(to url: URL) async throws -> any LiveWebSocketConnection
}

struct URLSessionLiveWebSocketTransport: LiveWebSocketTransport {
  func connect(to url: URL) async throws -> any LiveWebSocketConnection {
    URLSessionLiveWebSocketConnection(url: url)
  }
}

private actor URLSessionLiveWebSocketConnection: LiveWebSocketConnection {
  private let task: URLSessionWebSocketTask

  init(url: URL) {
    task = URLSession.shared.webSocketTask(with: url)
    task.resume()
  }

  func send(_ text: String) async throws {
    try await task.send(.string(text))
  }

  func receive() async throws -> Data {
    switch try await task.receive() {
    case .string(let text):
      return Data(text.utf8)
    case .data(let data):
      return data
    @unknown default:
      throw KomodoLiveUpdateError.unsupportedMessage
    }
  }

  func close() {
    task.cancel(with: .goingAway, reason: nil)
  }
}

enum KomodoLiveUpdateError: Error, Equatable {
  case invalidWebSocketURL
  case unsupportedMessage
  case connectionClosedBeforeLogin
}

@MainActor
final class KomodoLiveUpdateController: ObservableObject {
  @Published private(set) var status = LiveConnectionStatus.offline
  @Published private(set) var lastEventReceivedAt: Date?
  @Published private(set) var latestEvent: KomodoUpdateEvent?
  @Published private(set) var refreshGeneration = 0

  private let transport: any LiveWebSocketTransport
  private let reconnectDelays: [Duration]
  private let sleep: @Sendable (Duration) async throws -> Void
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()
  private var connectionTask: Task<Void, Never>?
  private var connection: (any LiveWebSocketConnection)?
  private var contextID: UUID?

  init(
    transport: any LiveWebSocketTransport = URLSessionLiveWebSocketTransport(),
    reconnectDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15)],
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.transport = transport
    self.reconnectDelays = reconnectDelays
    self.sleep = sleep
  }

  func start(address: ServerAddress, authentication: KomodoAuthentication) {
    stop()
    let contextID = UUID()
    self.contextID = contextID
    status = .connecting
    connectionTask = Task { [weak self] in
      await self?.run(address: address, authentication: authentication, contextID: contextID)
    }
  }

  func stop() {
    contextID = nil
    connectionTask?.cancel()
    connectionTask = nil
    let connection = self.connection
    self.connection = nil
    status = .offline
    if let connection {
      Task { await connection.close() }
    }
  }

  func reconnect(address: ServerAddress, authentication: KomodoAuthentication) {
    start(address: address, authentication: authentication)
  }

  private func run(
    address: ServerAddress,
    authentication: KomodoAuthentication,
    contextID: UUID
  ) async {
    guard let url = Self.webSocketURL(for: address) else {
      status = .offline
      return
    }

    var retryIndex = 0
    while !Task.isCancelled, self.contextID == contextID {
      status = .connecting
      do {
        let connection = try await transport.connect(to: url)
        guard !Task.isCancelled, self.contextID == contextID else {
          await connection.close()
          return
        }
        self.connection = connection
        try await connection.send(try loginMessage(for: authentication))
        try await receiveMessages(from: connection, contextID: contextID)
        if !Task.isCancelled {
          throw KomodoLiveUpdateError.connectionClosedBeforeLogin
        }
      } catch is CancellationError {
        break
      } catch {
        guard !Task.isCancelled, self.contextID == contextID else { break }
        if let connection = self.connection {
          await connection.close()
          self.connection = nil
        }
        if status == .live {
          retryIndex = 0
        }
        status = .offline
      }

      guard !Task.isCancelled, self.contextID == contextID else { break }
      let delay = reconnectDelays[min(retryIndex, max(0, reconnectDelays.count - 1))]
      retryIndex += 1
      do {
        try await sleep(delay)
      } catch {
        break
      }
    }

    if self.contextID == contextID {
      connection = nil
      status = .offline
    }
  }

  private func receiveMessages(
    from connection: any LiveWebSocketConnection,
    contextID: UUID
  ) async throws {
    while !Task.isCancelled, self.contextID == contextID {
      let data = try await connection.receive()
      if String(data: data, encoding: .utf8) == "LOGGED_IN" {
        status = .live
        lastEventReceivedAt = Date()
        refreshGeneration += 1
        continue
      }
      guard let event = try? decoder.decode(KomodoUpdateEvent.self, from: data) else {
        continue
      }
      latestEvent = event
      lastEventReceivedAt = Date()
    }
  }

  private func loginMessage(for authentication: KomodoAuthentication) throws -> String {
    let message: LoginMessage
    switch authentication {
    case .apiKey(let key, let secret):
      message = LoginMessage(type: "ApiKeys", params: ["key": key, "secret": secret])
    case .bearerToken(let token):
      message = LoginMessage(type: "Jwt", params: ["jwt": token])
    }
    let data = try encoder.encode(message)
    guard let text = String(data: data, encoding: .utf8) else {
      throw KomodoLiveUpdateError.unsupportedMessage
    }
    return text
  }

  private struct LoginMessage: Encodable {
    let type: String
    let params: [String: String]
  }

  private static func webSocketURL(for address: ServerAddress) -> URL? {
    guard var components = URLComponents(url: address.url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    components.scheme = components.scheme == "https" ? "wss" : "ws"
    components.path = "/ws/update"
    return components.url
  }
}

extension KomodoUpdateEvent {
  func affects(_ kind: KomodoResourceKind, id: String? = nil) -> Bool {
    guard status == "Complete" else { return false }
    if target.type == .system { return true }
    guard target.type == kind else { return false }
    return id == nil || target.id == id
  }
}

enum MetricsRefreshInterval: Int, CaseIterable, Identifiable, Sendable {
  case fiveSeconds = 5
  case fifteenSeconds = 15
  case thirtySeconds = 30
  case oneMinute = 60

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .fiveSeconds: String(localized: "metrics.interval.fiveSeconds")
    case .fifteenSeconds: String(localized: "metrics.interval.fifteenSeconds")
    case .thirtySeconds: String(localized: "metrics.interval.thirtySeconds")
    case .oneMinute: String(localized: "metrics.interval.oneMinute")
    }
  }
}
