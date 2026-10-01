import Foundation

struct StackDetail: Decodable, Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let description: String
  let template: Bool
  let tags: [String]
  let info: StackInfo
  let config: StackConfig

  private enum CodingKeys: String, CodingKey {
    case id = "_id"
    case name
    case description
    case template
    case tags
    case info
    case config
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(KomodoResourceID.self, forKey: .id).value
    name = try container.decode(String.self, forKey: .name)
    description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    template = try container.decodeIfPresent(Bool.self, forKey: .template) ?? false
    tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    info = try container.decodeIfPresent(StackInfo.self, forKey: .info) ?? StackInfo()
    config = try container.decodeIfPresent(StackConfig.self, forKey: .config) ?? StackConfig()
  }
}

struct StackConfig: Decodable, Equatable, Sendable {
  let serverID: String
  let swarmID: String
  let projectName: String
  let filePaths: [String]
  let linkedRepo: String
  let repository: String
  let branch: String
  let autoPull: Bool
  let pollForUpdates: Bool
  let autoUpdate: Bool

  enum CodingKeys: String, CodingKey {
    case serverID = "server_id"
    case swarmID = "swarm_id"
    case projectName = "project_name"
    case filePaths = "file_paths"
    case linkedRepo = "linked_repo"
    case repository = "repo"
    case branch
    case autoPull = "auto_pull"
    case pollForUpdates = "poll_for_updates"
    case autoUpdate = "auto_update"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    serverID = try container.decodeIfPresent(String.self, forKey: .serverID) ?? ""
    swarmID = try container.decodeIfPresent(String.self, forKey: .swarmID) ?? ""
    projectName = try container.decodeIfPresent(String.self, forKey: .projectName) ?? ""
    filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths) ?? []
    linkedRepo = try container.decodeIfPresent(String.self, forKey: .linkedRepo) ?? ""
    repository = try container.decodeIfPresent(String.self, forKey: .repository) ?? ""
    branch = try container.decodeIfPresent(String.self, forKey: .branch) ?? ""
    autoPull = try container.decodeIfPresent(Bool.self, forKey: .autoPull) ?? false
    pollForUpdates = try container.decodeIfPresent(Bool.self, forKey: .pollForUpdates) ?? false
    autoUpdate = try container.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? false
  }

  init() {
    serverID = ""
    swarmID = ""
    projectName = ""
    filePaths = []
    linkedRepo = ""
    repository = ""
    branch = ""
    autoPull = false
    pollForUpdates = false
    autoUpdate = false
  }
}

struct StackInfo: Decodable, Equatable, Sendable {
  let missingFiles: [String]
  let deployedProjectName: String?
  let deployedHash: String?
  let latestHash: String?
  let latestServices: [StackServiceNames]

  enum CodingKeys: String, CodingKey {
    case missingFiles = "missing_files"
    case deployedProjectName = "deployed_project_name"
    case deployedHash = "deployed_hash"
    case latestHash = "latest_hash"
    case latestServices = "latest_services"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    missingFiles = try container.decodeIfPresent([String].self, forKey: .missingFiles) ?? []
    deployedProjectName = try container.decodeIfPresent(String.self, forKey: .deployedProjectName)
    deployedHash = try container.decodeIfPresent(String.self, forKey: .deployedHash)
    latestHash = try container.decodeIfPresent(String.self, forKey: .latestHash)
    latestServices =
      try container.decodeIfPresent([StackServiceNames].self, forKey: .latestServices) ?? []
  }

  init() {
    missingFiles = []
    deployedProjectName = nil
    deployedHash = nil
    latestHash = nil
    latestServices = []
  }
}

struct StackServiceNames: Decodable, Equatable, Sendable {
  let serviceName: String
  let containerName: String
  let image: String

  enum CodingKeys: String, CodingKey {
    case serviceName = "service_name"
    case containerName = "container_name"
    case image
  }
}

private struct KomodoResourceID: Decodable {
  let value: String

  private enum CodingKeys: String, CodingKey {
    case value = "$oid"
  }

  init(from decoder: Decoder) throws {
    if let value = try? decoder.singleValueContainer().decode(String.self) {
      self.value = value
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    value = try container.decode(String.self, forKey: .value)
  }
}

struct StackService: Decodable, Equatable, Identifiable, Sendable {
  let stackID: String
  let stackName: String
  let service: String
  let image: String
  let container: ContainerListItem?
  let state: String

