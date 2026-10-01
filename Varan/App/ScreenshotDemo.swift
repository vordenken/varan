import Foundation
import SwiftUI

#if DEBUG
enum ScreenshotDemo {
  static let enabled = ProcessInfo.processInfo.arguments.contains("--screenshot-demo")
  static let colorScheme: ColorScheme? = ProcessInfo.processInfo.arguments.contains("--screenshot-light") ? .light : .dark

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
      screenshotAddress: try! ServerAddress("https://demo.varan.invalid"),
      session: URLSession(configuration: configuration)
    )
  }

  static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T {
    try! JSONDecoder().decode(type, from: Data(json.utf8))
  }

  static var serverSummary: ServerListItem {
    decode(ServerListItem.self, from: serverListResponseJSON.dropArray)
  }

  static var serverListResponseJSON: String {
    guard screen == "server-partial" else { return serverListJSON }
    return serverListJSON.replacingOccurrences(
      of: "\"region\":\"Home Lab\",\"address\":\"192.168.1.10\"",
      with: "\"region\":\"\",\"address\":null,\"external_address\":\"server.example.com\""
    )
  }

  static var stackSummary: StackListItem {
    decode(StackListItem.self, from: stackListJSON.dropArray)
  }

  static var containerSummary: ContainerListItem {
    decode([ContainerListItem].self, from: containersJSON)[0]
  }

  static let serverListJSON = """
  [{"id":"server-home","name":"Home Server","template":false,"tags":["production"],"info":{"state":"Ok","version":"1.19.4","stats":{"cpu_perc":18.7,"mem_used_gb":6.4,"mem_total_gb":16},"region":"Home Lab","address":"192.168.1.10","public_ip":"203.0.113.10"}}]
  """

  static let serverDetailJSON = """
  {"_id":"server-home","name":"Home Server","description":"Primary home lab host","tags":["production"],"info":{},"config":{"address":"https://192.168.1.10:8120","external_address":"https://komodo.example.com","region":"Home Lab","enabled":true,"insecure_tls":false,"auto_prune":true,"stats_monitoring":true,"auto_rotate_keys":true,"passkey":"","ignore_mounts":["/mnt/backup"],"send_unreachable_alerts":true,"send_cpu_alerts":true,"send_mem_alerts":true,"send_disk_alerts":true,"send_version_mismatch_alerts":true,"cpu_warning":90,"cpu_critical":99,"mem_warning":75,"mem_critical":95,"disk_warning":75,"disk_critical":95,"maintenance_windows":[{"name":"Weekly maintenance","description":"Host updates","schedule_type":"Weekly","day_of_week":"Sunday","date":"","hour":3,"minute":0,"duration_minutes":30,"timezone":"Europe/Berlin","enabled":true}]}}
  """

  static var serverDetailResponseJSON: String {
    guard screen == "server-partial" else { return serverDetailJSON }
    return serverDetailJSON.replacingOccurrences(
      of: "\"address\":\"https://192.168.1.10:8120\",\"external_address\":\"https://komodo.example.com\",\"region\":\"Home Lab\"",
      with: "\"address\":\"\",\"region\":\"\""
    )
  }

  static let systemStatsJSON = """
  {"cpu_perc":18.7,"load_average":{"one":0.82,"five":0.66,"fifteen":0.59},"mem_used_gb":6.4,"mem_total_gb":16,"swap_used_gb":0.1,"swap_total_gb":4,"disks":[{"mount":"/","file_system":"apfs","used_gb":128.2,"total_gb":500}],"network_ingress_bytes":2843000,"network_egress_bytes":917000,"refresh_ts":1789983600,"polling_rate":"5 seconds"}
  """

  static let historyJSON = """
  {"stats":[{"ts":1789979100,"cpu_perc":12.2,"mem_used_gb":6.1,"mem_total_gb":16},{"ts":1789980000,"cpu_perc":22.8,"mem_used_gb":6.2,"mem_total_gb":16},{"ts":1789980900,"cpu_perc":16.4,"mem_used_gb":6.3,"mem_total_gb":16},{"ts":1789981800,"cpu_perc":28.1,"mem_used_gb":6.4,"mem_total_gb":16},{"ts":1789982700,"cpu_perc":18.7,"mem_used_gb":6.4,"mem_total_gb":16}],"next_page":null}
  """

  static let stackListJSON = """
  [{"id":"stack-home","name":"Home Services","template":false,"tags":["production"],"info":{"server_name":"Home Server","swarm_name":"","state":"running","status":"deployed","services":[{"service":"web","image":"ghcr.io/example/home-web:2.4","update_available":true},{"service":"database","image":"postgres:17","update_available":false}]}}]
  """

  static var stackOverviewJSON: String {
    String(stackListJSON.trimmingCharacters(in: .whitespacesAndNewlines).dropLast()) + "," + """
      {"id":"stack-failed","name":"Failed Backup","template":false,"tags":[],"info":{"server_name":"Home Server","swarm_name":"","state":"failed","status":"failed","services":[]}}]
      """
  }

  static let stackDetailJSON = """
  {"_id":"stack-home","name":"Home Services","description":"Core services for the home lab","template":false,"tags":["production"],"info":{"missing_files":[],"deployed_project_name":"home-services","deployed_hash":"c124a98","latest_hash":"d833fb2","latest_services":[{"service_name":"web","container_name":"home-web-1","image":"ghcr.io/example/home-web:2.4"},{"service_name":"database","container_name":"home-db-1","image":"postgres:17"}]},"config":{"server_id":"server-home","swarm_id":"","project_name":"home-services","file_paths":["compose.yaml"],"linked_repo":"","repo":"example/home-services","branch":"main","auto_pull":true,"poll_for_updates":true,"auto_update":false,"files_on_host":false,"file_contents":"","run_directory":"stacks/home","env_file_path":".env","environment":"LOG_LEVEL=info","git_provider":"github.com","git_https":true,"git_account":"","commit":"","clone_path":"","reclone":false,"additional_env_files":[{"path":"production.env","track":true}],"config_files":[{"path":"web.conf","services":["web"],"requires":"Restart"}],"run_build":false,"destroy_before_deploy":false,"auto_update_all_services":false,"auto_update_skip_services":["database"],"ignore_services":["migration"],"send_alerts":true,"registry_provider":"ghcr.io","registry_account":"","extra_args":[],"build_extra_args":[],"compose_cmd_wrapper":"","compose_cmd_wrapper_include":[],"skip_secret_interp":false,"webhook_enabled":true,"webhook_force_deploy":false,"webhook_secret":"","pre_deploy":{"path":"","command":"","shell_mode":false},"post_deploy":{"path":"","command":"","shell_mode":false}}}
  """

  static let containersJSON = """
  [{"id":"container-web","server_id":"server-home","server_name":"Home Server","name":"home-web-1","image":"ghcr.io/example/home-web:2.4","image_id":"sha256:abc","state":"running","status":"Up 12 hours","networks":["proxy","backend"],"created":1789940400,"size_rw":12582912,"size_root_fs":268435456,"network_mode":"proxy","ports":[{"IP":"0.0.0.0","PrivatePort":8080,"PublicPort":443,"Type":"tcp"}],"volumes":["/srv/home/config:/app/config"],"stats":{"name":"home-web-1","cpu_perc":2.8,"mem_perc":12.4,"mem_usage":"126MiB / 1GiB","net_io":"18.4MB / 6.7MB","block_io":"42.1MB / 8.2MB","pids":14}},{"id":"container-db","server_id":"server-home","server_name":"Home Server","name":"home-db-1","image":"postgres:17","state":"running","status":"Up 12 hours","networks":["backend"],"network_mode":"backend","ports":[],"volumes":["home-db:/var/lib/postgresql/data"],"stats":{"name":"home-db-1","cpu_perc":1.2,"mem_perc":18.7,"mem_usage":"191MiB / 1GiB","net_io":"4.2MB / 9.1MB","block_io":"84.5MB / 31.2MB","pids":9}}]
  """

  static let mixedServerContainersJSON = """
  [{"id":"container-paused","server_id":"server-home","server_name":"Home Server","name":"paused-demo","state":"paused","status":"Paused","networks":[]},
   {"id":"container-stopped","server_id":"server-home","server_name":"Home Server","name":"stopped-demo","state":"exited","status":"Exited","networks":[]}]
  """

  static var containerOverviewJSON: String {
    String(containersJSON.trimmingCharacters(in: .whitespacesAndNewlines).dropLast()) + "," + """
      {"id":"container-failed","server_id":"server-home","server_name":"Home Server","name":"home-worker-1","image":"ghcr.io/example/worker:1.0","state":"unhealthy","status":"Unhealthy","networks":[],"ports":[],"volumes":[]}]
      """
  }

  static let webContainerJSON = """
  {"id":"container-web","server_id":"server-home","server_name":"Home Server","name":"home-web-1","image":"ghcr.io/example/home-web:2.4","image_id":"sha256:abc","state":"running","status":"Up 12 hours","networks":["proxy","backend"],"created":1789940400,"size_rw":12582912,"size_root_fs":268435456,"network_mode":"proxy","ports":[{"IP":"0.0.0.0","PrivatePort":8080,"PublicPort":443,"Type":"tcp"}],"volumes":["/srv/home/config:/app/config"],"stats":{"name":"home-web-1","cpu_perc":2.8,"mem_perc":12.4,"mem_usage":"126MiB / 1GiB","net_io":"18.4MB / 6.7MB","block_io":"42.1MB / 8.2MB","pids":14}}
  """

  static let servicesJSON = """
  [{"stack_id":"stack-home","stack_name":"Home Services","service":"web","image":"ghcr.io/example/home-web:2.4","state":"running","container":\(webContainerJSON)},{"stack_id":"stack-home","stack_name":"Home Services","service":"database","image":"postgres:17","state":"running","container":{"id":"container-db","server_id":"server-home","server_name":"Home Server","name":"home-db-1","image":"postgres:17","state":"running","status":"Up 12 hours","networks":["backend"],"network_mode":"backend","ports":[],"volumes":["home-db:/var/lib/postgresql/data"],"stats":{"name":"home-db-1","cpu_perc":1.2,"mem_perc":18.7,"mem_usage":"191MiB / 1GiB","net_io":"4.2MB / 9.1MB","block_io":"84.5MB / 31.2MB","pids":9}}}]
  """

  static let logJSON = """
  {"stage":"container_log","command":"docker logs","stdout":"2026-09-21T09:38:14Z Server started on port 8080\\n2026-09-21T09:38:15Z Connected to database\\n2026-09-21T09:39:02Z GET /health 200 4ms\\n2026-09-21T09:40:17Z GET /api/status 200 12ms\\n2026-09-21T09:41:03Z Background sync completed","stderr":"","success":true,"start_ts":1789983494,"end_ts":1789983663}
  """

  static let alertsJSON = """
  {"alerts":[
    {"_id":"alert-disk","ts":1789983663000,"resolved":false,"level":"WARNING","target":{"type":"Server","id":"server-home"},"data":{"type":"ServerDisk","data":{"name":"Home Server","message":"Disk space is running low"}}},
    {"_id":"alert-service","ts":1789983363000,"resolved":false,"level":"CRITICAL","target":{"type":"Stack","id":"stack-home"},"data":{"type":"ServiceHealth","data":{"name":"Home Services","message":"Web service health check failed"}}}
  ],"next_page":null}
  """

  static let updatesJSON = """
  {"updates":[
    {"id":"update-deploy","operation":"DeployStack","start_ts":1789983063000,"success":true,"username":"System","target":{"type":"Stack","id":"stack-home"},"status":"Complete"},
    {"id":"update-pull","operation":"PullImage","start_ts":1789982763000,"success":true,"username":"System","target":{"type":"Stack","id":"stack-home"},"status":"Complete"}
  ],"next_page":null}
  """
}

