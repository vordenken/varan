import Foundation

// Read-only snapshots preserve omitted fields rather than applying editor defaults.
// Sensitive contents are reduced to presence during decoding and never retained.
struct StackConfigurationDetails: Decodable, Equatable, Sendable {
  var serverID: String?
  var swarmID: String?
  var links: ConfigurationStringList?
  var projectName: String?
  var filesOnHost: Bool?
  var runDirectory: String?
  var filePaths: ConfigurationStringList?
  var fileContents: ProtectedConfigurationContent?
  var envFilePath: String?
  var environment: ProtectedConfigurationContent?
  var skipSecretInterpolation: Bool?
  var linkedRepo: String?
  var repository: String?
  var gitProvider: String?
  var gitAccount: String?
  var gitHTTPS: Bool?
  var branch: String?
  var commit: String?
  var clonePath: String?
  var reclone: Bool?
  var autoPull: Bool?
  var runBuild: Bool?
  var destroyBeforeDeploy: Bool?
  var pollForUpdates: Bool?
  var autoUpdate: Bool?
  var autoUpdateAllServices: Bool?
  var autoUpdateSkipServices: ConfigurationStringList?
  var ignoreServices: ConfigurationStringList?
  var sendAlerts: Bool?
  var registryProvider: String?
  var registryAccount: String?
  var extraArgs: ProtectedConfigurationContent?
  var buildExtraArgs: ProtectedConfigurationContent?
  var composeCommandWrapper: ProtectedConfigurationContent?
  var composeCommandWrapperInclude: ConfigurationStringList?
  var webhookEnabled: Bool?
  var webhookForceDeploy: Bool?
  var webhookSecret: ProtectedConfigurationContent?
  var additionalEnvFiles: [ConfigurationEnvFile]?
  var configFiles: [ConfigurationFileDependency]?
  var preDeploy: ConfigurationCommand?
  var postDeploy: ConfigurationCommand?

  private enum CodingKeys: String, CodingKey {
    case serverID = "server_id"
    case swarmID = "swarm_id"
    case links
    case projectName = "project_name"
    case filesOnHost = "files_on_host"
    case runDirectory = "run_directory"
    case filePaths = "file_paths"
    case fileContents = "file_contents"
    case envFilePath = "env_file_path"
    case environment
    case skipSecretInterpolation = "skip_secret_interp"
    case linkedRepo = "linked_repo"
    case repository = "repo"
    case gitProvider = "git_provider"
    case gitAccount = "git_account"
    case gitHTTPS = "git_https"
    case branch
    case commit
    case clonePath = "clone_path"
    case reclone
    case autoPull = "auto_pull"
    case runBuild = "run_build"
    case destroyBeforeDeploy = "destroy_before_deploy"
    case pollForUpdates = "poll_for_updates"
    case autoUpdate = "auto_update"
    case autoUpdateAllServices = "auto_update_all_services"
    case autoUpdateSkipServices = "auto_update_skip_services"
    case ignoreServices = "ignore_services"
    case sendAlerts = "send_alerts"
    case registryProvider = "registry_provider"
    case registryAccount = "registry_account"
    case extraArgs = "extra_args"
    case buildExtraArgs = "build_extra_args"
    case composeCommandWrapper = "compose_cmd_wrapper"
    case composeCommandWrapperInclude = "compose_cmd_wrapper_include"
    case webhookEnabled = "webhook_enabled"
    case webhookForceDeploy = "webhook_force_deploy"
    case webhookSecret = "webhook_secret"
    case additionalEnvFiles = "additional_env_files"
    case configFiles = "config_files"
    case preDeploy = "pre_deploy"
    case postDeploy = "post_deploy"
  }
}

struct ServerConfigurationDetails: Decodable, Equatable, Sendable {
  var links: ConfigurationStringList?
  var address: String?
  var externalAddress: String?
  var region: String?
  var enabled: Bool?
  var insecureTLS: Bool?
  var autoRotateKeys: Bool?
  var passkey: ProtectedConfigurationContent?
  var statsMonitoring: Bool?
  var ignoreMounts: ConfigurationStringList?
  var autoPrune: Bool?
  var sendUnreachableAlerts: Bool?
  var sendCPUAlerts: Bool?
  var sendMemoryAlerts: Bool?
  var sendDiskAlerts: Bool?
  var sendVersionMismatchAlerts: Bool?
  var cpuWarning: Double?
  var cpuCritical: Double?
  var memoryWarning: Double?
  var memoryCritical: Double?
  var diskWarning: Double?
  var diskCritical: Double?
  var maintenanceWindows: [ConfigurationMaintenanceWindow]?