  var id: String { service }

  enum CodingKeys: String, CodingKey {
    case stackID = "stack_id"
    case stackName = "stack_name"
    case service
    case image
    case container
    case state
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    stackID = try container.decodeIfPresent(String.self, forKey: .stackID) ?? ""
    stackName = try container.decodeIfPresent(String.self, forKey: .stackName) ?? ""
    service = try container.decode(String.self, forKey: .service)
    image = try container.decodeIfPresent(String.self, forKey: .image) ?? ""
    self.container = try container.decodeIfPresent(ContainerListItem.self, forKey: .container)
    state = try container.decodeIfPresent(String.self, forKey: .state) ?? "Unknown"
  }
}

struct ContainerListItem: Decodable, Equatable, Identifiable, Sendable {
  let id: String?
  let serverID: String?
  let serverName: String?
  let name: String
  let image: String?
  let imageID: String?
  let state: String
  let status: String?
  let networks: [String]
  let created: Int64?
  let sizeRW: Int64?
  let sizeRootFS: Int64?
  let networkMode: String?
  let ports: [ContainerPort]
  let volumes: [String]
  let stats: ContainerStats?

  enum CodingKeys: String, CodingKey {
    case id
    case serverID = "server_id"
    case serverName = "server_name"
    case name
    case image
    case imageID = "image_id"
    case state
    case status
    case networks
    case created
    case sizeRW = "size_rw"
    case sizeRootFS = "size_root_fs"
    case networkMode = "network_mode"
    case ports
    case volumes
    case stats
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id)
    serverID = try container.decodeIfPresent(String.self, forKey: .serverID)
    serverName = try container.decodeIfPresent(String.self, forKey: .serverName)
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    image = try container.decodeIfPresent(String.self, forKey: .image)
    imageID = try container.decodeIfPresent(String.self, forKey: .imageID)
    state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
    status = try container.decodeIfPresent(String.self, forKey: .status)
    networks = try container.decodeIfPresent([String].self, forKey: .networks) ?? []
    created = try container.decodeIfPresent(Int64.self, forKey: .created)
    sizeRW = try container.decodeIfPresent(Int64.self, forKey: .sizeRW)
    sizeRootFS = try container.decodeIfPresent(Int64.self, forKey: .sizeRootFS)
    networkMode = try container.decodeIfPresent(String.self, forKey: .networkMode)
    ports = try container.decodeIfPresent([ContainerPort].self, forKey: .ports) ?? []
    volumes = try container.decodeIfPresent([String].self, forKey: .volumes) ?? []
    stats = try container.decodeIfPresent(ContainerStats.self, forKey: .stats)
  }
}

struct ContainerPort: Decodable, Equatable, Sendable {
  let ip: String?
  let privatePort: Int
  let publicPort: Int?
  let type: String

  enum CodingKeys: String, CodingKey {
    case ip = "IP"
    case privatePort = "PrivatePort"
    case publicPort = "PublicPort"
    case type = "Type"
  }
}

struct ContainerStats: Decodable, Equatable, Sendable {
  let name: String
  let cpuPercent: Double
  let memoryPercent: Double
  let memoryUsage: String
  let networkIO: String
  let blockIO: String
  let processCount: Int
  let availableFields: Set<String>

  var cpuCoreEquivalent: Double {
    cpuPercent / 100
  }

  var parsedMemoryUsage: ContainerMemoryUsage? {
    let components = memoryUsage.split(separator: "/", maxSplits: 1).map(String.init)
    guard components.count == 2,
          let usedBytes = Self.bytes(from: components[0]),
          let limitBytes = Self.bytes(from: components[1]) else {
      return nil
    }
    return ContainerMemoryUsage(usedBytes: usedBytes, limitBytes: limitBytes)
  }

