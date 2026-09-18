import Foundation
import XCTest
@testable import Varan

final class KomodoAPIClientTests: XCTestCase {
  override func tearDown() {
    MockURLProtocol.handler = nil
    super.tearDown()
  }

  func testConnectionUsesAPIKeyHeadersAndListStacksEnvelope() async throws {
    let requestExpectation = expectation(description: "Request received")
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.absoluteString, "https://komodo.example.com/read")
      XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "key-id")
      XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-secret"), "secret-value")
      XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))

      let body = try Self.bodyData(from: request)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(json["type"] as? String, "ListStacks")
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      let query = try XCTUnwrap(params["query"] as? [String: Any])
      XCTAssertTrue(query.isEmpty)
      XCTAssertEqual(params["page"] as? Int, 0)
      XCTAssertEqual(params["limit"] as? Int, 1)
      requestExpectation.fulfill()
      return Self.response(for: request, statusCode: 200, body: "[]")
    }

    let client = try makeClient(authentication: .apiKey(key: "key-id", secret: "secret-value"))
    try await client.testConnection()

    await fulfillment(of: [requestExpectation], timeout: 1)
  }

  func testConnectionUsesAuthorizationHeaderForToken() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "signed-token")
      XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
      return Self.response(for: request, statusCode: 200, body: "[]")
    }

    let client = try makeClient(authentication: .bearerToken("signed-token"))

    try await client.testConnection()
  }

  func testListStacksDecodesStableResourceFields() async throws {
    MockURLProtocol.handler = { request in
      let body = try Self.bodyData(from: request)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["page"] as? Int, 2)
      XCTAssertEqual(params["limit"] as? Int, 25)
      return Self.response(
        for: request,
        statusCode: 200,
        body: """
          [{
            "id": "stack-1",
            "type": "Stack",
            "name": "Home Services",
            "template": false,
            "tags": ["production"],
            "info": {
              "server_name": "docker-01",
              "swarm_name": "",
              "state": "running",
              "status": "running(3)",
              "services": [{
                "service": "web",
                "image": "example/web:latest",
                "latest_image": null,
                "update_available": true
              }],
              "future_field": true
            },
            "future_field": "ignored"
          }]
          """
      )
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let stacks = try await client.listStacks(page: 2, limit: 25)

    XCTAssertEqual(stacks.count, 1)
    XCTAssertEqual(stacks[0].id, "stack-1")
    XCTAssertEqual(stacks[0].name, "Home Services")
    XCTAssertEqual(stacks[0].info.serverName, "docker-01")
    XCTAssertEqual(stacks[0].info.state, "running")
    XCTAssertEqual(stacks[0].info.services.first?.updateAvailable, true)
  }

  func testListStacksDefaultsOptionalInfoFields() async throws {
    MockURLProtocol.handler = { request in
      Self.response(
        for: request,
        statusCode: 200,
        body: """
          [{
            "id": "stack-1",
            "type": "Stack",
            "name": "Minimal Stack",
            "template": false,
            "tags": [],
            "info": {}
          }]
          """
      )
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let stacks = try await client.listStacks()
    let stack = try XCTUnwrap(stacks.first)

    XCTAssertEqual(stack.info.serverName, "")
    XCTAssertEqual(stack.info.swarmName, "")
    XCTAssertEqual(stack.info.state, "unknown")
    XCTAssertNil(stack.info.status)
    XCTAssertTrue(stack.info.services.isEmpty)
  }

  func testGetStackUsesReadEnvelopeAndDecodesDetails() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.absoluteString, "https://komodo.example.com/read")
      let body = try Self.bodyData(from: request)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(json["type"] as? String, "GetStack")
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["stack"] as? String, "home-services")
      return Self.response(
        for: request,
        statusCode: 200,
        body: """
          {
            "_id": {"$oid": "67d000000000000000000001"},
            "name": "Home Services",
            "description": "Services at home",
            "template": false,
            "tags": ["production"],
            "info": {
              "missing_files": [],
              "deployed_project_name": "home",
              "deployed_hash": "abc1234",
              "latest_hash": "def5678",
              "latest_services": [{
                "service_name": "web",
                "container_name": "home-web",
                "image": "example/web:latest",
                "future_field": true
              }]
            },
            "config": {
              "server_id": "server-1",
              "swarm_id": "",
              "project_name": "home",
              "file_paths": ["compose.yaml"],
              "linked_repo": "repo-1",
              "repo": "owner/home",
              "branch": "main",
              "future_field": true
            },
            "future_field": true
          }
          """
      )
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let stack = try await client.getStack(idOrName: "home-services")

    XCTAssertEqual(stack.id, "67d000000000000000000001")
    XCTAssertEqual(stack.name, "Home Services")
    XCTAssertEqual(stack.config.serverID, "server-1")
    XCTAssertEqual(stack.info.latestServices.first?.serviceName, "web")
  }

  func testListStackServicesDecodesContainerDetails() async throws {
    MockURLProtocol.handler = { request in
      let body = try Self.bodyData(from: request)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(json["type"] as? String, "ListStackServices")
      return Self.response(
        for: request,
        statusCode: 200,
        body: """
          [{
            "stack_id": "stack-1",
            "stack_name": "Home Services",
            "service": "web",
            "image": "example/web:latest",
            "container": {
              "server_id": "server-1",
              "name": "home-web-1",
              "id": "container-1",
              "image": "example/web:latest",
              "image_id": "sha256:123",
              "state": "running",
              "status": "Up 3 hours",
              "networks": ["home_default"]
            },
            "swarm_service": null,
            "state": "Running"
          }]
          """
      )
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let services = try await client.listStackServices(stack: "stack-1")

    XCTAssertEqual(services.first?.service, "web")
    XCTAssertEqual(services.first?.container?.name, "home-web-1")
    XCTAssertEqual(services.first?.container?.state, "running")
  }

  func testStartStackUsesExecuteEndpointAndServiceFilter() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.absoluteString, "https://komodo.example.com/execute")
      let body = try Self.bodyData(from: request)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(json["type"] as? String, "StartStack")
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["stack"] as? String, "stack-1")
      XCTAssertEqual(params["services"] as? [String], ["web"])
      return Self.response(
        for: request,
        statusCode: 200,
        body: """
          {"_id":{"$oid":"67d000000000000000000002"},"success":true,"status":"Complete"}
          """
      )
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let update = try await client.startStack(idOrName: "stack-1", services: ["web"])

    XCTAssertTrue(update.success)
    XCTAssertEqual(update.status, "Complete")
  }

  func testStopStackSendsOptionalTimeoutAndServices() async throws {
    MockURLProtocol.handler = { request in
      let body = try Self.bodyData(from: request)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(json["type"] as? String, "StopStack")
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["stack"] as? String, "stack-1")
      XCTAssertEqual(params["services"] as? [String], ["web"])
      XCTAssertNil(params["stop_time"])
      return Self.response(
        for: request,
        statusCode: 200,
        body: """
          {"_id":{"$oid":"67d000000000000000000003"},"success":false,"status":"InProgress"}
          """
      )
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let update = try await client.stopStack(idOrName: "stack-1", services: ["web"])

    XCTAssertEqual(update.status, "InProgress")
  }

  func testContainerActionsUseExecuteContracts() async throws {
    var receivedTypes: [String] = []
    MockURLProtocol.handler = { request in
      let body = try Self.bodyData(from: request)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      let type = try XCTUnwrap(json["type"] as? String)
      receivedTypes.append(type)
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["server"] as? String, "server-1")
      XCTAssertEqual(params["container"] as? String, "home-web-1")
      if type == "StopContainer" {
        XCTAssertNil(params["signal"])
        XCTAssertNil(params["time"])
      }
      return Self.response(
        for: request,
        statusCode: 200,
        body: """
          {"_id":{"$oid":"67d000000000000000000004"},"success":true,"status":"Complete"}
          """
      )
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    _ = try await client.startContainer(server: "server-1", container: "home-web-1")
    _ = try await client.stopContainer(server: "server-1", container: "home-web-1")

    XCTAssertEqual(receivedTypes, ["StartContainer", "StopContainer"])
  }

  func testGetContainerLogUsesReadEndpointAndDecodesOutput() async throws {
    MockURLProtocol.handler = { request in
      let body = try Self.bodyData(from: request)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(json["type"] as? String, "GetContainerLog")
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["server"] as? String, "server-1")
      XCTAssertEqual(params["container"] as? String, "home-web-1")
      XCTAssertEqual(params["tail"] as? Int, 200)
      XCTAssertEqual(params["timestamps"] as? Bool, true)
      return Self.response(
        for: request,
        statusCode: 200,
        body: """
          {"stage":"log","command":"docker logs","stdout":"ready","stderr":"","success":true,"start_ts":1,"end_ts":2}
          """
      )
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let log = try await client.getContainerLog(server: "server-1", container: "home-web-1")

    XCTAssertEqual(log.combinedOutput, "ready")
  }

  func testGetStackLogSendsServiceFilter() async throws {
    MockURLProtocol.handler = { request in
      let body = try Self.bodyData(from: request)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(json["type"] as? String, "GetStackLog")
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["stack"] as? String, "stack-1")
      XCTAssertEqual(params["services"] as? [String], ["web"])
      return Self.response(
        for: request,
        statusCode: 200,
        body: """
          {"stage":"log","command":"docker compose logs","stdout":"ready","stderr":"warning","success":true,"start_ts":1,"end_ts":2}
          """
      )
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let log = try await client.getStackLog(stack: "stack-1", services: ["web"])

    XCTAssertEqual(log.combinedOutput, "ready\n\nFehlerausgabe:\nwarning")
  }

  func testLogOutputRemovesANSIControlSequences() throws {
    let data = Data(
      #"{"stage":"log","command":"docker logs","stdout":"\u001b[32mready\u001b[0m","stderr":"","success":true,"start_ts":1,"end_ts":2}"#.utf8
    )

    let log = try JSONDecoder().decode(KomodoLog.self, from: data)

    XCTAssertEqual(log.cleanedStandardOutput, "ready")
    XCTAssertEqual(log.combinedOutput, "ready")
  }

  func testLogSearchCountsRepeatedMatchesAndFiltersLines() {
    let result = LogSearch.find(
      "ready",
      in: "READY on first line\nignored\nready and ready again"
    )

    XCTAssertEqual(result.output, "READY on first line\nready and ready again")
    XCTAssertEqual(result.query, "ready")
    XCTAssertEqual(result.matchCount, 3)
    XCTAssertTrue(result.isActive)
  }

  func testLogSearchDistinguishesEmptyQueryAndNoMatches() {
    let inactiveResult = LogSearch.find("   ", in: "complete output")
    let missingResult = LogSearch.find("warning", in: "complete output")

    XCTAssertEqual(inactiveResult.output, "complete output")
    XCTAssertFalse(inactiveResult.isActive)
    XCTAssertEqual(missingResult.output, "")
    XCTAssertEqual(missingResult.matchCount, 0)
    XCTAssertTrue(missingResult.isActive)
  }

  func testLogSearchPreparesMatchingLinesForLazyRendering() {
    let presentation = LogSearch.prepare(
      "ready",
      in: "ready first\nignored\nsecond READY"
    )

    XCTAssertEqual(presentation.result.matchCount, 2)
    XCTAssertEqual(presentation.highlightedLines.count, 2)
    XCTAssertTrue(presentation.highlightedOutput.characters.isEmpty)
  }

  func testConnectionMapsInvalidBearerTokenWithoutResponseBody() async throws {
    MockURLProtocol.handler = { request in
      Self.response(for: request, statusCode: 401, body: "sensitive server detail")
    }
    let client = try makeClient(authentication: .bearerToken("expired-token"))

    do {
      try await client.testConnection()
      XCTFail("Expected an invalid-token error")
    } catch {
      XCTAssertEqual(error as? KomodoAPIError, .invalidToken)
      XCTAssertEqual(error.localizedDescription, "Der Token ist abgelaufen oder ungültig.")
    }
  }

  func testConnectionMapsRejectedAPIKeyToUnauthorized() async throws {
    MockURLProtocol.handler = { request in
      Self.response(for: request, statusCode: 403, body: "")
    }
    let client = try makeClient(authentication: .apiKey(key: "invalid", secret: "invalid"))

    do {
      try await client.testConnection()
      XCTFail("Expected an unauthorized error")
    } catch {
      XCTAssertEqual(error as? KomodoAPIError, .unauthorized)
      XCTAssertEqual(error.localizedDescription, "Die Zugangsdaten wurden abgelehnt.")
    }
  }

  func testConnectionMapsServerErrorWithoutResponseBody() async throws {
    MockURLProtocol.handler = { request in
      Self.response(for: request, statusCode: 503, body: "internal detail")
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    do {
      try await client.testConnection()
      XCTFail("Expected a server error")
    } catch {
      XCTAssertEqual(error as? KomodoAPIError, .server(statusCode: 503, reason: nil))
    }
  }

  func testServerErrorUsesShortNonSensitiveReason() async throws {
    MockURLProtocol.handler = { request in
      Self.response(
        for: request,
        statusCode: 409,
        body: #"{"error":"Stack-Aktion läuft bereits","trace":["internal detail"]}"#
      )
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    do {
      try await client.testConnection()
      XCTFail("Expected a server error")
    } catch {
      XCTAssertEqual(
        error as? KomodoAPIError,
        .server(statusCode: 409, reason: "Stack-Aktion läuft bereits")
      )
      XCTAssertFalse(error.localizedDescription.contains("internal detail"))
    }
  }

  func testServerErrorSuppressesPotentialSecret() async throws {
    MockURLProtocol.handler = { request in
      Self.response(
        for: request,
        statusCode: 500,
        body: #"{"error":"API secret abc was rejected"}"#
      )
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    do {
      try await client.testConnection()
      XCTFail("Expected a server error")
    } catch {
      XCTAssertEqual(error as? KomodoAPIError, .server(statusCode: 500, reason: nil))
      XCTAssertFalse(error.localizedDescription.contains("abc"))
    }
  }

  func testConnectionRejectsInvalidJSON() async throws {
    MockURLProtocol.handler = { request in
      Self.response(for: request, statusCode: 200, body: "not-json")
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    do {
      try await client.testConnection()
      XCTFail("Expected an invalid-payload error")
    } catch {
      XCTAssertEqual(error as? KomodoAPIError, .invalidPayload)
    }
  }

  func testConnectionMapsOfflineError() async throws {
    MockURLProtocol.handler = { _ in
      throw URLError(.notConnectedToInternet)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    do {
      try await client.testConnection()
      XCTFail("Expected a network-unavailable error")
    } catch {
      XCTAssertEqual(error as? KomodoAPIError, .networkUnavailable)
      XCTAssertEqual(error.localizedDescription, "Es besteht derzeit keine Netzwerkverbindung.")
    }
  }

  func testConnectionMapsTimeoutError() async throws {
    MockURLProtocol.handler = { _ in
      throw URLError(.timedOut)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    do {
      try await client.testConnection()
      XCTFail("Expected a timeout error")
    } catch {
      XCTAssertEqual(error as? KomodoAPIError, .timedOut)
      XCTAssertEqual(
        error.localizedDescription,
        "Der Komodo-Server hat nicht rechtzeitig geantwortet."
      )
    }
  }

  func testConnectionPreservesCancellation() async throws {
    MockURLProtocol.handler = { _ in
      throw URLError(.cancelled)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    do {
      try await client.testConnection()
      XCTFail("Expected cancellation")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }

  private func makeClient(authentication: KomodoAuthentication) throws -> KomodoAPIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return KomodoAPIClient(
      address: try ServerAddress("https://komodo.example.com"),
      authentication: authentication,
      session: session
    )
  }

  private static func response(
    for request: URLRequest,
    statusCode: Int,
    body: String
  ) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: ["content-type": "application/json"]
    )!
    return (response, Data(body.utf8))
  }

  private static func bodyData(from request: URLRequest) throws -> Data {
    if let body = request.httpBody {
      return body
    }

    let stream = try XCTUnwrap(request.httpBodyStream)
    stream.open()
    defer { stream.close() }

    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count >= 0 else {
        throw try XCTUnwrap(stream.streamError)
      }
      if count == 0 {
        break
      }
      body.append(buffer, count: count)
    }
    return body
  }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: KomodoAPIError.invalidResponse)
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}