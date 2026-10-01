import Foundation
import XCTest
@testable import Varan

final class KomodoAPIClientTests: XCTestCase {
  override func tearDown() {
    MockURLProtocol.handler = nil
    super.tearDown()
  }

  func testServerListStatsDistinguishMissingMetricsFromReportedZero() throws {
    let data = Data("""
      [
        {"id":"empty","name":"Empty","template":false,"tags":[],"info":{"state":"Ok","stats":{}}},
        {"id":"zero","name":"Zero","template":false,"tags":[],"info":{"state":"Ok","public_ip":"203.0.113.10","stats":{"cpu_perc":0,"mem_used_gb":0,"mem_total_gb":16}}}
      ]
      """.utf8)

    let servers = try JSONDecoder().decode([ServerListItem].self, from: data)

    XCTAssertEqual(servers[0].info.stats?.availableFields, [])
    XCTAssertEqual(
      servers[1].info.stats?.availableFields,
      ["cpu_perc", "mem_used_gb", "mem_total_gb"]
    )
    XCTAssertEqual(servers[1].info.stats?.cpuPercent, 0)
    XCTAssertEqual(servers[1].info.stats?.memoryUsedGB, 0)
    XCTAssertEqual(servers[1].info.publicIP, "203.0.113.10")
  }