  enum CodingKeys: String, CodingKey {
    case name
    case dockerName = "Name"
    case cpuPercent = "cpu_perc"
    case dockerCPUPercent = "CPUPerc"
    case memoryPercent = "mem_perc"
    case dockerMemoryPercent = "MemPerc"
    case memoryUsage = "mem_usage"
    case dockerMemoryUsage = "MemUsage"
    case networkIO = "net_io"
    case dockerNetworkIO = "NetIO"
    case blockIO = "block_io"
    case dockerBlockIO = "BlockIO"
    case processCount = "pids"
    case dockerProcessCount = "PIDs"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    availableFields = Set([
      ("cpu_perc", [.cpuPercent, .dockerCPUPercent]),
      ("mem_perc", [.memoryPercent, .dockerMemoryPercent]),
      ("mem_usage", [.memoryUsage, .dockerMemoryUsage]),
      ("net_io", [.networkIO, .dockerNetworkIO]),
      ("block_io", [.blockIO, .dockerBlockIO]),
      ("pids", [.processCount, .dockerProcessCount]),
    ].compactMap { field, keys in
      keys.contains { key in
        container.contains(key) && (try? container.decodeNil(forKey: key)) == false
      } ? field : nil
    })
    name = try container.decodeIfPresent(String.self, forKey: .name)
      ?? container.decodeIfPresent(String.self, forKey: .dockerName)
      ?? ""
    cpuPercent = Self.percentage(in: container, keys: [.cpuPercent, .dockerCPUPercent])
    memoryPercent = Self.percentage(
      in: container,
      keys: [.memoryPercent, .dockerMemoryPercent]
    )
    memoryUsage = try container.decodeIfPresent(String.self, forKey: .memoryUsage)
      ?? container.decodeIfPresent(String.self, forKey: .dockerMemoryUsage)
      ?? ""
    networkIO = try container.decodeIfPresent(String.self, forKey: .networkIO)
      ?? container.decodeIfPresent(String.self, forKey: .dockerNetworkIO)
      ?? ""
    blockIO = try container.decodeIfPresent(String.self, forKey: .blockIO)
      ?? container.decodeIfPresent(String.self, forKey: .dockerBlockIO)
      ?? ""
    processCount = Self.integer(in: container, keys: [.processCount, .dockerProcessCount])
  }

  private static func percentage(
    in container: KeyedDecodingContainer<CodingKeys>,
    keys: [CodingKeys]
  ) -> Double {
    for key in keys {
      if let value = try? container.decode(Double.self, forKey: key) {
        return value
      }
      if let value = try? container.decode(String.self, forKey: key) {
        return Double(value.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) ?? 0
      }
    }
    return 0
  }

  private static func integer(
    in container: KeyedDecodingContainer<CodingKeys>,
    keys: [CodingKeys]
  ) -> Int {
    for key in keys {
      if let value = try? container.decode(Int.self, forKey: key) {
        return value
      }
      if let value = try? container.decode(String.self, forKey: key),
         let integer = Int(value) {
        return integer
      }
    }
    return 0
  }

  private static func bytes(from value: String) -> Int64? {
    let normalized = value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
      .replacingOccurrences(of: " ", with: "")
    let units: [(suffix: String, multiplier: Double)] = [
      ("TIB", 1_099_511_627_776), ("TB", 1_000_000_000_000),
      ("GIB", 1_073_741_824), ("GB", 1_000_000_000),
      ("MIB", 1_048_576), ("MB", 1_000_000),
      ("KIB", 1_024), ("KB", 1_000), ("B", 1)
    ]

    for unit in units where normalized.hasSuffix(unit.suffix) {
      let numberText = normalized.dropLast(unit.suffix.count)
      guard let number = Double(numberText) else { return nil }
      return Int64(number * unit.multiplier)
    }

    guard let number = Double(normalized) else { return nil }
    return Int64(number)
  }
}

struct ContainerMemoryUsage: Equatable, Sendable {
  let usedBytes: Int64
  let limitBytes: Int64

  static func aggregate(_ stats: [ContainerStats]) -> ContainerMemoryUsage? {
    let values = stats.compactMap(\.parsedMemoryUsage)
    guard !values.isEmpty, values.count == stats.count else { return nil }
    return ContainerMemoryUsage(
      usedBytes: values.reduce(0) { $0 + $1.usedBytes },
      limitBytes: values.reduce(0) { $0 + $1.limitBytes }
    )
  }

  var percentage: Double? {
    guard limitBytes > 0 else { return nil }
    return Double(usedBytes) / Double(limitBytes) * 100
  }

  var formatted: String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.countStyle = .memory
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return "\(formatter.string(fromByteCount: usedBytes)) / \(formatter.string(fromByteCount: limitBytes))"
  }
}