private extension String {
  var dropArray: String {
    String(dropFirst().dropLast())
  }
}

private final class ScreenshotDemoURLProtocol: URLProtocol, @unchecked Sendable {
  private static let state = DemoState()

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let data = Self.bodyData(from: request)
    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let requestType = object?["type"] as? String ?? ""
    let json = Self.responseJSON(for: requestType, body: object)
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

  private static func responseJSON(for type: String, body: [String: Any]?) -> String {
    switch type {
    case "ListServers": ScreenshotDemo.serverListResponseJSON
    case "GetServer": state.serverJSON
    case "UpdateServer": state.updateServer(body)
    case "GetServerState": "{\"status\":\"Ok\"}"
    case "GetSystemStats": ScreenshotDemo.systemStatsJSON
    case "GetHistoricalServerStats": ScreenshotDemo.historyJSON
    case "ListStacks": ScreenshotDemo.screen == "stack-list"
      ? ScreenshotDemo.stackOverviewJSON : ScreenshotDemo.stackListJSON
    case "GetStack": state.stackJSON
    case "UpdateStack": state.updateStack(body)
    case "ListStackServices": ScreenshotDemo.servicesJSON
    case "ListAllContainers", "ListContainers": switch ScreenshotDemo.screen {
      case "container-list": ScreenshotDemo.containerOverviewJSON
      case "server-mixed": ScreenshotDemo.mixedServerContainersJSON
      default: ScreenshotDemo.containersJSON
    }
    case "GetStackLog", "GetContainerLog": ScreenshotDemo.logJSON
    case "ListAlerts": ScreenshotDemo.alertsJSON
    case "ListUpdates": ScreenshotDemo.updatesJSON
    default: "{\"_id\":\"demo-update\",\"success\":true,\"status\":\"Complete\"}"
    }
  }

