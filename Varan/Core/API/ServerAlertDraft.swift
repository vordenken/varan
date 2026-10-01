import Foundation

enum ServerAlertSetting: String, CaseIterable, Identifiable, Sendable {
  case unreachable, cpu, memory, disk, versionMismatch
  var id: String { rawValue }
  var localizationKey: String {
    switch self {
    case .unreachable: "configuration.field.sendUnreachableAlerts"
    case .cpu: "configuration.field.sendCPUAlerts"
    case .memory: "configuration.field.sendMemoryAlerts"
    case .disk: "configuration.field.sendDiskAlerts"
    case .versionMismatch: "configuration.field.sendVersionMismatchAlerts"
    }
  }

  func value(in configuration: ServerConfigurationDetails) -> Bool? {
    switch self {
    case .unreachable: configuration.sendUnreachableAlerts
    case .cpu: configuration.sendCPUAlerts
    case .memory: configuration.sendMemoryAlerts
    case .disk: configuration.sendDiskAlerts
    case .versionMismatch: configuration.sendVersionMismatchAlerts
    }
  }

  func apply(_ value: Bool, to patch: inout ServerConfigPatch) {
    switch self {
    case .unreachable: patch.sendUnreachableAlerts = value
    case .cpu: patch.sendCPUAlerts = value
    case .memory: patch.sendMemoryAlerts = value
    case .disk: patch.sendDiskAlerts = value
    case .versionMismatch: patch.sendVersionMismatchAlerts = value
    }
  }
}

enum ServerAlertThreshold: String, CaseIterable, Identifiable, Sendable {
  case cpuWarning, cpuCritical, memoryWarning, memoryCritical, diskWarning, diskCritical
  var id: String { rawValue }
  var localizationKey: String { "configuration.field.\(rawValue)" }
  static let pairs: [(Self, Self)] = [(.cpuWarning, .cpuCritical), (.memoryWarning, .memoryCritical), (.diskWarning, .diskCritical)]

  func value(in configuration: ServerConfigurationDetails) -> Double? {
    switch self {
    case .cpuWarning: configuration.cpuWarning
    case .cpuCritical: configuration.cpuCritical
    case .memoryWarning: configuration.memoryWarning
    case .memoryCritical: configuration.memoryCritical
    case .diskWarning: configuration.diskWarning
    case .diskCritical: configuration.diskCritical
    }
  }

  func apply(_ value: Double, to patch: inout ServerConfigPatch) {
    switch self {
    case .cpuWarning: patch.cpuWarning = value
    case .cpuCritical: patch.cpuCritical = value
    case .memoryWarning: patch.memoryWarning = value
    case .memoryCritical: patch.memoryCritical = value
    case .diskWarning: patch.diskWarning = value
    case .diskCritical: patch.diskCritical = value
    }
  }
}

struct ServerAlertDraft: Equatable, Sendable {
  let original: ServerConfigurationDetails
  var alerts: [ServerAlertSetting: Bool]
  var thresholds: [ServerAlertThreshold: String]

  init(original: ServerConfigurationDetails? = nil) {
    // Creation uses Komodo defaults for display; unchanged defaults are omitted from writes.
    let baseline = original ?? Self.creationDefaults
    self.original = baseline
    alerts = Dictionary(uniqueKeysWithValues: ServerAlertSetting.allCases.compactMap { setting in
      setting.value(in: baseline).map { (setting, $0) }
    })
    thresholds = Dictionary(uniqueKeysWithValues: ServerAlertThreshold.allCases.compactMap { threshold in
      threshold.value(in: baseline).map { (threshold, String($0)) }
    })
  }

  func canEdit(_ threshold: ServerAlertThreshold) -> Bool {
    guard let pair = ServerAlertThreshold.pairs.first(where: { $0.0 == threshold || $0.1 == threshold }) else { return false }
    return pair.0.value(in: original) != nil && pair.1.value(in: original) != nil
  }

  private func value(for threshold: ServerAlertThreshold) -> Double? {
    guard let input = thresholds[threshold] else { return nil }
    // Preserve the exact baseline, including values rendered with scientific notation.
    if let old = threshold.value(in: original), input == String(old) { return old }
    return Self.percentage(input)
  }

  private func hasChanged(_ threshold: ServerAlertThreshold) -> Bool {
    guard canEdit(threshold), thresholds[threshold] != nil else { return false }
    return value(for: threshold) != threshold.value(in: original)
  }

  var validationMessageKey: String? {
    for (warning, critical) in ServerAlertThreshold.pairs where hasChanged(warning) || hasChanged(critical) {
      guard let warningValue = value(for: warning),
            let criticalValue = value(for: critical),
            (0...100).contains(warningValue), (0...100).contains(criticalValue) else {
        return "server.alerts.validation.range"
      }
      if warningValue > criticalValue { return "server.alerts.validation.order" }
    }
    return nil
  }

  var changedFields: [String] {
    let changedAlerts = ServerAlertSetting.allCases.filter {
      guard let old = $0.value(in: original), let new = alerts[$0] else { return false }
      return old != new
    }.map(\.localizationKey)
    return (changedAlerts + ServerAlertThreshold.allCases.filter { hasChanged($0) }.map(\.localizationKey))
      .map { String(localized: String.LocalizationValue($0)) }
  }

  func apply(to patch: inout ServerConfigPatch) {
    guard validationMessageKey == nil else { return }
    for setting in ServerAlertSetting.allCases {
      if let old = setting.value(in: original), let new = alerts[setting], old != new {
        setting.apply(new, to: &patch)
      }
    }
    for threshold in ServerAlertThreshold.allCases where hasChanged(threshold) {
      if let value = value(for: threshold) { threshold.apply(value, to: &patch) }
    }
  }

  // Accept decimal commas and points, without silently accepting grouping or trailing text.
  static func percentage(_ input: String) -> Double? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.range(of: #"^[+-]?(?:[0-9]+(?:[.,][0-9]*)?|[.,][0-9]+)$"#, options: .regularExpression) != nil,
          let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite else { return nil }
    return number
  }

  private static var creationDefaults: ServerConfigurationDetails {
    var configuration = ServerConfigurationDetails()
    configuration.sendUnreachableAlerts = true
    configuration.sendCPUAlerts = true
    configuration.sendMemoryAlerts = true
    configuration.sendDiskAlerts = true
    configuration.sendVersionMismatchAlerts = true
    configuration.cpuWarning = 90
    configuration.cpuCritical = 99
    configuration.memoryWarning = 75
    configuration.memoryCritical = 95
    configuration.diskWarning = 75
    configuration.diskCritical = 95
    return configuration
  }
}
