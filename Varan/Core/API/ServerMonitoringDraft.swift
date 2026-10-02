import Foundation

struct ServerMonitoringDraft: Equatable, Sendable {
  let original: ServerConfigurationDetails
  var statsMonitoring: Bool?
  var ignoreMountsText: String?

  init(original: ServerConfigurationDetails? = nil) {
    var defaults = ServerConfigurationDetails()
    defaults.statsMonitoring = true
    defaults.ignoreMounts = ConfigurationStringList(values: [])
    self.original = original ?? defaults
    statsMonitoring = self.original.statsMonitoring
    ignoreMountsText = self.original.ignoreMounts?.values.joined(separator: "\n")
  }

  private var mounts: [String]? {
    guard let originalMounts = original.ignoreMounts?.values, let ignoreMountsText else { return nil }
    if ignoreMountsText == originalMounts.joined(separator: "\n") { return originalMounts }
    return ignoreMountsText.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }

  private var mountsChanged: Bool {
    guard let old = original.ignoreMounts?.values, let mounts else { return false }
    return old != mounts
  }

  var validationMessageKey: String? {
    guard mountsChanged, let mounts, let ignoreMountsText else { return nil }
    let lineBreaks = CharacterSet(charactersIn: "\r\n")
    if ignoreMountsText.unicodeScalars.contains(where: {
      CharacterSet.controlCharacters.contains($0) && !lineBreaks.contains($0)
    }) { return "server.monitoring.validation.characters" }
    if Set(mounts).count != mounts.count { return "server.monitoring.validation.duplicates" }
    return nil
  }

  var changedFields: [String] {
    var keys: [String] = []
    if let old = original.statsMonitoring, let statsMonitoring, old != statsMonitoring {
      keys.append("field.statsMonitoring")
    }
    if mountsChanged { keys.append("configuration.field.ignoreMounts") }
    return keys.map { String(localized: String.LocalizationValue($0)) }
  }

  func apply(to patch: inout ServerConfigPatch) {
    guard validationMessageKey == nil else { return }
    if let old = original.statsMonitoring, let statsMonitoring, old != statsMonitoring {
      patch.statsMonitoring = statsMonitoring
    }
    if mountsChanged { patch.ignoreMounts = mounts }
  }
}