struct ServerListItem: Decodable, Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let template: Bool
  let tags: [String]
  let info: ServerListItemInfo
}

struct ServerListItemInfo: Decodable, Equatable, Sendable {
  let state: KomodoServerState
  let version: String?
  let error: String?
  let stats: MinimalSystemStats?
  let region: String
  let address: String?
  let externalAddress: String?
  let publicIP: String?

  enum CodingKeys: String, CodingKey {
    case state
    case version
    case error = "err"
    case stats
    case region
    case address
    case externalAddress = "external_address"
    case publicIP = "public_ip"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    state = try container.decodeIfPresent(KomodoServerState.self, forKey: .state) ?? .unknown("")
    version = try container.decodeIfPresent(String.self, forKey: .version)
    error = try container.decodeIfPresent(String.self, forKey: .error)
    stats = try container.decodeIfPresent(MinimalSystemStats.self, forKey: .stats)
    region = try container.decodeIfPresent(String.self, forKey: .region) ?? ""
    address = try container.decodeIfPresent(String.self, forKey: .address)
    externalAddress = try container.decodeIfPresent(String.self, forKey: .externalAddress)
    publicIP = try container.decodeIfPresent(String.self, forKey: .publicIP)
  }
}

enum KomodoServerState: Decodable, Equatable, Sendable {
  case ok
  case notOk
  case disabled
  case unknown(String)

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    switch value.lowercased() {
    case "ok": self = .ok
    case "notok", "not_ok", "not ok": self = .notOk
    case "disabled": self = .disabled
    default: self = .unknown(value)
    }
  }
}

struct ServerStateResponse: Decodable, Equatable, Sendable {
  let status: KomodoServerState
}

struct MinimalSystemStats: Decodable, Equatable, Sendable {
  let cpuPercent: Double
  let memoryUsedGB: Double
  let memoryTotalGB: Double
  let availableFields: Set<String>

  enum CodingKeys: String, CodingKey, CaseIterable {
    case cpuPercent = "cpu_perc"
    case memoryUsedGB = "mem_used_gb"
    case memoryTotalGB = "mem_total_gb"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    availableFields = Set(CodingKeys.allCases.compactMap { key in
      container.contains(key) && (try? container.decodeNil(forKey: key)) == false
        ? key.rawValue : nil
    })
    cpuPercent = try container.decodeIfPresent(Double.self, forKey: .cpuPercent) ?? 0
    memoryUsedGB = try container.decodeIfPresent(Double.self, forKey: .memoryUsedGB) ?? 0
    memoryTotalGB = try container.decodeIfPresent(Double.self, forKey: .memoryTotalGB) ?? 0
  }
}

struct ServerDetail: Decodable, Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let description: String
  let tags: [String]
  let info: ServerInfo
  let config: ServerConfig

  private enum CodingKeys: String, CodingKey {
    case id = "_id"
    case name, description, tags, info, config
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(KomodoResourceID.self, forKey: .id).value
    name = try container.decode(String.self, forKey: .name)
    description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    info = try container.decodeIfPresent(ServerInfo.self, forKey: .info) ?? ServerInfo()
    config = try container.decode(ServerConfig.self, forKey: .config)
  }
}

struct ServerInfo: Decodable, Equatable, Sendable {
  let attemptedPublicKey: String?
  let publicKey: String?

  private enum CodingKeys: String, CodingKey {
    case attemptedPublicKey = "attempted_public_key"
    case publicKey = "public_key"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    attemptedPublicKey = try container.decodeIfPresent(String.self, forKey: .attemptedPublicKey)
    publicKey = try container.decodeIfPresent(String.self, forKey: .publicKey)
  }

  init() {
    attemptedPublicKey = nil
    publicKey = nil
  }
}

struct ServerConfig: Decodable, Equatable, Sendable {
  let address: String
  let externalAddress: String
  let region: String
  let enabled: Bool
  let insecureTLS: Bool
  let autoPrune: Bool
  let statsMonitoring: Bool
  let availableFields: Set<String>

