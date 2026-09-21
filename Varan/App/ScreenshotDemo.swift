import Foundation
import SwiftUI

#if DEBUG
enum ScreenshotDemo {
  static let enabled = ProcessInfo.processInfo.arguments.contains("--screenshot-demo")

  static var screen: String {
    guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--screenshot-screen"),
          ProcessInfo.processInfo.arguments.indices.contains(index + 1) else {
      return "server"
    }
    return ProcessInfo.processInfo.arguments[index + 1]
  }

  @MainActor static var profile: ServerProfile {
    ServerProfile(
      id: UUID(uuidString: "A78E92E1-C218-4B26-B40A-641E5E5A4200")!,
      name: "Demo",
      address: try! ServerAddress("https://demo.varan.invalid"),
      authenticationKind: .apiKey
    )
  }

  static func makeClient() -> KomodoAPIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ScreenshotDemoURLProtocol.self]
    return KomodoAPIClient(
      address: try! ServerAddress("https://demo.varan.invalid"),
      authentication: .apiKey(key: "demo", secret: "demo"),
      session: URLSession(configuration: configuration)
    )
  }

  static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T {
    try! JSONDecoder().decode(type, from: Data(json.utf8))
  }

  static var serverSummary: ServerListItem {
    decode(ServerListItem.self, from: serverListJSON.dropArray)
  }

  static var stackSummary: StackListItem {
    decode(StackListItem.self, from: stackListJSON.dropArray)
  }

  static var containerSummary: ContainerListItem {
    decode([ContainerListItem].self, from: containersJSON)[0]
  }

  static let serverListJSON = """
  [{"id":"server-home","name":"Home Server","template":false,"tags":["production"],"info":{"state":"Ok","version":"1.19.4","stats":{"cpu_perc":18.7,"mem_used_gb":6.4,"mem_total_gb":16},"region":"Home Lab","address":"192.168.1.10"}}]
  """

  static let serverDetailJSON = """
  {"_id":"server-home","name":"Home Server","description":"Primary home lab host","tags":["production"],"info":{},"config":{"address":"https://192.168.1.10:8120","external_address":"https://komodo.example.com","region":"Home Lab","enabled":true,"insecure_tls":false,"auto_prune":true,"stats_monitoring":true}}
  """

  static let systemStatsJSON = """
  {"cpu_perc":18.7,"load_average":{"one":0.82,"five":0.66,"fifteen":0.59},"mem_used_gb":6.4,"mem_total_gb":16,"swap_used_gb":0.1,"swap_total_gb":4,"disks":[{"mount":"/","file_system":"apfs","used_gb":128.2,"total_gb":500}],"network_ingress_bytes":2843000,"network_egress_bytes":917000,"refresh_ts":1789983600,"polling_rate":"5 seconds"}
  """

  static let historyJSON = """
  {"stats":[{"ts":1789979100,"cpu_perc":12.2,"mem_used_gb":6.1,"mem_total_gb":16},{"ts":1789980000,"cpu_perc":22.8,"mem_used_gb":6.2,"mem_total_gb":16},{"ts":1789980900,"cpu_perc":16.4,"mem_used_gb":6.3,"mem_total_gb":16},{"ts":1789981800,"cpu_perc":28.1,"mem_used_gb":6.4,"mem_total_gb":16},{"ts":1789982700,"cpu_perc":18.7,"mem_used_gb":6.4,"mem_total_gb":16}],"next_page":null}
  """

  static let stackListJSON = """
  [{"id":"stack-home","name":"Home Services","template":false,"tags":["production"],"info":{"server_name":"Home Server","swarm_name":"","state":"running","status":"deployed","services":[{"service":"web","image":"ghcr.io/example/home-web:2.4","update_available":true},{"service":"database","image":"postgres:17","update_available":false}]}}]
  """

  static let stackDetailJSON = """
  {"_id":"stack-home","name":"Home Services","description":"Core services for the home lab","template":false,"tags":["production"],"info":{"missing_files":[],"deployed_project_name":"home-services","deployed_hash":"c124a98","latest_hash":"d833fb2","latest_services":[{"service_name":"web","container_name":"home-web-1","image":"ghcr.io/example/home-web:2.4"},{"service_name":"database","container_name":"home-db-1","image":"postgres:17"}]},"config":{"server_id":"server-home","swarm_id":"","project_name":"home-services","file_paths":["compose.yaml"],"linked_repo":"","repo":"example/home-services","branch":"main","auto_pull":true,"poll_for_updates":true,"auto_update":false}}
  """

  static let containersJSON = """
  [{"id":"container-web","server_id":"server-home","server_name":"Home Server","name":"home-web-1","image":"ghcr.io/example/home-web:2.4","image_id":"sha256:abc","state":"running","status":"Up 12 hours","networks":["proxy","backend"],"created":1789940400,"size_rw":12582912,"size_root_fs":268435456,"network_mode":"proxy","ports":[{"IP":"0.0.0.0","PrivatePort":8080,"PublicPort":443,"Type":"tcp"}],"volumes":["/srv/home/config:/app/config"],"stats":{"name":"home-web-1","cpu_perc":2.8,"mem_perc":12.4,"mem_usage":"126MiB / 1GiB","net_io":"18.4MB / 6.7MB","block_io":"42.1MB / 8.2MB","pids":14}},{"id":"container-db","server_id":"server-home","server_name":"Home Server","name":"home-db-1","image":"postgres:17","state":"running","status":"Up 12 hours","networks":["backend"],"network_mode":"backend","ports":[],"volumes":["home-db:/var/lib/postgresql/data"],"stats":{"name":"home-db-1","cpu_perc":1.2,"mem_perc":18.7,"mem_usage":"191MiB / 1GiB","net_io":"4.2MB / 9.1MB","block_io":"84.5MB / 31.2MB","pids":9}}]
  """

  static let webContainerJSON = """
  {"id":"container-web","server_id":"server-home","server_name":"Home Server","name":"home-web-1","image":"ghcr.io/example/home-web:2.4","image_id":"sha256:abc","state":"running","status":"Up 12 hours","networks":["proxy","backend"],"created":1789940400,"size_rw":12582912,"size_root_fs":268435456,"network_mode":"proxy","ports":[{"IP":"0.0.0.0","PrivatePort":8080,"PublicPort":443,"Type":"tcp"}],"volumes":["/srv/home/config:/app/config"],"stats":{"name":"home-web-1","cpu_perc":2.8,"mem_perc":12.4,"mem_usage":"126MiB / 1GiB","net_io":"18.4MB / 6.7MB","block_io":"42.1MB / 8.2MB","pids":14}}
  """

  static let servicesJSON = """
  [{"stack_id":"stack-home","stack_name":"Home Services","service":"web","image":"ghcr.io/example/home-web:2.4","state":"running","container":\(webContainerJSON)},{"stack_id":"stack-home","stack_name":"Home Services","service":"database","image":"postgres:17","state":"running","container":{"id":"container-db","server_id":"server-home","server_name":"Home Server","name":"home-db-1","image":"postgres:17","state":"running","status":"Up 12 hours","networks":["backend"],"network_mode":"backend","ports":[],"volumes":["home-db:/var/lib/postgresql/data"],"stats":{"name":"home-db-1","cpu_perc":1.2,"mem_perc":18.7,"mem_usage":"191MiB / 1GiB","net_io":"4.2MB / 9.1MB","block_io":"84.5MB / 31.2MB","pids":9}}}]
  """

  static let logJSON = """
  {"stage":"container_log","command":"docker logs","stdout":"2026-09-21T09:38:14Z Server started on port 8080\\n2026-09-21T09:38:15Z Connected to database\\n2026-09-21T09:39:02Z GET /health 200 4ms\\n2026-09-21T09:40:17Z GET /api/status 200 12ms\\n2026-09-21T09:41:03Z Background sync completed","stderr":"","success":true,"start_ts":1789983494,"end_ts":1789983663}
  """
}