  private final class DemoState: @unchecked Sendable {
    private let lock = NSLock()
    private var serverConfigOverrides: [String: Any] = [:]
    private var stackConfigOverrides: [String: Any] = [:]

    var serverJSON: String {
      lock.lock(); defer { lock.unlock() }
      guard var payload = try? JSONSerialization.jsonObject(with: Data(ScreenshotDemo.serverDetailResponseJSON.utf8)) as? [String: Any],
            var config = payload["config"] as? [String: Any] else { return ScreenshotDemo.serverDetailResponseJSON }
      config.merge(serverConfigOverrides) { _, saved in saved }
      payload["config"] = config
      guard let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8) else { return ScreenshotDemo.serverDetailResponseJSON }
      return json
    }

    var stackJSON: String {
      lock.lock(); defer { lock.unlock() }
      guard var payload = try? JSONSerialization.jsonObject(with: Data(ScreenshotDemo.stackDetailJSON.utf8)) as? [String: Any],
            var config = payload["config"] as? [String: Any] else { return ScreenshotDemo.stackDetailJSON }
      config.merge(stackConfigOverrides) { _, saved in saved }
      payload["config"] = config
      guard let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8) else { return ScreenshotDemo.stackDetailJSON }
      return json
    }

    func updateServer(_ body: [String: Any]?) -> String {
      lock.lock()
      if let config = (body?["params"] as? [String: Any])?["config"] as? [String: Any] {
        serverConfigOverrides.merge(config) { _, saved in saved }
      }
      lock.unlock()
      return serverJSON
    }

    func updateStack(_ body: [String: Any]?) -> String {
      lock.lock()
      if let config = (body?["params"] as? [String: Any])?["config"] as? [String: Any] {
        stackConfigOverrides.merge(config) { _, saved in saved }
      }
      lock.unlock()
      return stackJSON
    }
  }
}