  enum CodingKeys: String, CodingKey, CaseIterable {
    case address
    case externalAddress = "external_address"
    case region, enabled
    case insecureTLS = "insecure_tls"
    case autoPrune = "auto_prune"
    case statsMonitoring = "stats_monitoring"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    availableFields = Set(CodingKeys.allCases.compactMap { key in
      container.contains(key) && (try? container.decodeNil(forKey: key)) == false
        ? key.rawValue : nil
    })
    address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
    externalAddress = try container.decodeIfPresent(String.self, forKey: .externalAddress) ?? ""
    region = try container.decodeIfPresent(String.self, forKey: .region) ?? ""
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    insecureTLS = try container.decodeIfPresent(Bool.self, forKey: .insecureTLS) ?? false
    autoPrune = try container.decodeIfPresent(Bool.self, forKey: .autoPrune) ?? false
    statsMonitoring = try container.decodeIfPresent(Bool.self, forKey: .statsMonitoring) ?? true
  }

  init() {
    address = ""; externalAddress = ""; region = ""; enabled = true
    insecureTLS = false; autoPrune = false; statsMonitoring = true
    availableFields = []
  }
}

struct SystemLoadAverage: Decodable, Equatable, Sendable {
  let one: Double
  let five: Double
  let fifteen: Double
}

struct DiskUsage: Decodable, Equatable, Identifiable, Sendable {
  let mount: String
  let fileSystem: String
  let usedGB: Double
  let totalGB: Double
  var id: String { mount }

  enum CodingKeys: String, CodingKey {
    case mount
    case fileSystem = "file_system"
    case usedGB = "used_gb"
    case totalGB = "total_gb"
  }
}

struct SystemStats: Decodable, Equatable, Sendable {
  let cpuPercent: Double
  let loadAverage: SystemLoadAverage
  let memoryUsedGB: Double
  let memoryTotalGB: Double
  let swapUsedGB: Double
  let swapTotalGB: Double
  let disks: [DiskUsage]
  let networkIngressBytes: Int64
  let networkEgressBytes: Int64
  let refreshTimestamp: Int64
  let pollingRate: String
  let availableFields: Set<String>

  enum CodingKeys: String, CodingKey, CaseIterable {
    case cpuPercent = "cpu_perc"
    case loadAverage = "load_average"
    case memoryUsedGB = "mem_used_gb"
    case memoryTotalGB = "mem_total_gb"
    case swapUsedGB = "swap_used_gb"
    case swapTotalGB = "swap_total_gb"
    case disks
    case networkIngressBytes = "network_ingress_bytes"
    case networkEgressBytes = "network_egress_bytes"
    case refreshTimestamp = "refresh_ts"
    case pollingRate = "polling_rate"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    availableFields = Set(
      CodingKeys.allCases.filter { key in
        container.contains(key) && (try? container.decodeNil(forKey: key)) == false
      }.map(\.rawValue)
    )
    cpuPercent = try container.decodeIfPresent(Double.self, forKey: .cpuPercent) ?? 0
    loadAverage = try container.decodeIfPresent(SystemLoadAverage.self, forKey: .loadAverage)
      ?? SystemLoadAverage(one: 0, five: 0, fifteen: 0)
    memoryUsedGB = try container.decodeIfPresent(Double.self, forKey: .memoryUsedGB) ?? 0
    memoryTotalGB = try container.decodeIfPresent(Double.self, forKey: .memoryTotalGB) ?? 0
    swapUsedGB = try container.decodeIfPresent(Double.self, forKey: .swapUsedGB) ?? 0
    swapTotalGB = try container.decodeIfPresent(Double.self, forKey: .swapTotalGB) ?? 0
    disks = try container.decodeIfPresent([DiskUsage].self, forKey: .disks) ?? []
    networkIngressBytes = try container.decodeIfPresent(Int64.self, forKey: .networkIngressBytes) ?? 0
    networkEgressBytes = try container.decodeIfPresent(Int64.self, forKey: .networkEgressBytes) ?? 0
    refreshTimestamp = try container.decodeIfPresent(Int64.self, forKey: .refreshTimestamp) ?? 0
    pollingRate = try container.decodeIfPresent(String.self, forKey: .pollingRate) ?? ""
  }
}

struct ContainerInspection: Decodable, Equatable, Sendable {
  let id: String
  let name: String
  let image: String
  let state: ContainerInspectionState?
  let mounts: [ContainerMount]

