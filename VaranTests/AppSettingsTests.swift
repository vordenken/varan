import Foundation
import XCTest
@testable import Varan

final class AppSettingsTests: XCTestCase {
  @MainActor
  func testDefaultsPreserveExistingAppBehavior() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)

    XCTAssertTrue(settings.liveUpdatesEnabled)
    XCTAssertTrue(settings.metricsAutoRefresh)
    XCTAssertEqual(settings.metricsRefreshInterval, .fifteenSeconds)
    XCTAssertTrue(settings.logsAutoRefresh)
    XCTAssertEqual(settings.logRefreshInterval, .fiveSeconds)
    XCTAssertTrue(settings.logsFollowLatest)
    XCTAssertEqual(settings.defaultResourceSection, .stacks)
  }

  @MainActor
  func testSettingsPersistAcrossInstances() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    settings.liveUpdatesEnabled = false
    settings.metricsAutoRefresh = false
    settings.metricsRefreshInterval = .oneMinute
    settings.logsAutoRefresh = false
    settings.logRefreshInterval = .thirtySeconds
    settings.logsFollowLatest = false
    settings.defaultResourceSection = .containers

    let restored = AppSettings(defaults: defaults)

    XCTAssertFalse(restored.liveUpdatesEnabled)
    XCTAssertFalse(restored.metricsAutoRefresh)
    XCTAssertEqual(restored.metricsRefreshInterval, .oneMinute)
    XCTAssertFalse(restored.logsAutoRefresh)
    XCTAssertEqual(restored.logRefreshInterval, .thirtySeconds)
    XCTAssertFalse(restored.logsFollowLatest)
    XCTAssertEqual(restored.defaultResourceSection, .containers)
  }

  @MainActor
  func testInvalidStoredValuesUseSafeDefaults() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(-1, forKey: "settings.metricsRefreshInterval")
    defaults.set(999, forKey: "settings.logRefreshInterval")
    defaults.set("unknown", forKey: "settings.defaultResourceSection")

    let settings = AppSettings(defaults: defaults)

    XCTAssertEqual(settings.metricsRefreshInterval, .fifteenSeconds)
    XCTAssertEqual(settings.logRefreshInterval, .fiveSeconds)
    XCTAssertEqual(settings.defaultResourceSection, .stacks)
  }

  @MainActor
  func testResetRestoresDefaultsWithoutTouchingUnrelatedValues() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    settings.liveUpdatesEnabled = false
    settings.metricsRefreshInterval = .oneMinute
    settings.logsFollowLatest = false
    settings.defaultResourceSection = .servers
    defaults.set("preserved", forKey: "unrelated")

    settings.reset()

    XCTAssertTrue(settings.liveUpdatesEnabled)
    XCTAssertEqual(settings.metricsRefreshInterval, .fifteenSeconds)
    XCTAssertTrue(settings.logsFollowLatest)
    XCTAssertEqual(settings.defaultResourceSection, .stacks)
    XCTAssertEqual(defaults.string(forKey: "unrelated"), "preserved")
  }

  private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = "AppSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
  }
}
