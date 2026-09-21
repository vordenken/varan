import Foundation

enum KomodoAuthentication: Sendable {
  case apiKey(key: String, secret: String)
  case bearerToken(String)
}

enum KomodoAPIError: LocalizedError, Equatable {
  case invalidResponse
  case unauthorized
  case invalidToken
  case forbidden
  case server(statusCode: Int, reason: String?)
  case invalidPayload
  case networkUnavailable
  case timedOut
  case connectionFailed

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      String(localized: "error.api.invalidResponse")
    case .unauthorized:
      String(localized: "error.api.unauthorized")
    case .invalidToken:
      String(localized: "error.api.invalidToken")
    case .forbidden:
      String(localized: "error.api.forbidden")
    case .server(let statusCode, let reason):
      if let reason {
        String(format: String(localized: "error.api.server.withReason"), statusCode, reason)
      } else {
        String(format: String(localized: "error.api.server.withoutReason"), statusCode)
      }
    case .invalidPayload:
      String(localized: "error.api.invalidPayload")
    case .networkUnavailable:
      String(localized: "error.api.networkUnavailable")
    case .timedOut:
      String(localized: "error.api.timedOut")
    case .connectionFailed:
      String(localized: "error.api.connectionFailed")
    }
  }
}

actor KomodoAPIClient {
  private enum Endpoint: String {
    case read
    case write
    case execute
  }

  private struct RequestBody<Parameters: Encodable>: Encodable {
    let type: String
    let params: Parameters
  }

  private struct ErrorResponse: Decodable {
    let error: String
  }

  private struct StackQuery: Encodable {}
  private struct ServerQuery: Encodable {}

  private struct ListStacksParameters: Encodable {
    let query: StackQuery
    let page: Int
    let limit: Int
  }

  private struct StackParameters: Encodable {
    let stack: String
  }

  private struct StackActionParameters: Encodable {
    let stack: String
    let services: [String]
  }

  private struct DeployStackParameters: Encodable {
    let stack: String
    let services: [String]
    let stopTime: Int?

    enum CodingKeys: String, CodingKey {
      case stack, services
      case stopTime = "stop_time"
    }
  }

  private struct DestroyStackParameters: Encodable {
    let stack: String
    let services: [String]
    let removeOrphans: Bool
    let stopTime: Int?

    enum CodingKeys: String, CodingKey {
      case stack, services
      case removeOrphans = "remove_orphans"
      case stopTime = "stop_time"
    }
  }

  private struct StopStackParameters: Encodable {
    let stack: String
    let stopTime: Int?
    let services: [String]

    enum CodingKeys: String, CodingKey {
      case stack
      case stopTime = "stop_time"
      case services
    }
  }

  private struct ContainerParameters: Encodable {
    let server: String
    let container: String
  }

  private struct DeleteResourceParameters: Encodable {
    let id: String
  }

  private struct StopContainerParameters: Encodable {
    let server: String
    let container: String
    let signal: String?
    let time: Int?
  }

  private struct StackLogParameters: Encodable {
    let stack: String
    let services: [String]
    let tail: Int
    let timestamps: Bool
  }
  private struct InspectStackContainerParameters: Encodable {
    let stack: String
    let service: String
  }

  private struct ContainerLogParameters: Encodable {
    let server: String
    let container: String
    let tail: Int
    let timestamps: Bool
  }

  private struct ListServersParameters: Encodable {
    let query: ServerQuery
    let page: Int
    let limit: Int
  }

  private struct ServerParameters: Encodable { let server: String }
  private struct HistoricalStatsParameters: Encodable {
    let server: String
    let granularity: String
    let page: Int
  }
  private struct ListAllContainersParameters: Encodable {
    let servers: [String] = []
    let tags: [String] = []
    let terms: [String] = []
    let state: [String] = []
    let page: Int
    let limit: Int
  }
  private struct ListContainersParameters: Encodable { let server: String }
  private struct CreateServerParameters: Encodable {
    let name: String
    let config: ServerConfigPatch
    let publicKey: String? = nil
    enum CodingKeys: String, CodingKey { case name, config; case publicKey = "public_key" }
  }
  private struct UpdateServerParameters: Encodable { let id: String; let config: ServerConfigPatch }
  private struct CreateStackParameters: Encodable { let name: String; let config: StackConfigPatch }
  private struct UpdateStackParameters: Encodable { let id: String; let config: StackConfigPatch }

  private let address: ServerAddress
  private let authentication: KomodoAuthentication
  private let session: URLSession
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    address: ServerAddress,
    authentication: KomodoAuthentication,
    session: URLSession = .shared
  ) {
    self.address = address
    self.authentication = authentication
    self.session = session
  }

  func testConnection() async throws {
    _ = try await listStacks(page: 0, limit: 1)
  }

  func listStacks(page: Int = 0, limit: Int = 50) async throws -> [StackListItem] {
    let parameters = ListStacksParameters(query: StackQuery(), page: page, limit: limit)
    return try await read(type: "ListStacks", parameters: parameters)
  }

  func getStack(idOrName: String) async throws -> StackDetail {
    try await read(type: "GetStack", parameters: StackParameters(stack: idOrName))
  }

  func listServers(page: Int = 0, limit: Int = 50) async throws -> [ServerListItem] {
    try await read(
      type: "ListServers",
      parameters: ListServersParameters(query: ServerQuery(), page: page, limit: limit)
    )
  }

  func getServer(idOrName: String) async throws -> ServerDetail {
    try await read(type: "GetServer", parameters: ServerParameters(server: idOrName))
  }

  func getServerState(idOrName: String) async throws -> ServerStateResponse {
    try await read(type: "GetServerState", parameters: ServerParameters(server: idOrName))
  }

  func getSystemStats(server: String) async throws -> SystemStats {
    try await read(type: "GetSystemStats", parameters: ServerParameters(server: server))
  }

  func getHistoricalServerStats(
    server: String,
    granularity: String = "15-min",
    page: Int = 0
  ) async throws -> HistoricalSystemStatsPage {
    try await read(
      type: "GetHistoricalServerStats",
      parameters: HistoricalStatsParameters(server: server, granularity: granularity, page: page)
    )
  }

  func listAllContainers(page: Int = 0, limit: Int = 100) async throws -> [ContainerListItem] {
    try await read(
      type: "ListAllContainers",
      parameters: ListAllContainersParameters(page: page, limit: limit)
    )
  }

  func listContainers(server: String) async throws -> [ContainerListItem] {
    try await read(type: "ListContainers", parameters: ListContainersParameters(server: server))
  }

  func createServer(name: String, config: ServerConfigPatch) async throws -> ServerDetail {
    try await write(
      type: "CreateServer",
      parameters: CreateServerParameters(name: name, config: config)
    )
  }

  func updateServer(id: String, config: ServerConfigPatch) async throws -> ServerDetail {
    try await write(type: "UpdateServer", parameters: UpdateServerParameters(id: id, config: config))
  }

  func deleteServer(idOrName: String) async throws -> ServerDetail {
    try await write(type: "DeleteServer", parameters: DeleteResourceParameters(id: idOrName))
  }

  func createStack(name: String, config: StackConfigPatch) async throws -> StackDetail {
    try await write(type: "CreateStack", parameters: CreateStackParameters(name: name, config: config))
  }

  func updateStack(id: String, config: StackConfigPatch) async throws -> StackDetail {
    try await write(type: "UpdateStack", parameters: UpdateStackParameters(id: id, config: config))
  }

  func deleteStack(idOrName: String) async throws -> StackDetail {
    try await write(type: "DeleteStack", parameters: DeleteResourceParameters(id: idOrName))
  }

  func listStackServices(stack idOrName: String) async throws -> [StackService] {
    try await read(type: "ListStackServices", parameters: StackParameters(stack: idOrName))
  }

  func inspectStackContainer(stack: String, service: String) async throws -> ContainerInspection {
    try await read(
      type: "InspectStackContainer",
      parameters: InspectStackContainerParameters(stack: stack, service: service)
    )
  }

  func startStack(idOrName: String, services: [String] = []) async throws -> KomodoUpdate {
    try await execute(
      type: "StartStack",
      parameters: StackActionParameters(stack: idOrName, services: services)
    )
  }

  func deployStack(idOrName: String, services: [String] = []) async throws -> KomodoUpdate {
    try await execute(
      type: "DeployStack",
      parameters: DeployStackParameters(stack: idOrName, services: services, stopTime: nil)
    )
  }

  func pullStackImages(idOrName: String, services: [String] = []) async throws -> KomodoUpdate {
    try await execute(
      type: "PullStack",
      parameters: StackActionParameters(stack: idOrName, services: services)
    )
  }

  func restartStack(idOrName: String, services: [String] = []) async throws -> KomodoUpdate {
    try await execute(
      type: "RestartStack",
      parameters: StackActionParameters(stack: idOrName, services: services)
    )
  }

  func pauseStack(idOrName: String, services: [String] = []) async throws -> KomodoUpdate {
    try await execute(
      type: "PauseStack",
      parameters: StackActionParameters(stack: idOrName, services: services)
    )
  }

  func unpauseStack(idOrName: String, services: [String] = []) async throws -> KomodoUpdate {
    try await execute(
      type: "UnpauseStack",
      parameters: StackActionParameters(stack: idOrName, services: services)
    )
  }

  func stopStack(idOrName: String, services: [String] = []) async throws -> KomodoUpdate {
    try await execute(
      type: "StopStack",
      parameters: StopStackParameters(stack: idOrName, stopTime: nil, services: services)
    )
  }

  func destroyStack(
    idOrName: String,
    services: [String] = [],
    removeOrphans: Bool = false
  ) async throws -> KomodoUpdate {
    try await execute(
      type: "DestroyStack",
      parameters: DestroyStackParameters(
        stack: idOrName,
        services: services,
        removeOrphans: removeOrphans,
        stopTime: nil
      )
    )
  }

  func startContainer(server: String, container: String) async throws -> KomodoUpdate {
    try await execute(
      type: "StartContainer",
      parameters: ContainerParameters(server: server, container: container)
    )
  }

  func restartContainer(server: String, container: String) async throws -> KomodoUpdate {
    try await execute(
      type: "RestartContainer",
      parameters: ContainerParameters(server: server, container: container)
    )
  }

  func pauseContainer(server: String, container: String) async throws -> KomodoUpdate {
    try await execute(
      type: "PauseContainer",
      parameters: ContainerParameters(server: server, container: container)
    )
  }

  func unpauseContainer(server: String, container: String) async throws -> KomodoUpdate {
    try await execute(
      type: "UnpauseContainer",
      parameters: ContainerParameters(server: server, container: container)
    )
  }

  func stopContainer(server: String, container: String) async throws -> KomodoUpdate {
    try await execute(
      type: "StopContainer",
      parameters: StopContainerParameters(
        server: server,
        container: container,
        signal: nil,
        time: nil
      )
    )
  }

  func destroyContainer(server: String, container: String) async throws -> KomodoUpdate {
    try await execute(
      type: "DestroyContainer",
      parameters: StopContainerParameters(
        server: server,
        container: container,
        signal: nil,
        time: nil
      )
    )
  }

  func getStackLog(
    stack idOrName: String,
    services: [String] = [],
    tail: Int = 200,
    timestamps: Bool = true
  ) async throws -> KomodoLog {
    try await read(
      type: "GetStackLog",
      parameters: StackLogParameters(
        stack: idOrName,
        services: services,
        tail: tail,
        timestamps: timestamps
      )
    )
  }

  func getContainerLog(
    server: String,
    container: String,
    tail: Int = 200,
    timestamps: Bool = true
  ) async throws -> KomodoLog {
    try await read(
      type: "GetContainerLog",
      parameters: ContainerLogParameters(
        server: server,
        container: container,
        tail: tail,
        timestamps: timestamps
      )
    )
  }

  private func read<Response: Decodable, Parameters: Encodable>(
    type: String,
    parameters: Parameters
  ) async throws -> Response {
    try await request(endpoint: .read, type: type, parameters: parameters)
  }

  private func execute<Response: Decodable, Parameters: Encodable>(
    type: String,
    parameters: Parameters
  ) async throws -> Response {
    try await request(endpoint: .execute, type: type, parameters: parameters)
  }

  private func write<Response: Decodable, Parameters: Encodable>(
    type: String,
    parameters: Parameters
  ) async throws -> Response {
    try await request(endpoint: .write, type: type, parameters: parameters)
  }

  private func request<Response: Decodable, Parameters: Encodable>(
    endpoint: Endpoint,
    type: String,
    parameters: Parameters
  ) async throws -> Response {
    var request = URLRequest(url: address.url.appendingPathComponent(endpoint.rawValue))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    applyAuthentication(to: &request)
    request.httpBody = try encoder.encode(RequestBody(type: type, params: parameters))

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError {
      switch error.code {
      case .cancelled:
        throw CancellationError()
      case .notConnectedToInternet, .networkConnectionLost:
        throw KomodoAPIError.networkUnavailable
      case .timedOut:
        throw KomodoAPIError.timedOut
      default:
        throw KomodoAPIError.connectionFailed
      }
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw KomodoAPIError.invalidResponse
    }
    switch httpResponse.statusCode {
    case 200..<300:
      do {
        return try decoder.decode(Response.self, from: data)
      } catch {
        throw KomodoAPIError.invalidPayload
      }
    case 401:
      switch authentication {
      case .bearerToken:
        throw KomodoAPIError.invalidToken
      case .apiKey:
        throw KomodoAPIError.unauthorized
      }
    case 403:
      throw KomodoAPIError.forbidden
    default:
      throw KomodoAPIError.server(
        statusCode: httpResponse.statusCode,
        reason: safeServerReason(from: data)
      )
    }
  }

  private func safeServerReason(from data: Data) -> String? {
    guard let response = try? decoder.decode(ErrorResponse.self, from: data) else {
      return nil
    }
    let reason = response.error
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !reason.isEmpty, reason.count <= 200 else { return nil }

    let sensitiveTerms = ["token", "secret", "password", "authorization", "api key", "x-api"]
    guard !sensitiveTerms.contains(where: reason.localizedCaseInsensitiveContains) else {
      return nil
    }
    return reason
  }

  private func applyAuthentication(to request: inout URLRequest) {
    switch authentication {
    case .apiKey(let key, let secret):
      request.setValue(key, forHTTPHeaderField: "x-api-key")
      request.setValue(secret, forHTTPHeaderField: "x-api-secret")
    case .bearerToken(let token):
      request.setValue(token, forHTTPHeaderField: "authorization")
    }
  }
}