  enum CodingKeys: String, CodingKey { case id = "Id"; case name = "Name"; case state = "State"; case mounts = "Mounts"; case config = "Config" }
  enum ConfigKeys: String, CodingKey { case image = "Image" }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    state = try container.decodeIfPresent(ContainerInspectionState.self, forKey: .state)
    mounts = try container.decodeIfPresent([ContainerMount].self, forKey: .mounts) ?? []
    let config = try? container.nestedContainer(keyedBy: ConfigKeys.self, forKey: .config)
    image = (try? config?.decodeIfPresent(String.self, forKey: .image)) ?? ""
  }
}

struct ContainerInspectionState: Decodable, Equatable, Sendable {
  let status: String
  let running: Bool
  let paused: Bool
  let restarting: Bool
  let exitCode: Int
  let error: String

  enum CodingKeys: String, CodingKey {
    case status = "Status"; case running = "Running"; case paused = "Paused"
    case restarting = "Restarting"; case exitCode = "ExitCode"; case error = "Error"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
    running = try container.decodeIfPresent(Bool.self, forKey: .running) ?? false
    paused = try container.decodeIfPresent(Bool.self, forKey: .paused) ?? false
    restarting = try container.decodeIfPresent(Bool.self, forKey: .restarting) ?? false
    exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode) ?? 0
    error = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
  }
}

struct ContainerMount: Decodable, Equatable, Identifiable, Sendable {
  let type: String
  let source: String
  let destination: String
  let readWrite: Bool
  var id: String { destination }
  enum CodingKeys: String, CodingKey { case type = "Type"; case source = "Source"; case destination = "Destination"; case readWrite = "RW" }
}

struct SystemStatsRecord: Decodable, Equatable, Identifiable, Sendable {
  let timestamp: Int64
  let cpuPercent: Double
  let memoryUsedGB: Double
  let memoryTotalGB: Double
  let availableFields: Set<String>
  var id: Int64 { timestamp }

  enum CodingKeys: String, CodingKey, CaseIterable {
    case timestamp = "ts"
    case cpuPercent = "cpu_perc"
    case memoryUsedGB = "mem_used_gb"
    case memoryTotalGB = "mem_total_gb"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    availableFields = Set(CodingKeys.allCases.compactMap { key in
      container.contains(key) && (try? container.decodeNil(forKey: key)) == false
        ? key.rawValue : nil
    })
    timestamp = try container.decodeIfPresent(Int64.self, forKey: .timestamp) ?? 0
    cpuPercent = try container.decodeIfPresent(Double.self, forKey: .cpuPercent) ?? 0
    memoryUsedGB = try container.decodeIfPresent(Double.self, forKey: .memoryUsedGB) ?? 0
    memoryTotalGB = try container.decodeIfPresent(Double.self, forKey: .memoryTotalGB) ?? 0
  }

}

struct HistoricalSystemStatsPage: Decodable, Equatable, Sendable {
  let stats: [SystemStatsRecord]
  let nextPage: Int?

  enum CodingKeys: String, CodingKey {
    case stats
    case nextPage = "next_page"
  }
}

enum MetricFreshness {
  static func measurementDate(for timestamp: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(timestamp) / (timestamp > 10_000_000_000 ? 1_000 : 1))
  }

  static func isStale(
    timestamp: Int64,
    now: Date = .now,
    after threshold: TimeInterval
  ) -> Bool {
    guard timestamp > 0 else { return false }
    return now.timeIntervalSince(measurementDate(for: timestamp)) > threshold
  }
}

struct ServerConfigPatch: Encodable, Equatable, Sendable {
  var address: String? = nil
  var externalAddress: String? = nil
  var region: String? = nil
  var enabled: Bool? = nil
  var insecureTLS: Bool? = nil
  var autoPrune: Bool? = nil
  var statsMonitoring: Bool? = nil

  enum CodingKeys: String, CodingKey {
    case address
    case externalAddress = "external_address"
    case region, enabled
    case insecureTLS = "insecure_tls"
    case autoPrune = "auto_prune"
    case statsMonitoring = "stats_monitoring"
  }
}

struct StackConfigPatch: Encodable, Equatable, Sendable {
  var serverID: String? = nil
  var projectName: String? = nil
  var linkedRepo: String? = nil
  var repository: String? = nil
  var branch: String? = nil
  var autoPull: Bool? = nil
  var pollForUpdates: Bool? = nil
  var autoUpdate: Bool? = nil

