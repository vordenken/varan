import Foundation
import XCTest
@testable import Varan

@MainActor
final class KomodoLiveUpdateTests: XCTestCase {
  func testAPIKeyLoginAndTargetedEventDecoding() async throws {
    let connection = MockLiveConnection()
    let transport = MockLiveTransport(connections: [connection])
    let controller = makeController(transport: transport)

    controller.start(
      address: try ServerAddress("https://komodo.example.com"),
      authentication: .apiKey(key: "key-id", secret: "secret-value")
    )

    try await waitUntil { await connection.sentMessages().count == 1 }
    let messages = await connection.sentMessages()
    let login = try XCTUnwrap(messages.first)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(login.utf8)) as? [String: Any])
    XCTAssertEqual(json["type"] as? String, "ApiKeys")
    XCTAssertEqual((json["params"] as? [String: String])?["key"], "key-id")
    XCTAssertEqual((json["params"] as? [String: String])?["secret"], "secret-value")
    let connectedURLs = await transport.connectedURLs()
    XCTAssertEqual(connectedURLs.first?.absoluteString, "wss://komodo.example.com/ws/update")

    await connection.enqueue("LOGGED_IN")
    try await waitUntil { controller.status == .live && controller.refreshGeneration == 1 }
    await connection.enqueue(#"{"id":"update-1","operation":"DeployStack","target":{"type":"Stack","id":"stack-1"},"status":"Complete","success":true}"#)
    try await waitUntil { controller.latestEvent?.id == "update-1" }

    XCTAssertTrue(controller.latestEvent?.affects(.stack, id: "stack-1") == true)
    XCTAssertFalse(controller.latestEvent?.affects(.server) == true)
    XCTAssertNotNil(controller.lastEventReceivedAt)
    controller.stop()
  }

  func testJWTLoginUsesExpectedEnvelope() async throws {
    let connection = MockLiveConnection()
    let controller = makeController(transport: MockLiveTransport(connections: [connection]))

    controller.start(
      address: try ServerAddress("http://localhost:9120"),
      authentication: .bearerToken("signed-token")
    )

    try await waitUntil { await connection.sentMessages().count == 1 }
    let messages = await connection.sentMessages()
    let login = try XCTUnwrap(messages.first)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(login.utf8)) as? [String: Any])
    XCTAssertEqual(json["type"] as? String, "Jwt")
    XCTAssertEqual((json["params"] as? [String: String])?["jwt"], "signed-token")
    controller.stop()
  }

  func testReconnectUsesNextConnectionAfterFailure() async throws {
    let first = MockLiveConnection()
    let second = MockLiveConnection()
    let transport = MockLiveTransport(connections: [first, second])
    let controller = makeController(transport: transport)

    controller.start(
      address: try ServerAddress("https://komodo.example.com"),
      authentication: .bearerToken("token")
    )
    try await waitUntil { await first.sentMessages().count == 1 }
    await first.failReceive()
    try await waitUntil { await transport.connectionCount() == 2 }
    await second.enqueue("LOGGED_IN")
    try await waitUntil { controller.status == .live }

    controller.stop()
  }

  func testStartingNewProfileClosesPreviousConnectionAndAvoidsDuplicates() async throws {
    let first = MockLiveConnection()
    let second = MockLiveConnection()
    let transport = MockLiveTransport(connections: [first, second])
    let controller = makeController(transport: transport)
    let address = try ServerAddress("https://komodo.example.com")

    controller.start(address: address, authentication: .bearerToken("first"))
    try await waitUntil { await first.sentMessages().count == 1 }
    controller.start(address: address, authentication: .bearerToken("second"))
    try await waitUntil {
      let firstClosed = await first.wasClosed()
      let secondMessageCount = await second.sentMessages().count
      return firstClosed && secondMessageCount == 1
    }

    let connectionCount = await transport.connectionCount()
    XCTAssertEqual(connectionCount, 2)
    controller.stop()
    try await waitUntil { await second.wasClosed() }
    XCTAssertEqual(controller.status, .offline)
  }

  private func makeController(transport: MockLiveTransport) -> KomodoLiveUpdateController {
    KomodoLiveUpdateController(
      transport: transport,
      reconnectDelays: [.zero],
      sleep: { _ in await Task.yield() }
    )
  }

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () async -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !(await condition()) {
      guard clock.now < deadline else {
        XCTFail("Condition was not met before timeout")
        return
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }
}

private enum MockLiveError: Error {
  case disconnected
}

private actor MockLiveConnection: LiveWebSocketConnection {
  private var sent: [String] = []
  private var queuedMessages: [Result<Data, Error>] = []
  private var waiter: CheckedContinuation<Data, Error>?
  private var closed = false

  func send(_ text: String) {
    sent.append(text)
  }

  func receive() async throws -> Data {
    if !queuedMessages.isEmpty {
      return try queuedMessages.removeFirst().get()
    }
    return try await withCheckedThrowingContinuation { continuation in
      waiter = continuation
    }
  }

  func close() {
    closed = true
    waiter?.resume(throwing: CancellationError())
    waiter = nil
  }

  func enqueue(_ text: String) {
    let data = Data(text.utf8)
    if let waiter {
      self.waiter = nil
      waiter.resume(returning: data)
    } else {
      queuedMessages.append(.success(data))
    }
  }

  func failReceive() {
    if let waiter {
      self.waiter = nil
      waiter.resume(throwing: MockLiveError.disconnected)
    } else {
      queuedMessages.append(.failure(MockLiveError.disconnected))
    }
  }

  func sentMessages() -> [String] { sent }
  func wasClosed() -> Bool { closed }
}

private actor MockLiveTransport: LiveWebSocketTransport {
  private var connections: [MockLiveConnection]
  private var urls: [URL] = []

  init(connections: [MockLiveConnection]) {
    self.connections = connections
  }

  func connect(to url: URL) throws -> any LiveWebSocketConnection {
    urls.append(url)
    guard !connections.isEmpty else { throw MockLiveError.disconnected }
    return connections.removeFirst()
  }

  func connectionCount() -> Int { urls.count }
  func connectedURLs() -> [URL] { urls }
}