  func testListAllServersLoadsPastFirstPage() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/read")
      let body = try Self.bodyData(from: request)
      let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(envelope["type"] as? String, "ListServers")
      let parameters = try XCTUnwrap(envelope["params"] as? [String: Any])
      XCTAssertEqual(parameters["limit"] as? Int, 50)
      let page = try XCTUnwrap(parameters["page"] as? Int)
      XCTAssertTrue(page == 0 || page == 1)
      let indices = page == 0 ? 0..<50 : 50..<51
      let servers = indices.map { index in
        [
          "id": "server-\(index)",
          "name": "Server \(index)",
          "template": false,
          "tags": [],
          "info": ["state": "Ok"],
        ] as [String: Any]
      }
      let responseData = try JSONSerialization.data(withJSONObject: servers)
      return Self.response(
        for: request,
        statusCode: 200,
        body: try XCTUnwrap(String(data: responseData, encoding: .utf8))
      )
    }

    let client = try makeClient(authentication: .bearerToken("signed-token"))
    let servers = try await client.listAllServers()

    XCTAssertEqual(servers.count, 51)
    XCTAssertEqual(servers.last?.id, "server-50")
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

  func testStackLifecycleActionsUseExecuteContracts() async throws {
    var receivedTypes: [String] = []
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/execute")
      let json = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
      )
      let type = try XCTUnwrap(json["type"] as? String)
      receivedTypes.append(type)
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["stack"] as? String, "stack-1")
      XCTAssertEqual(params["services"] as? [String], [])
      if type == "DeployStack" {
        XCTAssertNil(params["stop_time"])
      }
      if type == "DestroyStack" {
        XCTAssertEqual(params["remove_orphans"] as? Bool, true)
        XCTAssertNil(params["stop_time"])
      }
      return Self.response(for: request, statusCode: 200, body: """
        {"_id":"update-1","success":true,"status":"Complete"}
        """)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    _ = try await client.deployStack(idOrName: "stack-1")
    _ = try await client.pullStackImages(idOrName: "stack-1")
    _ = try await client.restartStack(idOrName: "stack-1")
    _ = try await client.pauseStack(idOrName: "stack-1")
    _ = try await client.unpauseStack(idOrName: "stack-1")
    _ = try await client.destroyStack(idOrName: "stack-1", removeOrphans: true)

    XCTAssertEqual(
      receivedTypes,
      ["DeployStack", "PullStack", "RestartStack", "PauseStack", "UnpauseStack", "DestroyStack"]
    )
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
    _ = try await client.restartContainer(server: "server-1", container: "home-web-1")
    _ = try await client.pauseContainer(server: "server-1", container: "home-web-1")
    _ = try await client.unpauseContainer(server: "server-1", container: "home-web-1")
    _ = try await client.stopContainer(server: "server-1", container: "home-web-1")
    _ = try await client.destroyContainer(server: "server-1", container: "home-web-1")

    XCTAssertEqual(
      receivedTypes,
      [
        "StartContainer", "RestartContainer", "PauseContainer", "UnpauseContainer",
        "StopContainer", "DestroyContainer"
      ]
    )
  }

  func testResourceDeletionUsesWriteContracts() async throws {
    var receivedTypes: [String] = []
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/write")
      let json = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
      )
      let type = try XCTUnwrap(json["type"] as? String)
      receivedTypes.append(type)
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["id"] as? String, type == "DeleteStack" ? "stack-1" : "server-1")
      if type == "DeleteStack" {
        return Self.response(for: request, statusCode: 200, body: """
          {"_id":"stack-1","name":"Home","info":{},"config":{}}
          """)
      }
      return Self.response(for: request, statusCode: 200, body: """
        {"_id":"server-1","name":"Docker","info":{},"config":{}}
        """)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    _ = try await client.deleteStack(idOrName: "stack-1")
    _ = try await client.deleteServer(idOrName: "server-1")

    XCTAssertEqual(receivedTypes, ["DeleteStack", "DeleteServer"])
  }

  func testServerWideActionsUseExecuteContracts() async throws {
    var receivedTypes: [String] = []
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/execute")
      let body = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
      )
      receivedTypes.append(try XCTUnwrap(body["type"] as? String))
      let params = try XCTUnwrap(body["params"] as? [String: Any])
      XCTAssertEqual(params["server"] as? String, "server-1")
      XCTAssertEqual(params.count, 1)
      return Self.response(for: request, statusCode: 200, body: """
        {"_id":"update-1","success":true,"status":"Complete"}
        """)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    _ = try await client.startAllContainers(server: "server-1")
    _ = try await client.restartAllContainers(server: "server-1")
    _ = try await client.pauseAllContainers(server: "server-1")
    _ = try await client.unpauseAllContainers(server: "server-1")
    _ = try await client.stopAllContainers(server: "server-1")
    _ = try await client.pruneBuildx(server: "server-1")
    _ = try await client.pruneSystem(server: "server-1")

    XCTAssertEqual(receivedTypes, [
      "StartAllContainers", "RestartAllContainers", "PauseAllContainers",
      "UnpauseAllContainers", "StopAllContainers", "PruneBuildx", "PruneSystem"
    ])
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

  func testEmptyLogKeepsCombinedOutputEmptyForEmptyStatePresentation() throws {
    let data = Data(
      #"{"stage":"log","command":"docker logs","stdout":"","stderr":"","success":true,"start_ts":1,"end_ts":2}"#.utf8
    )

    let log = try JSONDecoder().decode(KomodoLog.self, from: data)

    XCTAssertTrue(log.combinedOutput.isEmpty)
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
      Self.response(for: request, statusCode: 401, body: "")
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

  func testConnectionMapsValidationResponsesToTypedErrors() async throws {
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    for statusCode in [400, 422] {
      MockURLProtocol.handler = { request in
        Self.response(
          for: request,
          statusCode: statusCode,
          body: #"{"error":"Invalid server address"}"#
        )
      }

      do {
        try await client.testConnection()
        XCTFail("Expected a validation error for HTTP \(statusCode)")
      } catch {
        XCTAssertEqual(error as? KomodoAPIError, .validation(reason: "Invalid server address"))
      }
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

  func testConnectionMapsDroppedConnectionToNetworkUnavailable() async throws {
    MockURLProtocol.handler = { _ in
      throw URLError(.networkConnectionLost)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    do {
      try await client.testConnection()
      XCTFail("Expected a network-unavailable error")
    } catch {
      XCTAssertEqual(error as? KomodoAPIError, .networkUnavailable)
    }
  }

  func testConnectionAcceptsDelayedValidResponse() async throws {
    let responseExpectation = expectation(description: "Delayed response delivered")
    MockURLProtocol.handler = { request in
      Thread.sleep(forTimeInterval: 0.05)
      responseExpectation.fulfill()
      return Self.response(for: request, statusCode: 200, body: "[]")
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    try await client.testConnection()

    await fulfillment(of: [responseExpectation], timeout: 1)
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

  func testListServersAndSystemStatsUseReadContracts() async throws {
    var requestCount = 0
    MockURLProtocol.handler = { request in
      requestCount += 1
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any])
      if requestCount == 1 {
        XCTAssertEqual(json["type"] as? String, "ListServers")
        return Self.response(for: request, statusCode: 200, body: """
          [{"id":"server-1","name":"Docker","template":false,"tags":["home"],
            "info":{"state":"Ok","version":"1.19.0","region":"office","address":"https://agent.local",
              "stats":{"cpu_perc":12.5,"mem_used_gb":2.0,"mem_total_gb":8.0}}}]
          """)
      }
      XCTAssertEqual(json["type"] as? String, "GetSystemStats")
      XCTAssertEqual((json["params"] as? [String: Any])?["server"] as? String, "server-1")
      return Self.response(for: request, statusCode: 200, body: """
        {"cpu_perc":12.5,"load_average":{"one":0.1,"five":0.2,"fifteen":0.3},
         "mem_used_gb":2,"mem_total_gb":8,"swap_used_gb":0,"swap_total_gb":1,
         "disks":[],"network_ingress_bytes":100,"network_egress_bytes":200,"refresh_ts":123}
        """)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let servers = try await client.listServers()
    let stats = try await client.getSystemStats(server: "server-1")

    XCTAssertEqual(servers.first?.info.stats?.memoryTotalGB, 8)
    XCTAssertEqual(servers.first?.info.state, .ok)
    XCTAssertEqual(servers.first?.info.version, "1.19.0")
    XCTAssertEqual(stats.loadAverage.five, 0.2)
    XCTAssertEqual(stats.networkEgressBytes, 200)
    XCTAssertTrue(stats.availableFields.contains("cpu_perc"))
    XCTAssertTrue(stats.availableFields.contains("mem_total_gb"))
    XCTAssertFalse(stats.availableFields.contains("future_metric"))
  }

  func testSystemStatsDistinguishesMissingAndNullFieldsFromZeroValues() throws {
    let stats = try JSONDecoder().decode(
      SystemStats.self,
      from: Data(#"{"cpu_perc":0,"mem_used_gb":null,"refresh_ts":123}"#.utf8)
    )

    XCTAssertEqual(stats.cpuPercent, 0)
    XCTAssertTrue(stats.availableFields.contains("cpu_perc"))
    XCTAssertFalse(stats.availableFields.contains("mem_used_gb"))
    XCTAssertFalse(stats.availableFields.contains("mem_total_gb"))
    XCTAssertTrue(stats.availableFields.contains("refresh_ts"))
  }

  func testHistoricalStatsDistinguishMissingAndNullMetricsFromZero() throws {
    let records = try JSONDecoder().decode(
      [SystemStatsRecord].self,
      from: Data(#"[{"ts":100,"cpu_perc":0,"mem_used_gb":null},{"ts":200,"mem_total_gb":8}]"#.utf8)
    )

    XCTAssertTrue(records[0].availableFields.contains("cpu_perc"))
    XCTAssertFalse(records[0].availableFields.contains("mem_used_gb"))
    XCTAssertFalse(records[0].availableFields.contains("mem_total_gb"))
    XCTAssertFalse(records[1].availableFields.contains("cpu_perc"))
    XCTAssertTrue(records[1].availableFields.contains("mem_total_gb"))
    XCTAssertEqual(records[0].cpuPercent, 0)
  }

  func testMetricFreshnessHandlesSecondAndMillisecondTimestamps() {
    let now = Date(timeIntervalSince1970: 1_000)

    XCTAssertFalse(MetricFreshness.isStale(timestamp: 0, now: now, after: 100))
    XCTAssertFalse(MetricFreshness.isStale(timestamp: 900, now: now, after: 100))
    XCTAssertTrue(MetricFreshness.isStale(timestamp: 899, now: now, after: 100))
    let millisecondTimestamp: Int64 = 900_000_000_000
    let millisecondDate = Date(timeIntervalSince1970: 900_000_000)
    XCTAssertFalse(MetricFreshness.isStale(
      timestamp: millisecondTimestamp,
      now: millisecondDate.addingTimeInterval(100),
      after: 100
    ))
    XCTAssertEqual(
      MetricFreshness.measurementDate(for: millisecondTimestamp),
      millisecondDate
    )
  }

  func testServerDetailHistoryAndContainerListUseReadContracts() async throws {
    var requestCount = 0
    MockURLProtocol.handler = { request in
      requestCount += 1
      let json = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
      )
      let params = try XCTUnwrap(json["params"] as? [String: Any])

      switch requestCount {
      case 1:
        XCTAssertEqual(json["type"] as? String, "GetServer")
        XCTAssertEqual(params["server"] as? String, "server-1")
        return Self.response(for: request, statusCode: 200, body: """
          {"_id":"server-1","name":"Docker","description":"Primary","tags":["home"],
           "info":{"attempted_public_key":"old-key","public_key":"current-key"},
           "config":{"address":"https://agent.local","external_address":"agent.example.com","region":"office","enabled":true}}
          """)
      case 2:
        XCTAssertEqual(json["type"] as? String, "GetHistoricalServerStats")
        XCTAssertEqual(params["server"] as? String, "server-1")
        XCTAssertEqual(params["granularity"] as? String, "1-hr")
        XCTAssertEqual(params["page"] as? Int, 2)
        return Self.response(for: request, statusCode: 200, body: """
          {"stats":[{"ts":123,"cpu_perc":20,"mem_used_gb":2,"mem_total_gb":8}],
           "next_page":3}
          """)
      default:
        XCTAssertEqual(json["type"] as? String, "ListContainers")
        XCTAssertEqual(params["server"] as? String, "server-1")
        return Self.response(for: request, statusCode: 200, body: """
          [{"server_id":"server-1","server_name":"Docker","name":"web","id":"container-1",
            "state":"running","networks":[]}]
          """)
      }
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let server = try await client.getServer(idOrName: "server-1")
    let history = try await client.getHistoricalServerStats(
      server: "server-1",
      granularity: "1-hr",
      page: 2
    )
    let containers = try await client.listContainers(server: "server-1")

    XCTAssertEqual(server.info.attemptedPublicKey, "old-key")
    XCTAssertEqual(server.info.publicKey, "current-key")
    XCTAssertEqual(server.config.externalAddress, "agent.example.com")
    XCTAssertTrue(server.config.availableFields.contains("external_address"))
    XCTAssertEqual(history.stats.first?.cpuPercent, 20)
    XCTAssertEqual(history.nextPage, 3)
    XCTAssertEqual(containers.first?.name, "web")
  }

  func testGetServerRejectsResponseWithoutConfiguration() async throws {
    MockURLProtocol.handler = { request in
      Self.response(for: request, statusCode: 200, body: """
        {"_id":"server-1","name":"Docker","info":{"state":"Ok"}}
        """)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    do {
      _ = try await client.getServer(idOrName: "server-1")
      XCTFail("GetServer must not invent an editable configuration")
    } catch let error as KomodoAPIError {
      XCTAssertEqual(error, .invalidPayload)
    }
  }

  func testGetServerStateUsesReadContractAndDecodesKnownAndFutureStates() async throws {
    var responseBody = #"{"status":"NotOk"}"#
    MockURLProtocol.handler = { request in
      let json = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
      )
      XCTAssertEqual(json["type"] as? String, "GetServerState")
      XCTAssertEqual((json["params"] as? [String: Any])?["server"] as? String, "server-1")
      return Self.response(for: request, statusCode: 200, body: responseBody)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let unavailable = try await client.getServerState(idOrName: "server-1")
    XCTAssertEqual(unavailable.status, .notOk)

    responseBody = #"{"status":"Maintenance"}"#
    let futureState = try await client.getServerState(idOrName: "server-1")
    XCTAssertEqual(futureState.status, .unknown("Maintenance"))
  }

  func testCreateServerSendsTypedConfigurationToWriteEndpoint() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/write")
      let json = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
      )
      XCTAssertEqual(json["type"] as? String, "CreateServer")
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["name"] as? String, "Docker")
      XCTAssertNil(params["public_key"])
      let config = try XCTUnwrap(params["config"] as? [String: Any])
      XCTAssertEqual(config["address"] as? String, "https://agent.local")
      XCTAssertEqual(config["stats_monitoring"] as? Bool, true)
      XCTAssertNil(config["region"])
      return Self.response(for: request, statusCode: 200, body: """
        {"_id":"server-1","name":"Docker","description":"","tags":[],
         "info":{"state":"Ok"},
         "config":{"address":"https://agent.local","stats_monitoring":true}}
        """)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))
    let patch = ServerConfigPatch(
      address: "https://agent.local",
      statsMonitoring: true
    )

    let server = try await client.createServer(name: "Docker", config: patch)

    XCTAssertEqual(server.id, "server-1")
    XCTAssertTrue(server.config.statsMonitoring)
  }

  func testCreateStackSendsTypedConfigurationToWriteEndpoint() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/write")
      let json = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
      )
      XCTAssertEqual(json["type"] as? String, "CreateStack")
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["name"] as? String, "Home")
      let config = try XCTUnwrap(params["config"] as? [String: Any])
      XCTAssertEqual(config["server_id"] as? String, "server-1")
      XCTAssertEqual(config["project_name"] as? String, "home")
      XCTAssertNil(config["branch"])
      return Self.response(for: request, statusCode: 200, body: """
        {"_id":"stack-1","name":"Home","description":"","template":false,"tags":[],
         "info":{},"config":{"server_id":"server-1","project_name":"home"}}
        """)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))
    let patch = StackConfigPatch(serverID: "server-1", projectName: "home")

    let stack = try await client.createStack(name: "Home", config: patch)

    XCTAssertEqual(stack.id, "stack-1")
    XCTAssertEqual(stack.config.projectName, "home")
  }

  func testUpdateServerSendsOnlyProvidedPartialFieldsToWriteEndpoint() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.absoluteString, "https://komodo.example.com/write")
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any])
      XCTAssertEqual(json["type"] as? String, "UpdateServer")
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["id"] as? String, "server-1")
      let config = try XCTUnwrap(params["config"] as? [String: Any])
      XCTAssertEqual(config["region"] as? String, "office")
      XCTAssertNil(config["address"])
      XCTAssertNil(config["enabled"])
      return Self.response(for: request, statusCode: 200, body: """
        {"_id":"server-1","name":"Docker","description":"","tags":[],
         "info":{"state":"Ok"},"config":{"address":"https://agent.local","region":"office"}}
        """)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))
    let patch = ServerConfigPatch(region: "office")

    let server = try await client.updateServer(id: "server-1", config: patch)

    XCTAssertEqual(server.config.region, "office")
  }

  func testUpdateStackSendsTypedPartialConfiguration() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/write")
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any])
      XCTAssertEqual(json["type"] as? String, "UpdateStack")
      let config = try XCTUnwrap((json["params"] as? [String: Any])?["config"] as? [String: Any])
      XCTAssertEqual(config["branch"] as? String, "stable")
      XCTAssertEqual(config["auto_pull"] as? Bool, true)
      XCTAssertNil(config["repo"])
      return Self.response(for: request, statusCode: 200, body: """
        {"_id":"stack-1","name":"Home","description":"","template":false,"tags":[],
         "info":{},"config":{"server_id":"server-1","branch":"stable","auto_pull":true}}
        """)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))
    let patch = StackConfigPatch(branch: "stable", autoPull: true)

    let stack = try await client.updateStack(id: "stack-1", config: patch)

    XCTAssertEqual(stack.config.branch, "stable")
    XCTAssertTrue(stack.config.autoPull)
  }

  func testForbiddenIsNotReportedAsInvalidAuthentication() async throws {
    MockURLProtocol.handler = { request in
      Self.response(for: request, statusCode: 403, body: #"{"error":"forbidden"}"#)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    do {
      _ = try await client.listServers()
      XCTFail("Expected forbidden")
    } catch {
      XCTAssertEqual(error as? KomodoAPIError, .forbidden)
    }
  }

  func testInspectStackContainerUsesStackAndService() async throws {
    MockURLProtocol.handler = { request in
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any])
      XCTAssertEqual(json["type"] as? String, "InspectStackContainer")
      let params = try XCTUnwrap(json["params"] as? [String: Any])
      XCTAssertEqual(params["stack"] as? String, "stack-1")
      XCTAssertEqual(params["service"] as? String, "web")
      return Self.response(for: request, statusCode: 200, body: """
        {"Id":"container-1","Name":"/home-web","Config":{"Image":"example/web:latest"},
         "State":{"Status":"running","Running":true,"Paused":false,"Restarting":false,"ExitCode":0,"Error":""},
         "Mounts":[{"Type":"bind","Source":"/srv/data","Destination":"/data","RW":true}]}
        """)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let inspection = try await client.inspectStackContainer(stack: "stack-1", service: "web")

    XCTAssertEqual(inspection.image, "example/web:latest")
    XCTAssertEqual(inspection.mounts.first?.destination, "/data")
    XCTAssertTrue(inspection.state?.running == true)
  }

  func testListAllContainersDecodesDockerFormattedStats() async throws {
    MockURLProtocol.handler = { request in
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any])
      XCTAssertEqual(json["type"] as? String, "ListAllContainers")
      return Self.response(for: request, statusCode: 200, body: """
        [{"server_id":"server-1","server_name":"Docker","name":"web","id":"container-1",
          "image":"example/web:latest","state":"running","status":"Up 2 hours",
          "networks":["frontend"],"ports":[{"IP":"0.0.0.0","PrivatePort":80,"PublicPort":8080,"Type":"tcp"}],
          "volumes":["web-data"],"stats":{"Name":"web","CPUPerc":"1.25%","MemPerc":"3.50%",
            "MemUsage":"128MiB / 4GiB","NetIO":"1MB / 2MB","BlockIO":"3MB / 4MB","PIDs":"12"}}]
        """)
    }
    let client = try makeClient(authentication: .bearerToken("signed-token"))

    let containers = try await client.listAllContainers()
    let container = try XCTUnwrap(containers.first)

    XCTAssertEqual(container.stats?.cpuPercent, 1.25)
    XCTAssertEqual(container.stats?.cpuCoreEquivalent, 0.0125)
    XCTAssertEqual(container.stats?.memoryPercent, 3.5)
    XCTAssertEqual(container.stats?.parsedMemoryUsage?.usedBytes, 134_217_728)
    XCTAssertEqual(container.stats?.parsedMemoryUsage?.limitBytes, 4_294_967_296)
    XCTAssertEqual(container.stats?.processCount, 12)
    XCTAssertEqual(container.ports.first?.publicPort, 8080)
  }

  func testContainerMemoryAggregationUsesCombinedUsageAndLimits() throws {
    let stats = try JSONDecoder().decode([ContainerStats].self, from: Data("""
      [
        {"Name":"web","MemUsage":"128MiB / 512MiB"},
        {"Name":"database","MemUsage":"256MiB / 1GiB"}
      ]
      """.utf8))

    let aggregate = try XCTUnwrap(ContainerMemoryUsage.aggregate(stats))

    XCTAssertEqual(aggregate.usedBytes, 402_653_184)
    XCTAssertEqual(aggregate.limitBytes, 1_610_612_736)
    XCTAssertEqual(try XCTUnwrap(aggregate.percentage), 25, accuracy: 0.001)
  }

  func testContainerMemoryAggregationRejectsPartialData() throws {
    let stats = try JSONDecoder().decode([ContainerStats].self, from: Data("""
      [
        {"Name":"web","MemUsage":"128MiB / 512MiB"},
        {"Name":"database","MemUsage":"not available"}
      ]
      """.utf8))

    XCTAssertNil(ContainerMemoryUsage.aggregate(stats))
  }

  func testContainerMemoryUnitsDistinguishDecimalAndBinaryPrefixes() throws {
    let stats = try JSONDecoder().decode(ContainerStats.self, from: Data(#"{"mem_usage":"1GB / 2GiB"}"#.utf8))
    let usage = try XCTUnwrap(stats.parsedMemoryUsage)

    XCTAssertEqual(usage.usedBytes, 1_000_000_000)
    XCTAssertEqual(usage.limitBytes, 2_147_483_648)
    XCTAssertEqual(try XCTUnwrap(usage.percentage), 46.566, accuracy: 0.001)

    let zeroLimitStats = try JSONDecoder().decode(ContainerStats.self, from: Data(#"{"mem_usage":"0B / 0B"}"#.utf8))
    XCTAssertNil(zeroLimitStats.parsedMemoryUsage?.percentage)
  }

  func testContainerStatsDistinguishesMissingMetricsFromReportedZero() throws {
    let stats = try JSONDecoder().decode(ContainerStats.self, from: Data("""
      {"cpu_perc":0,"pids":0,"Name":"web"}
      """.utf8))

    XCTAssertTrue(stats.availableFields.contains("cpu_perc"))
    XCTAssertTrue(stats.availableFields.contains("pids"))
    XCTAssertFalse(stats.availableFields.contains("mem_usage"))
    XCTAssertEqual(stats.cpuPercent, 0)
    XCTAssertEqual(stats.processCount, 0)
  }

  func testNotificationAlertsUseReadAPIAndDecodeUnknownType() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/read")
      let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any])
      let type = try XCTUnwrap(envelope["type"] as? String)
      let params = try XCTUnwrap(envelope["params"] as? [String: Any])
      switch type {
      case "ListAlerts":
        XCTAssertEqual(params["page"] as? Int, 2)
        return Self.response(for: request, statusCode: 200, body: """
          {"alerts":[{"_id":{"$oid":"67d000000000000000000005"},"ts":1700000000000,"resolved":false,"level":"CRITICAL","target":{"type":"Server","id":"server-1"},"data":{"type":"FutureAlert","data":{"name":"Host A"}},"resolved_ts":null}],"next_page":3}
          """)
      case "GetAlert":
        XCTAssertEqual(params["id"] as? String, "67d000000000000000000005")
        return Self.response(for: request, statusCode: 200, body: """
          {"_id":{"$oid":"67d000000000000000000005"},"ts":1700000000000,"resolved":true,"level":"CRITICAL","target":{"type":"Server","id":"server-1"},"data":{"type":"FutureAlert","data":{"name":"Host A"}},"resolved_ts":1700000060000}
          """)
      default:
        XCTFail("Unexpected request: \(type)")
        return Self.response(for: request, statusCode: 400, body: "{}")
      }
    }

    let client = try makeClient(authentication: .bearerToken("signed-token"))
    let page = try await client.listAlerts(page: 2)
    XCTAssertEqual(page.nextPage, 3)
    XCTAssertEqual(page.alerts.first?.data.type, "FutureAlert")
    let detail = try await client.getAlert(id: try XCTUnwrap(page.alerts.first?.id))
    XCTAssertTrue(detail.resolved)
    XCTAssertEqual(detail.resolvedTimestamp, 1_700_000_060_000)
  }

  func testNotificationUpdatesUseReadAPIAndExposeCompletion() async throws {
    MockURLProtocol.handler = { request in
      let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any])
      let type = try XCTUnwrap(envelope["type"] as? String)
      let params = try XCTUnwrap(envelope["params"] as? [String: Any])
      switch type {
      case "ListUpdates":
        XCTAssertEqual(params["page"] as? Int, 0)
        return Self.response(for: request, statusCode: 200, body: """
          {"updates":[{"id":"update-1","operation":"DeployStack","start_ts":1700000000000,"success":false,"username":"000000000000000000000001","target":{"type":"Stack","id":"stack-1"},"status":"InProgress"}],"next_page":null}
          """)
      case "GetUpdate":
        XCTAssertEqual(params["id"] as? String, "update-1")
        return Self.response(for: request, statusCode: 200, body: """
          {"_id":{"$oid":"67d000000000000000000006"},"operation":"DeployStack","start_ts":1700000000000,"end_ts":1700000060000,"success":false,"target":{"type":"Stack","id":"stack-1"},"status":"Complete","logs":[{"stage":"Deploy","success":false,"stdout":"","stderr":"failed"}]}
          """)
      default:
        XCTFail("Unexpected request: \(type)")
        return Self.response(for: request, statusCode: 400, body: "{}")
      }
    }

    let client = try makeClient(authentication: .bearerToken("signed-token"))
    let page = try await client.listUpdates()
    XCTAssertEqual(page.updates.first?.status, "InProgress")
    XCTAssertEqual(page.updates.first?.actorDisplayName, String(localized: "notifications.actor.procedure"))
    let detail = try await client.getUpdate(id: "update-1")
    XCTAssertEqual(detail.status, "Complete")
    XCTAssertFalse(detail.success)
    XCTAssertEqual(detail.logs.first?.stage, "Deploy")
  }

  @MainActor
  func testNotificationBadgeCountsUnreadItemsAcrossFilteredPages() async throws {
    let client = try makeClient(authentication: .bearerToken("signed-token"))
    let defaultsName = "notifications-test-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let profile = ServerProfile(
      name: "Test", address: try ServerAddress("https://komodo.example.com"),
      authenticationKind: .bearerToken
    )
    let store = NotificationInboxStore(defaults: defaults) { _, _ in client }
    let keychain = KeychainStore(service: defaultsName)

    func setResponses(includeNew: Bool) {
      MockURLProtocol.handler = { @Sendable request in
        let envelope = try XCTUnwrap(
          JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
        )
        let type = try XCTUnwrap(envelope["type"] as? String)
        let params = try XCTUnwrap(envelope["params"] as? [String: Any])
        let page = try XCTUnwrap(params["page"] as? Int)
        let query = params["query"] as? [String: Any]
        let filtered = query != nil
        if filtered {
          if type == "ListAlerts" {
            XCTAssertEqual(query?["resolved"] as? Bool, false)
          } else {
            XCTAssertEqual(query?["status"] as? String, "Complete")
            XCTAssertEqual(query?["success"] as? Bool, false)
          }
        }
        let ids: [String]
        let nextPage: String
        if page == 0 {
          ids = includeNew ? ["000000000000000000000003", "000000000000000000000001"]
            : ["000000000000000000000001"]
          nextPage = filtered ? "1" : "null"
        } else {
          XCTAssertEqual(page, 1)
          ids = ["000000000000000000000002"]
          nextPage = "null"
        }
        let entries = ids.map { id -> String in
          if type == "ListAlerts" {
            return """
              {"_id":"\(id)","ts":1700000000000,"resolved":false,"level":"CRITICAL","target":{"type":"Server","id":"server-1"},"data":{"type":"TestAlert"}}
              """
          }
          return """
            {"id":"\(id)","operation":"DeployStack","start_ts":1700000000000,"success":false,"target":{"type":"Stack","id":"stack-1"},"status":"Complete"}
            """
        }.joined(separator: ",")
        let key = type == "ListAlerts" ? "alerts" : "updates"
        return Self.response(
          for: request, statusCode: 200,
          body: "{\"\(key)\":[\(entries)],\"next_page\":\(nextPage)}"
        )
      }
    }

    setResponses(includeNew: false)
    await store.loadIfNeeded(profile: profile, keychainStore: keychain)
    XCTAssertEqual(store.openAlertCount, 2)
    XCTAssertEqual(store.unreadCount, 0)

    setResponses(includeNew: true)
    await store.refresh()
    XCTAssertEqual(store.openAlertCount, 3)
    XCTAssertEqual(store.unreadCount, 2)
    store.markRead(.alert(try XCTUnwrap(store.alerts.first)))
    XCTAssertEqual(store.unreadCount, 1)
    store.markAllRead()
    XCTAssertEqual(store.unreadCount, 0)
    await store.refresh()
    XCTAssertEqual(store.unreadCount, 0)
  }

  @MainActor
  func testNotificationInboxRebuildsClientAfterConnectionEdit() async throws {
    let defaultsName = "notifications-client-test-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let profile = ServerProfile(
      name: "Test", address: try ServerAddress("https://old.example.com"),
      authenticationKind: .bearerToken
    )
    let oldAddress = profile.baseURL
    let keychain = KeychainStore(service: defaultsName)
    var clientAddresses: [String] = []
    let store = NotificationInboxStore(defaults: defaults) { profile, _ in
      clientAddresses.append(profile.baseURL)
      return try self.makeClient(authentication: .bearerToken("signed-token"))
    }
    MockURLProtocol.handler = { request in
      let envelope = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
      )
      let type = try XCTUnwrap(envelope["type"] as? String)
      let body = type == "ListAlerts"
        ? "{\"alerts\":[],\"next_page\":null}"
        : "{\"updates\":[],\"next_page\":null}"
      return Self.response(for: request, statusCode: 200, body: body)
    }

    await store.loadIfNeeded(profile: profile, keychainStore: keychain)
    profile.update(
      name: "Test", address: try ServerAddress("https://new.example.com"),
      authenticationKind: .bearerToken
    )
    let newAddress = profile.baseURL
    await store.refresh()

    XCTAssertNotEqual(oldAddress, newAddress)
    XCTAssertEqual(clientAddresses, [oldAddress, newAddress])

    let replacement = ServerProfile(
      id: profile.id, name: "Test",
      address: try ServerAddress("https://third.example.com"),
      authenticationKind: .bearerToken
    )
    await store.connectionDidChange(profile: replacement)
    XCTAssertEqual(clientAddresses, [oldAddress, newAddress, replacement.baseURL])
  }

  @MainActor
  func testNotificationInboxKeepsLoadedPagesAfterRefresh() async throws {
    let defaultsName = "notifications-pages-test-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let profile = ServerProfile(
      name: "Test", address: try ServerAddress("https://komodo.example.com"),
      authenticationKind: .bearerToken
    )
    let keychain = KeychainStore(service: defaultsName)
    let client = try makeClient(authentication: .bearerToken("signed-token"))
    let store = NotificationInboxStore(defaults: defaults) { _, _ in client }

    func setResponses(firstID: String) {
      MockURLProtocol.handler = { request in
        let envelope = try XCTUnwrap(
          JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any]
        )
        let type = try XCTUnwrap(envelope["type"] as? String)
        let params = try XCTUnwrap(envelope["params"] as? [String: Any])
        let filtered = params["query"] != nil
        let page = try XCTUnwrap(params["page"] as? Int)
        let id = page == 0 ? firstID : "second"
        let nextPage = page == 0 && !filtered ? "1" : "null"
        let entry: String
        let key: String
        if type == "ListAlerts" {
          key = "alerts"
          entry = """
            {"_id":"alert-\(id)","ts":1700000000000,"resolved":false,"level":"WARNING","target":{"type":"Server","id":"server-1"},"data":{"type":"TestAlert"}}
            """
        } else {
          key = "updates"
          entry = """
            {"id":"update-\(id)","operation":"DeployStack","start_ts":1700000000000,"success":true,"target":{"type":"Stack","id":"stack-1"},"status":"Complete"}
            """
        }
        let entries = filtered ? "" : entry
        let body = "{\"\(key)\":[\(entries)],\"next_page\":\(nextPage)}"
        return Self.response(for: request, statusCode: 200, body: body)
      }
    }

    setResponses(firstID: "first")
    await store.loadIfNeeded(profile: profile, keychainStore: keychain)
    await store.loadMore()
    XCTAssertEqual(store.alerts.map(\.id), ["alert-first", "alert-second"])
    XCTAssertEqual(store.updates.map(\.id), ["update-first", "update-second"])

    setResponses(firstID: "new")
    await store.refresh()
    XCTAssertEqual(store.alerts.map(\.id), ["alert-new", "alert-second"])
    XCTAssertEqual(store.updates.map(\.id), ["update-new", "update-second"])
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
