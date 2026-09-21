import Combine
import Foundation

enum DefaultResourceSection: String, CaseIterable, Identifiable, Sendable {
  case servers
  case stacks
  case containers

  var id: Self { self }

  var title: String {
    switch self {
    case .servers: String(localized: "title.servers")
    case .stacks: String(localized: "title.stacks")
    case .containers: String(localized: "title.containers")
    }
  }
}

enum LogRefreshInterval: Int, CaseIterable, Identifiable, Sendable {
  case twoSeconds = 2
  case fiveSeconds = 5
  case tenSeconds = 10
  case thirtySeconds = 30

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .twoSeconds: String(localized: "settings.interval.twoSeconds")
    case .fiveSeconds: String(localized: "settings.interval.fiveSeconds")
    case .tenSeconds: String(localized: "settings.interval.tenSeconds")
    case .thirtySeconds: String(localized: "settings.interval.thirtySeconds")
    }
  }
}

@MainActor
final class AppSettings: ObservableObject {
  private enum Key {
    static let liveUpdatesEnabled = "settings.liveUpdatesEnabled"
    static let metricsAutoRefresh = "settings.metricsAutoRefresh"
    static let metricsRefreshInterval = "settings.metricsRefreshInterval"
    static let logsAutoRefresh = "settings.logsAutoRefresh"
    static let logRefreshInterval = "settings.logRefreshInterval"
    static let logsFollowLatest = "settings.logsFollowLatest"
    static let defaultResourceSection = "settings.defaultResourceSection"

    static let all = [
      liveUpdatesEnabled,
      metricsAutoRefresh,
      metricsRefreshInterval,
      logsAutoRefresh,
      logRefreshInterval,
      logsFollowLatest,
      defaultResourceSection,
    ]
  }

  @Published var liveUpdatesEnabled: Bool {
    didSet { defaults.set(liveUpdatesEnabled, forKey: Key.liveUpdatesEnabled) }
  }
  @Published var metricsAutoRefresh: Bool {
    didSet { defaults.set(metricsAutoRefresh, forKey: Key.metricsAutoRefresh) }
  }
  @Published var metricsRefreshInterval: MetricsRefreshInterval {
    didSet { defaults.set(metricsRefreshInterval.rawValue, forKey: Key.metricsRefreshInterval) }
  }
  @Published var logsAutoRefresh: Bool {
    didSet { defaults.set(logsAutoRefresh, forKey: Key.logsAutoRefresh) }
  }
  @Published var logRefreshInterval: LogRefreshInterval {
    didSet { defaults.set(logRefreshInterval.rawValue, forKey: Key.logRefreshInterval) }
  }
  @Published var logsFollowLatest: Bool {
    didSet { defaults.set(logsFollowLatest, forKey: Key.logsFollowLatest) }
  }
  @Published var defaultResourceSection: DefaultResourceSection {
    didSet { defaults.set(defaultResourceSection.rawValue, forKey: Key.defaultResourceSection) }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    liveUpdatesEnabled = Self.bool(
      forKey: Key.liveUpdatesEnabled,
      defaultValue: true,
      defaults: defaults
    )
    metricsAutoRefresh = Self.bool(
      forKey: Key.metricsAutoRefresh,
      defaultValue: true,
      defaults: defaults
    )
    metricsRefreshInterval = MetricsRefreshInterval(
      rawValue: defaults.integer(forKey: Key.metricsRefreshInterval)
    ) ?? .fifteenSeconds
    logsAutoRefresh = Self.bool(
      forKey: Key.logsAutoRefresh,
      defaultValue: true,
      defaults: defaults
    )
    logRefreshInterval = LogRefreshInterval(
      rawValue: defaults.integer(forKey: Key.logRefreshInterval)
    ) ?? .fiveSeconds
    logsFollowLatest = Self.bool(
      forKey: Key.logsFollowLatest,
      defaultValue: true,
      defaults: defaults
    )
    defaultResourceSection = DefaultResourceSection(
      rawValue: defaults.string(forKey: Key.defaultResourceSection) ?? ""
    ) ?? .stacks
  }

  func reset() {
    Key.all.forEach(defaults.removeObject(forKey:))
    liveUpdatesEnabled = true
    metricsAutoRefresh = true
    metricsRefreshInterval = .fifteenSeconds
    logsAutoRefresh = true
    logRefreshInterval = .fiveSeconds
    logsFollowLatest = true
    defaultResourceSection = .stacks
  }

  private static func bool(
    forKey key: String,
    defaultValue: Bool,
    defaults: UserDefaults
  ) -> Bool {
    defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
  }
}