  private enum CodingKeys: String, CodingKey {
    case links
    case address
    case externalAddress = "external_address"
    case region
    case enabled
    case insecureTLS = "insecure_tls"
    case autoRotateKeys = "auto_rotate_keys"
    case passkey
    case statsMonitoring = "stats_monitoring"
    case ignoreMounts = "ignore_mounts"
    case autoPrune = "auto_prune"
    case sendUnreachableAlerts = "send_unreachable_alerts"
    case sendCPUAlerts = "send_cpu_alerts"
    case sendMemoryAlerts = "send_mem_alerts"
    case sendDiskAlerts = "send_disk_alerts"
    case sendVersionMismatchAlerts = "send_version_mismatch_alerts"
    case cpuWarning = "cpu_warning"
    case cpuCritical = "cpu_critical"
    case memoryWarning = "mem_warning"
    case memoryCritical = "mem_critical"
    case diskWarning = "disk_warning"
    case diskCritical = "disk_critical"
    case maintenanceWindows = "maintenance_windows"
  }
}

struct ProtectedConfigurationContent: Decodable, Equatable, Sendable {
  let isConfigured: Bool

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let contents = try? container.decode(String.self) {
      isConfigured = !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } else {
      let arguments = try container.decode([String].self)
      isConfigured = arguments.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
  }
}

struct ConfigurationStringList: Decodable, Equatable, Sendable {
  let values: [String]

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let text = try? container.decode(String.self) {
      values = text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    } else {
      values = try container.decode([String].self)
    }
  }
}

struct ConfigurationEnvFile: Decodable, Equatable, Sendable {
  let path: String
  let track: Bool

  private enum CodingKeys: String, CodingKey { case path, track }

  init(from decoder: Decoder) throws {
    if let path = try? decoder.singleValueContainer().decode(String.self) {
      self.path = path
      track = true
    } else {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try container.decode(String.self, forKey: .path)
      track = try container.decodeIfPresent(Bool.self, forKey: .track) ?? true
    }
  }
}

struct ConfigurationFileDependency: Decodable, Equatable, Sendable {
  let path: String
  let services: ConfigurationStringList?
  let requires: String

  private enum CodingKeys: String, CodingKey { case path, services, requires, service, req }

  init(from decoder: Decoder) throws {
    if let path = try? decoder.singleValueContainer().decode(String.self) {
      self.path = path
      services = nil
      requires = "None"
    } else {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      path = try container.decode(String.self, forKey: .path)
      services = try container.decodeIfPresent(ConfigurationStringList.self, forKey: .services)
        ?? container.decodeIfPresent(ConfigurationStringList.self, forKey: .service)
      let requirement = try container.decodeIfPresent(String.self, forKey: .requires)
        ?? container.decodeIfPresent(String.self, forKey: .req) ?? "None"
      switch requirement.lowercased() {
      case "redeploy": requires = "Redeploy"
      case "restart": requires = "Restart"
      case "none": requires = "None"
      default: requires = requirement
      }
    }
  }
}

struct ConfigurationCommand: Decodable, Equatable, Sendable {
  var path: String?
  var command: ProtectedConfigurationContent?
  var shellMode: Bool?

  private enum CodingKeys: String, CodingKey {
    case path, command
    case shellMode = "shell_mode"
  }
}

struct ConfigurationMaintenanceWindow: Decodable, Equatable, Sendable {
  var name: String?
  var description: String?
  var scheduleType: String?
  var dayOfWeek: String?
  var date: String?
  var hour: Int?
  var minute: Int?
  var durationMinutes: Int?
  var timezone: String?
  var enabled: Bool?

  private enum CodingKeys: String, CodingKey {
    case name, description, date, hour, minute, timezone, enabled
    case scheduleType = "schedule_type"
    case dayOfWeek = "day_of_week"
    case durationMinutes = "duration_minutes"
  }
}

extension StackConfigurationDetails {
  var composeSourceLocalizationKey: String {
    if filesOnHost == true { return "configuration.source.host" }
    guard filesOnHost == false else { return "configuration.value.unavailable" }
    if fileContents?.isConfigured == true { return "configuration.source.inline" }
    guard fileContents != nil else { return "configuration.value.unavailable" }
    if let linkedRepo, !linkedRepo.isEmpty { return "configuration.source.linkedRepo" }
    guard linkedRepo != nil else { return "configuration.value.unavailable" }
    if let repository, !repository.isEmpty { return "configuration.source.git" }
    // Partial API responses must not masquerade as an unconfigured source.
    if filesOnHost != nil, fileContents != nil, linkedRepo != nil, repository != nil {
      return "configuration.source.unconfigured"
    }
    return "configuration.value.unavailable"
  }
}