  enum CodingKeys: String, CodingKey {
    case serverID = "server_id"
    case projectName = "project_name"
    case linkedRepo = "linked_repo"
    case repository = "repo"
    case branch
    case autoPull = "auto_pull"
    case pollForUpdates = "poll_for_updates"
    case autoUpdate = "auto_update"
  }
}

private struct DynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init(_ stringValue: String) { self.stringValue = stringValue }
  init?(stringValue: String) { self.init(stringValue) }
  init?(intValue: Int) { return nil }
}

struct KomodoLog: Decodable, Equatable, Sendable {
  let stage: String
  let command: String
  let stdout: String
  let stderr: String
  let success: Bool
  let startTimestamp: Int64
  let endTimestamp: Int64

  var combinedOutput: String {
    switch (stdout.isEmpty, stderr.isEmpty) {
    case (false, false): "\(cleanedStandardOutput)\n\n\(String(localized: "label.errorOutput"))\n\(cleanedErrorOutput)"
    case (false, true): cleanedStandardOutput
    case (true, false): cleanedErrorOutput
    case (true, true): ""
    }
  }

  var cleanedStandardOutput: String { stdout.removingANSIControlSequences() }
  var cleanedErrorOutput: String { stderr.removingANSIControlSequences() }

  enum CodingKeys: String, CodingKey {
    case stage
    case command
    case stdout
    case stderr
    case success
    case startTimestamp = "start_ts"
    case endTimestamp = "end_ts"
  }
}

private extension String {
  func removingANSIControlSequences() -> String {
    guard let expression = try? NSRegularExpression(
      pattern: "\u{001B}\\[[0-?]*[ -/]*[@-~]"
    ) else {
      return self
    }
    return expression.stringByReplacingMatches(
      in: self,
      range: NSRange(startIndex..., in: self),
      withTemplate: ""
    )
  }
}

struct KomodoUpdate: Decodable, Equatable, Sendable {
  let id: String
  let success: Bool
  let status: String

  private enum CodingKeys: String, CodingKey {
    case id = "_id"
    case success
    case status
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(KomodoResourceID.self, forKey: .id).value
    success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
    status = try container.decodeIfPresent(String.self, forKey: .status) ?? "Queued"
  }
}

struct KomodoNoticeTarget: Decodable, Equatable, Sendable {
  let type: String
  let id: String
}

struct KomodoAlertPayload: Decodable, Equatable, Sendable {
  struct Detail: Decodable, Equatable, Sendable {
    let name: String?
    let message: String?
    let details: String?
    let service: String?
    let image: String?

    private enum CodingKeys: String, CodingKey {
      case name, message, details, service, image
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      name = try? container.decode(String.self, forKey: .name)
      message = try? container.decode(String.self, forKey: .message)
      details = try? container.decode(String.self, forKey: .details)
      service = try? container.decode(String.self, forKey: .service)
      image = try? container.decode(String.self, forKey: .image)
    }
  }

  let type: String
  let data: Detail?

  private enum CodingKeys: String, CodingKey {
    case type, data
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    type = try container.decode(String.self, forKey: .type)
    data = try? container.decode(Detail.self, forKey: .data)
  }
}

struct KomodoAlert: Decodable, Equatable, Identifiable, Sendable {
  let id: String
  let timestamp: Int64
  let resolved: Bool
  let level: String
  let target: KomodoNoticeTarget
  let data: KomodoAlertPayload
  let resolvedTimestamp: Int64?

  enum CodingKeys: String, CodingKey {
    case id = "_id"
    case timestamp = "ts"
    case resolved, level, target, data
    case resolvedTimestamp = "resolved_ts"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(KomodoResourceID.self, forKey: .id).value
    timestamp = try container.decode(Int64.self, forKey: .timestamp)
    resolved = try container.decode(Bool.self, forKey: .resolved)
    level = try container.decode(String.self, forKey: .level)
    target = try container.decode(KomodoNoticeTarget.self, forKey: .target)
    data = try container.decode(KomodoAlertPayload.self, forKey: .data)
    resolvedTimestamp = try container.decodeIfPresent(Int64.self, forKey: .resolvedTimestamp)
  }
}

struct KomodoAlertPage: Decodable, Equatable, Sendable {
  let alerts: [KomodoAlert]
  let nextPage: Int?

