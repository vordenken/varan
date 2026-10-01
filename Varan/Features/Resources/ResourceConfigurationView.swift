import SwiftUI

struct ConfigurationValueRow: View {
  let title: LocalizedStringKey
  let value: String

  init(_ title: LocalizedStringKey, _ value: String?) {
    self.title = title
    self.value = value.map { $0.isEmpty ? String(localized: "configuration.value.unset") : $0 }
      ?? String(localized: "configuration.value.unavailable")
  }

  init(_ title: LocalizedStringKey, _ value: Bool?) {
    self.init(title, value.map { String(localized: $0 ? "configuration.value.yes" : "configuration.value.no") })
  }

  init(_ title: LocalizedStringKey, _ value: Double?) {
    self.init(title, value.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " %" })
  }

  init(_ title: LocalizedStringKey, _ value: ConfigurationStringList?) {
    self.init(title, value.map { $0.values.joined(separator: "\n") })
  }

  init(_ title: LocalizedStringKey, _ value: ProtectedConfigurationContent?) {
    self.init(title, value.map {
      String(localized: $0.isConfigured ? "configuration.value.protected" : "configuration.value.unset")
    })
  }

  var body: some View {
    LabeledContent(title) {
      Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct StackConfigurationSection: View {
  let configuration: StackConfigurationDetails
  var serverName: String? = nil

  var body: some View {
    Section("section.configuration") {
      LabeledContent("configuration.source") {
        Text(LocalizedStringKey(configuration.composeSourceLocalizationKey))
      }
      DisclosureGroup("configuration.group.target") {
        ConfigurationValueRow("configuration.field.serverID", serverName ?? configuration.serverID)
        ConfigurationValueRow("configuration.field.swarmID", configuration.swarmID)
        ConfigurationValueRow("configuration.field.projectName", configuration.projectName)
        ConfigurationValueRow("configuration.field.links", configuration.links)
      }
      .accessibilityIdentifier("stack-configuration-target")
      DisclosureGroup("configuration.group.files") {
        ConfigurationValueRow("configuration.field.filesOnHost", configuration.filesOnHost)
        ConfigurationValueRow("configuration.field.runDirectory", configuration.runDirectory)
        ConfigurationValueRow("configuration.field.filePaths", configuration.filePaths)
        ConfigurationValueRow("configuration.field.fileContents", configuration.fileContents)
        ConfigurationValueRow("configuration.field.envFilePath", configuration.envFilePath)
        ConfigurationValueRow("configuration.field.environment", configuration.environment)
        ConfigurationValueRow("configuration.field.skipSecretInterpolation", configuration.skipSecretInterpolation)
        DisclosureGroup("configuration.field.additionalEnvFiles") {
          if let files = configuration.additionalEnvFiles {
            if files.isEmpty { Text("configuration.value.unset").foregroundStyle(.secondary) }
            ForEach(Array(files.enumerated()), id: \.offset) { _, file in
              ConfigurationValueRow("configuration.field.path", file.path)
              ConfigurationValueRow("configuration.field.track", file.track)
            }
          } else { Text("configuration.value.unavailable").foregroundStyle(.secondary) }
        }
        DisclosureGroup("configuration.field.configFiles") {
          if let files = configuration.configFiles {
            if files.isEmpty { Text("configuration.value.unset").foregroundStyle(.secondary) }
            ForEach(Array(files.enumerated()), id: \.offset) { _, file in
              ConfigurationValueRow("configuration.field.path", file.path)
              ConfigurationValueRow("configuration.field.services", file.services?.values.joined(separator: ", ") ?? "")
              ConfigurationValueRow("configuration.field.requires", localizedConfigurationOption(file.requires, prefix: "configuration.requires"))
            }
          } else { Text("configuration.value.unavailable").foregroundStyle(.secondary) }
        }
      }
      .accessibilityIdentifier("stack-configuration-files")
      DisclosureGroup("configuration.group.git") {
        ConfigurationValueRow("configuration.field.linkedRepo", configuration.linkedRepo)
        ConfigurationValueRow("configuration.field.repository", configuration.repository)
        ConfigurationValueRow("configuration.field.gitProvider", configuration.gitProvider)
        ConfigurationValueRow("configuration.field.gitAccount", configuration.gitAccount)
        ConfigurationValueRow("configuration.field.gitHTTPS", configuration.gitHTTPS)
        ConfigurationValueRow("configuration.field.branch", configuration.branch)
        ConfigurationValueRow("configuration.field.commit", configuration.commit)
        ConfigurationValueRow("configuration.field.clonePath", configuration.clonePath)
        ConfigurationValueRow("configuration.field.reclone", configuration.reclone)
      }
      DisclosureGroup("configuration.group.deployment") {
        ConfigurationValueRow("configuration.field.autoPull", configuration.autoPull)
        ConfigurationValueRow("configuration.field.runBuild", configuration.runBuild)
        ConfigurationValueRow("configuration.field.destroyBeforeDeploy", configuration.destroyBeforeDeploy)
        ConfigurationValueRow("configuration.field.pollForUpdates", configuration.pollForUpdates)
        ConfigurationValueRow("configuration.field.autoUpdate", configuration.autoUpdate)
        ConfigurationValueRow("configuration.field.autoUpdateAllServices", configuration.autoUpdateAllServices)
        ConfigurationValueRow("configuration.field.autoUpdateSkipServices", configuration.autoUpdateSkipServices)
        ConfigurationValueRow("configuration.field.ignoreServices", configuration.ignoreServices)
        ConfigurationValueRow("configuration.field.sendAlerts", configuration.sendAlerts)
        ConfigurationValueRow("configuration.field.registryProvider", configuration.registryProvider)
        ConfigurationValueRow("configuration.field.registryAccount", configuration.registryAccount)
        ConfigurationValueRow("configuration.field.extraArgs", configuration.extraArgs)
        ConfigurationValueRow("configuration.field.buildExtraArgs", configuration.buildExtraArgs)
        ConfigurationValueRow("configuration.field.composeCommandWrapper", configuration.composeCommandWrapper)
        ConfigurationValueRow("configuration.field.composeCommandWrapperInclude", configuration.composeCommandWrapperInclude)
        ConfigurationCommandGroup(title: "configuration.group.preDeploy", command: configuration.preDeploy)
        ConfigurationCommandGroup(title: "configuration.group.postDeploy", command: configuration.postDeploy)
      }
      DisclosureGroup("configuration.group.webhooks") {
        ConfigurationValueRow("configuration.field.webhookEnabled", configuration.webhookEnabled)
        ConfigurationValueRow("configuration.field.webhookForceDeploy", configuration.webhookForceDeploy)
        ConfigurationValueRow("configuration.field.webhookSecret", configuration.webhookSecret)
      }
    }
  }
}

struct ServerConfigurationView: View {
  let configuration: ServerConfigurationDetails

  var body: some View {
    List {
      Section("configuration.group.connection") {
        ConfigurationValueRow("configuration.field.address", configuration.address)
        ConfigurationValueRow("configuration.field.externalAddress", configuration.externalAddress)
        ConfigurationValueRow("configuration.field.region", configuration.region)
        ConfigurationValueRow("configuration.field.links", configuration.links)
        ConfigurationValueRow("configuration.field.enabled", configuration.enabled)
        ConfigurationValueRow("configuration.field.insecureTLS", configuration.insecureTLS)
        ConfigurationValueRow("configuration.field.autoRotateKeys", configuration.autoRotateKeys)
        ConfigurationValueRow("configuration.field.passkey", configuration.passkey)
      }
      Section("configuration.group.monitoring") {
        ConfigurationValueRow("configuration.field.statsMonitoring", configuration.statsMonitoring)
        ConfigurationValueRow("configuration.field.ignoreMounts", configuration.ignoreMounts)
        ConfigurationValueRow("configuration.field.autoPrune", configuration.autoPrune)
      }
      Section("configuration.group.alerts") {
        ConfigurationValueRow("configuration.field.sendUnreachableAlerts", configuration.sendUnreachableAlerts)
        ConfigurationValueRow("configuration.field.sendCPUAlerts", configuration.sendCPUAlerts)
        ConfigurationValueRow("configuration.field.sendMemoryAlerts", configuration.sendMemoryAlerts)
        ConfigurationValueRow("configuration.field.sendDiskAlerts", configuration.sendDiskAlerts)
        ConfigurationValueRow("configuration.field.sendVersionMismatchAlerts", configuration.sendVersionMismatchAlerts)
        ConfigurationValueRow("configuration.field.cpuWarning", configuration.cpuWarning)
        ConfigurationValueRow("configuration.field.cpuCritical", configuration.cpuCritical)
        ConfigurationValueRow("configuration.field.memoryWarning", configuration.memoryWarning)
        ConfigurationValueRow("configuration.field.memoryCritical", configuration.memoryCritical)
        ConfigurationValueRow("configuration.field.diskWarning", configuration.diskWarning)
        ConfigurationValueRow("configuration.field.diskCritical", configuration.diskCritical)
      }
      Section("configuration.group.maintenance") {
        if let windows = configuration.maintenanceWindows {
          if windows.isEmpty { Text("configuration.value.unset").foregroundStyle(.secondary) }
          ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
            ConfigurationValueRow("configuration.field.name", window.name)
            ConfigurationValueRow("configuration.field.description", window.description)
            ConfigurationValueRow("configuration.field.enabled", window.enabled)
            ConfigurationValueRow("configuration.field.scheduleType", window.scheduleType.map {
              localizedConfigurationOption($0, prefix: "configuration.schedule")
            })
            ConfigurationValueRow("configuration.field.dayOfWeek", window.dayOfWeek.map(localizedMaintenanceDay))
            ConfigurationValueRow("configuration.field.date", window.date)
            ConfigurationValueRow("configuration.field.time", startTime(window))
            ConfigurationValueRow("configuration.field.duration", window.durationMinutes.map { $0.formatted() })
            ConfigurationValueRow("configuration.field.timezone", window.timezone.map {
              $0.isEmpty ? String(localized: "configuration.value.coreTimezone") : $0
            })
          }
        } else { Text("configuration.value.unavailable").foregroundStyle(.secondary) }
      }
    }
    .accessibilityIdentifier("server-configuration-list")
    .navigationTitle("title.configuration")
  }

  private func startTime(_ window: ConfigurationMaintenanceWindow) -> String? {
    guard let hour = window.hour, let minute = window.minute else { return nil }
    return String(format: "%02d:%02d", hour, minute)
  }
}

private struct ConfigurationCommandGroup: View {
  let title: LocalizedStringKey
  let command: ConfigurationCommand?

  var body: some View {
    DisclosureGroup(title) {
      ConfigurationValueRow("configuration.field.path", command?.path)
      ConfigurationValueRow("configuration.field.command", command?.command)
      ConfigurationValueRow("configuration.field.shellMode", command?.shellMode)
    }
  }
}

private func localizedConfigurationOption(_ value: String, prefix: String) -> String {
  let key = "\(prefix).\(value)"
  let localized = String(localized: String.LocalizationValue(key))
  return localized == key ? value : localized
}

private func localizedMaintenanceDay(_ day: String) -> String {
  let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
  guard let index = names.firstIndex(of: day.lowercased()) else { return day }
  return DateFormatter().weekdaySymbols[index]
}