#if os(iOS) || os(macOS)
struct ScreenshotDemoRootView: View {
  @StateObject private var liveUpdates = KomodoLiveUpdateController(initialStatus: .live)
  @StateObject private var appSettings = AppSettings()
  @StateObject private var notificationInbox = NotificationInboxStore(
    clientFactory: { _, _ in ScreenshotDemo.makeClient() }
  )
  @State private var selectedTab = ScreenshotDemo.screen.hasPrefix("server-")
    ? "server" : ScreenshotDemo.screen.replacingOccurrences(of: "-list", with: "")

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("title.servers", systemImage: "server.rack", value: "server") {
        demoNavigation { serverDetail }
      }
      Tab("title.stacks", systemImage: "square.stack.3d.up.fill", value: "stack") {
        demoNavigation { stackScreen }
      }
      Tab("title.containers", systemImage: "shippingbox.fill", value: "container") {
        demoNavigation { containerScreen }
      }
      Tab("title.notifications", systemImage: "bell.fill", value: "notifications") {
        demoNavigation {
          NotificationInboxView(
            store: notificationInbox, profile: ScreenshotDemo.profile,
            keychainStore: .shared, appSettings: appSettings
          )
        }
      }
      Tab("settings.title", systemImage: "gearshape.fill", value: "settings") {
        NavigationStack { SettingsView(settings: appSettings) }
      }
    }
    .environmentObject(liveUpdates)
    .preferredColorScheme(ScreenshotDemo.colorScheme)
  }

  private func demoNavigation<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    NavigationStack {
      content()
        .toolbar {
#if os(iOS)
          ToolbarItem(placement: .topBarLeading) {
            Button("action.back", systemImage: "chevron.backward") {}
          }
#endif
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

  @ViewBuilder private var stackScreen: some View {
    if ScreenshotDemo.screen == "stack-list" {
      StackListView(
        profile: ScreenshotDemo.profile,
        keychainStore: .shared,
        appSettings: appSettings
      )
    } else {
      StackDetailView(
        summary: ScreenshotDemo.stackSummary,
        profile: ScreenshotDemo.profile,
        keychainStore: .shared,
        appSettings: appSettings
      )
    }
  }

  @ViewBuilder private var containerScreen: some View {
    if ScreenshotDemo.screen == "container-list" {
      ContainerListView(
        profile: ScreenshotDemo.profile,
        keychainStore: .shared,
        appSettings: appSettings
      )
    } else {
      ContainerDetailView(
        container: ScreenshotDemo.containerSummary,
        profile: ScreenshotDemo.profile,
        keychainStore: .shared,
        appSettings: appSettings
      )
    }
  }
}
#endif
#endif