  enum CodingKeys: String, CodingKey {
    case alerts
    case nextPage = "next_page"
  }
}

struct KomodoUpdateListItem: Decodable, Equatable, Identifiable, Sendable {
  let id: String
  let operation: String
  let startTimestamp: Int64
  let success: Bool
  let username: String?
  let target: KomodoNoticeTarget
  let status: String

  enum CodingKeys: String, CodingKey {
    case id, operation, success, username, target, status
    case startTimestamp = "start_ts"
  }

  var actorDisplayName: String? {
    guard let username, !username.isEmpty else { return nil }
    switch username {
    case "000000000000000000000000", "System":
      return String(localized: "notifications.actor.system")
    case "000000000000000000000001", "Procedure":
      return String(localized: "notifications.actor.procedure")
    case "000000000000000000000002", "Action":
      return String(localized: "notifications.actor.action")
    case "000000000000000000000003", "Git Webhook":
      return String(localized: "notifications.actor.gitWebhook")
    case "000000000000000000000004", "Auto Redeploy":
      return String(localized: "notifications.actor.autoRedeploy")
    case "000000000000000000000005", "Resource Sync":
      return String(localized: "notifications.actor.resourceSync")
    case "000000000000000000000006", "Stack Wizard":
      return String(localized: "notifications.actor.stackWizard")
    case "000000000000000000000007", "Build Manager":
      return String(localized: "notifications.actor.buildManager")
    case "000000000000000000000008", "Repo Manager":
      return String(localized: "notifications.actor.repoManager")
    case "unknown":
      return String(localized: "notifications.actor.unknown")
    default:
      return username.range(of: "^[0-9a-fA-F]{24}$", options: .regularExpression) != nil
        ? String(localized: "notifications.actor.unknown") : username
    }
  }
}

struct KomodoUpdatePage: Decodable, Equatable, Sendable {
  let updates: [KomodoUpdateListItem]
  let nextPage: Int?

  enum CodingKeys: String, CodingKey {
    case updates
    case nextPage = "next_page"
  }
}

struct KomodoUpdateDetail: Decodable, Equatable, Sendable {
  struct Stage: Decodable, Equatable, Sendable {
    let stage: String
    let success: Bool
  }

  let id: String
  let operation: String
  let startTimestamp: Int64
  let endTimestamp: Int64?
  let success: Bool
  let status: String
  let target: KomodoNoticeTarget
  let logs: [Stage]

  enum CodingKeys: String, CodingKey {
    case id = "_id"
    case operation, success, status, target, logs
    case startTimestamp = "start_ts"
    case endTimestamp = "end_ts"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(KomodoResourceID.self, forKey: .id).value
    operation = try container.decode(String.self, forKey: .operation)
    startTimestamp = try container.decode(Int64.self, forKey: .startTimestamp)
    endTimestamp = try container.decodeIfPresent(Int64.self, forKey: .endTimestamp)
    success = try container.decode(Bool.self, forKey: .success)
    status = try container.decode(String.self, forKey: .status)
    target = try container.decode(KomodoNoticeTarget.self, forKey: .target)
    logs = try container.decodeIfPresent([Stage].self, forKey: .logs) ?? []
  }
}

struct StackListItem: Decodable, Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let template: Bool
  let tags: [String]
  let info: StackListItemInfo
}

struct StackListItemInfo: Decodable, Equatable, Sendable {
  let serverName: String
  let swarmName: String
  let state: String
  let status: String?
  let services: [StackServiceListItem]

  enum CodingKeys: String, CodingKey {
    case serverName = "server_name"
    case swarmName = "swarm_name"
    case state
    case status
    case services
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    serverName = try container.decodeIfPresent(String.self, forKey: .serverName) ?? ""
    swarmName = try container.decodeIfPresent(String.self, forKey: .swarmName) ?? ""
    state = try container.decodeIfPresent(String.self, forKey: .state) ?? "unknown"
    status = try container.decodeIfPresent(String.self, forKey: .status)
    services = try container.decodeIfPresent([StackServiceListItem].self, forKey: .services) ?? []
  }
}

struct StackServiceListItem: Decodable, Equatable, Sendable {
  let service: String
  let image: String
  let updateAvailable: Bool

  enum CodingKeys: String, CodingKey {
    case service
    case image
    case updateAvailable = "update_available"
  }
}