private extension String {
  var dropArray: String {
    String(dropFirst().dropLast())
  }
}

private final class ScreenshotDemoURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let data = Self.bodyData(from: request)
    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let requestType = object?["type"] as? String ?? ""
    let json = Self.responseJSON(for: requestType)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(json.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func bodyData(from request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      body.append(buffer, count: count)
    }
    return body
  }

  private static func responseJSON(for type: String) -> String {
    switch type {
    case "ListServers": ScreenshotDemo.serverListJSON
    case "GetServer": ScreenshotDemo.serverDetailJSON
    case "GetServerState": "{\"status\":\"Ok\"}"
    case "GetSystemStats": ScreenshotDemo.systemStatsJSON
    case "GetHistoricalServerStats": ScreenshotDemo.historyJSON
    case "ListStacks": ScreenshotDemo.stackListJSON
    case "GetStack": ScreenshotDemo.stackDetailJSON
    case "ListStackServices": ScreenshotDemo.servicesJSON
    case "ListAllContainers", "ListContainers": ScreenshotDemo.containersJSON
    case "GetStackLog", "GetContainerLog": ScreenshotDemo.logJSON
    default: "{\"_id\":\"demo-update\",\"success\":true,\"status\":\"Complete\"}"
    }
  }
}

#if os(iOS)
struct ScreenshotDemoRootView: View {
  @StateObject private var liveUpdates = KomodoLiveUpdateController(initialStatus: .live)
  @StateObject private var appSettings = AppSettings()
  @State private var selectedTab = ScreenshotDemo.screen

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("title.servers", systemImage: "server.rack", value: "server") {
        demoNavigation { serverDetail }
      }
      Tab("title.stacks", systemImage: "square.stack.3d.up.fill", value: "stack") {
        demoNavigation { stackDetail }
      }
      Tab("title.containers", systemImage: "shippingbox.fill", value: "container") {
        demoNavigation { containerDetail }
      }
      Tab("settings.title", systemImage: "gearshape.fill", value: "settings") {
        NavigationStack { SettingsView(settings: appSettings) }
      }
    }
    .environmentObject(liveUpdates)
    .preferredColorScheme(.dark)
  }

  private func demoNavigation<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    NavigationStack {
      content()
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("action.back", systemImage: "chevron.backward") {}
          }
        }
    }
  }

  private var serverDetail: some View {
    ServerDetailView(
      summary: ScreenshotDemo.serverSummary,
      profile: ScreenshotDemo.profile,
      keychainStore: .shared,
      appSettings: appSettings
    )
  }

  private var stackDetail: some View {
    StackDetailView(
      summary: ScreenshotDemo.stackSummary,
      profile: ScreenshotDemo.profile,
      keychainStore: .shared,
      appSettings: appSettings
    )
  }

  private var containerDetail: some View {
    ContainerDetailView(
      container: ScreenshotDemo.containerSummary,
      profile: ScreenshotDemo.profile,
      keychainStore: .shared,
      appSettings: appSettings
    )
  }
}
#endif
#endif
