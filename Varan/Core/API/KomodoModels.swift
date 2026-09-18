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

  enum CodingKeys: String, CodingKey {
    case serverID = "server_id"
    case swarmID = "swarm_id"
    case projectName = "project_name"
    case filePaths = "file_paths"
    case linkedRepo = "linked_repo"
    case repository = "repo"
    case branch
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
  }

  init() {
    serverID = ""
    swarmID = ""
    projectName = ""
    filePaths = []
    linkedRepo = ""
    repository = ""
    branch = ""
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
  }
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
    case (true, true): String(localized: "label.noLogOutput")
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