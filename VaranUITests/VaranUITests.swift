import XCTest

final class VaranUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testServerDetailAndEditorAreAccessible() {
    let app = launch(screen: "server")
    XCTAssertTrue(app.staticTexts["Home Server"].waitForExistence(timeout: 10))
    let cpuMetric = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "18.7")).firstMatch
    XCTAssertTrue(cpuMetric.waitForExistence(timeout: 10))
    let publicIP = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "203.0.113.10")).firstMatch
    XCTAssertTrue(publicIP.waitForExistence(timeout: 5))
    openServerConfiguration(in: app)
    let warningThreshold = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "CPU warning threshold")
    ).firstMatch
    let list = app.collectionViews.firstMatch
    XCTAssertTrue(list.waitForExistence(timeout: 5))
    for _ in 0..<3 where !warningThreshold.exists { list.swipeUp() }
    XCTAssertTrue(warningThreshold.waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    openServerEditor(in: app)
    XCTAssertTrue(app.otherElements["server-editor-form"].waitForExistence(timeout: 5)
      || app.descendants(matching: .any)["server-editor-form"].exists)
    XCTAssertEqual(app.textFields["server-editor-address-field"].value as? String,
                   "https://192.168.1.10:8120")
    XCTAssertEqual(app.textFields["server-editor-external-address-field"].value as? String,
                   "https://komodo.example.com")
    XCTAssertEqual(app.textFields["server-editor-region-field"].value as? String, "Home Lab")
  }

  @MainActor
  func testServerMonitoringMountValidation() {
    let app = launch(screen: "server")
    defer { app.terminate() }
    openServerMonitoringEditor(in: app)
    let mounts = app.textViews["server-editor-ignore-mounts"]
    XCTAssertEqual(mounts.value as? String, "/mnt/backup")
    mounts.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    let duplicate = "/mnt/cache\n/mnt/cache"
    mounts.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "/mnt/backup".count) + duplicate)
    XCTAssertEqual(mounts.value as? String, duplicate)
    XCTAssertFalse(app.buttons["Review Changes"].isEnabled)
    let replacement = "/mnt/cache\n/Volumes/Backup Drive"
    mounts.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: duplicate.count) + replacement)
    XCTAssertEqual(mounts.value as? String, replacement)
    XCTAssertTrue(app.buttons["Review Changes"].isEnabled)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Server monitoring editor"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testServerMonitoringCanonicalReload() {
    let app = launch(screen: "server")
    defer { app.terminate() }
    openServerMonitoringEditor(in: app)
    let monitoring = app.switches["server-editor-stats-monitoring"].firstMatch
    XCTAssertEqual(monitoring.value as? String, "1")
    monitoring.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    XCTAssertEqual(monitoring.value as? String, "0")
    let mounts = app.textViews["server-editor-ignore-mounts"]
    mounts.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    let replacement = "/mnt/cache"
    mounts.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "/mnt/backup".count) + replacement)
    XCTAssertEqual(mounts.value as? String, replacement)
    app.buttons["Review Changes"].tap()
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ignored disk mounts")).firstMatch.waitForExistence(timeout: 5))
    app.buttons["Save"].tap()
    openServerMonitoringEditor(in: app)
    let savedMounts = app.textViews["server-editor-ignore-mounts"]
    XCTAssertEqual(savedMounts.value as? String, replacement)
    XCTAssertEqual(app.switches["server-editor-stats-monitoring"].firstMatch.value as? String, "0")
    XCTAssertFalse(app.buttons["Review Changes"].isEnabled)
  }

  @MainActor
  func testServerAlertThresholdValidationAndCanonicalReload() {
    let app = launch(screen: "server")
    openServerEditor(in: app)
    let list = app.collectionViews.firstMatch
    let thresholds = app.buttons["server-editor-alert-thresholds"].firstMatch
    for _ in 0..<3 where !thresholds.isHittable { list.swipeUp() }
    XCTAssertTrue(thresholds.waitForExistence(timeout: 5))
    thresholds.tap()
    let warning = app.textFields["server-editor-threshold-cpuWarning"]
    for _ in 0..<3 where !warning.isHittable { list.swipeUp() }
    XCTAssertTrue(warning.waitForExistence(timeout: 5))
    warning.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    let old = warning.value as? String ?? ""
    warning.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "101")
    XCTAssertEqual(warning.value as? String, "101")
    XCTAssertFalse(app.buttons["Review Changes"].isEnabled)
    warning.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "85.5")
    XCTAssertEqual(warning.value as? String, "85.5")
    XCTAssertTrue(app.buttons["Review Changes"].isEnabled)
    app.buttons["Review Changes"].tap()
    let review = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "CPU warning threshold")).firstMatch
    XCTAssertTrue(review.waitForExistence(timeout: 5))
    app.buttons["Save"].tap()

    openServerConfiguration(in: app)
    let canonical = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "CPU warning threshold", "85.5")).firstMatch
    let detailList = app.collectionViews.firstMatch
    for _ in 0..<3 where !canonical.exists { detailList.swipeUp() }
    XCTAssertTrue(canonical.waitForExistence(timeout: 5))
  }

  @MainActor
  func testServerEditReloadsCanonicalState() {
    let app = launch(screen: "server")
    openServerEditor(in: app)

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Native Server editor field appearance"
    attachment.lifetime = .keepAlways
    add(attachment)

    let region = app.textFields["server-editor-region-field"]
    XCTAssertTrue(region.waitForExistence(timeout: 5))
    region.tap()
    let oldValue = region.value as? String ?? ""
    region.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + "Office")
    XCTAssertEqual(region.value as? String, "Office")

    let review = app.buttons["Review Changes"]
    XCTAssertTrue(review.waitForExistence(timeout: 5))
    review.tap()
    let save = app.buttons["Save"]
    XCTAssertTrue(save.waitForExistence(timeout: 5))
    save.tap()

    let canonicalRegion = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Region, Office")
    ).firstMatch
    XCTAssertTrue(canonicalRegion.waitForExistence(timeout: 10))
  }

  @MainActor
  func testServerEditorUsesListAddressWhenDetailOmitsIt() {
    let app = launch(screen: "server-partial")
    openServerEditor(in: app)

    let externalAddress = app.textFields["server-editor-external-address-field"]
    XCTAssertTrue(externalAddress.waitForExistence(timeout: 5))
    XCTAssertEqual(externalAddress.value as? String, "server.example.com")

    let region = app.textFields["server-editor-region-field"]
    region.tap()
    region.typeText("Office")
    XCTAssertTrue(app.buttons["Review Changes"].isEnabled)
  }

  @MainActor
  func testServerActionsMenuGroupsOperationsAndMaintenance() {
    let app = launch(screen: "server")
    let menu = app.buttons["server-actions-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    menu.tap()

    XCTAssertTrue(app.buttons["Restart All Containers"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Pause All Containers"].exists)
    XCTAssertTrue(app.buttons["Stop All Containers"].exists)
    XCTAssertTrue(app.buttons["Prune Buildx Cache"].exists)
    XCTAssertTrue(app.buttons["Prune Docker System"].exists)
    XCTAssertTrue(app.buttons["Delete Server"].exists)

    app.buttons["Prune Buildx Cache"].tap()
    let warning = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Future builds may take longer")
    ).firstMatch
    XCTAssertTrue(warning.waitForExistence(timeout: 5))
  }

  @MainActor
  func testServerActionsMenuReflectsPausedAndStoppedContainers() {
    let app = launch(screen: "server-mixed")
    let menu = app.buttons["server-actions-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    menu.tap()

    XCTAssertTrue(app.buttons["Resume All Containers"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Start All Containers"].exists)
    XCTAssertTrue(app.buttons["Restart All Containers"].exists)
    XCTAssertTrue(app.buttons["Stop All Containers"].exists)
    XCTAssertFalse(app.buttons["Pause All Containers"].exists)
  }

  @MainActor
  func testStackEditorShowsPersistentLabelsForFilledGitFields() {
    let app = launch(screen: "stack")
    let menu = app.buttons["stack-actions-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    menu.tap()
    app.buttons["Edit"].tap()
    let list = app.collectionViews.firstMatch
    let branch = app.textFields["stack-editor-branch-field"]
    for _ in 0..<4 where !branch.exists || !branch.isHittable { list.swipeUp() }
    XCTAssertTrue(branch.waitForExistence(timeout: 5))
    XCTAssertEqual(branch.value as? String, "main")
    XCTAssertTrue(app.staticTexts["Branch"].exists)
    XCTAssertTrue(app.staticTexts["Git branch used to load the Stack’s Compose files."].exists)
    let provider = app.textFields["stack-editor-gitProvider"]
    for _ in 0..<3 where !provider.exists || !provider.isHittable { list.swipeUp() }
    XCTAssertTrue(provider.waitForExistence(timeout: 5))
    XCTAssertEqual(provider.value as? String, "github.com")
    XCTAssertTrue(app.staticTexts["Git provider"].exists)
    XCTAssertTrue(app.staticTexts["Domain of the Git host, for example github.com or your own GitLab server."].exists)
    XCTAssertFalse(app.buttons["Review Changes"].isEnabled)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Filled editor fields with persistent labels"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testStackTargetServerShowsResolvedName() {
    let app = launch(screen: "stack")
    let target = app.buttons["stack-configuration-target"].firstMatch
    let list = app.collectionViews.firstMatch
    XCTAssertTrue(list.waitForExistence(timeout: 10))
    for _ in 0..<3 where !target.exists || !target.isHittable { list.swipeUp() }
    XCTAssertTrue(target.waitForExistence(timeout: 5))
    target.tap()
    let resolved = app.staticTexts.matching(NSPredicate(
      format: "label CONTAINS %@ AND label CONTAINS %@", "Target server", "Home Server"
    )).firstMatch
    XCTAssertTrue(resolved.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts.matching(NSPredicate(
      format: "label CONTAINS %@ AND label CONTAINS %@", "Target server", "server-home"
    )).firstMatch.exists)
  }

  @MainActor
  func testStackDeploymentComparisonExplainsRevisionAndScope() {
    let app = launch(screen: "stack")
    let status = app.descendants(matching: .any)["stack-deployment-status"].firstMatch
    XCTAssertTrue(status.waitForExistence(timeout: 10))
    XCTAssertTrue(status.label.contains("Git revision differs from deployed revision"))
    app.buttons["stack-deployment-details"].firstMatch.tap()
    let deployed = app.staticTexts.matching(NSPredicate(
      format: "label CONTAINS %@ AND label CONTAINS %@", "Deployed Git revision", "c124a98"
    )).firstMatch
    let latest = app.staticTexts.matching(NSPredicate(
      format: "label CONTAINS %@ AND label CONTAINS %@", "Latest Git revision", "d833fb2"
    )).firstMatch
    XCTAssertTrue(deployed.waitForExistence(timeout: 5))
    XCTAssertTrue(latest.waitForExistence(timeout: 5))
    let scope = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Other saved settings and inline Compose")).firstMatch
    let list = app.collectionViews.firstMatch
    for _ in 0..<3 where !scope.exists { list.swipeUp() }
    XCTAssertTrue(scope.waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Concrete deployment revision comparison"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testStackDetailActionsMenuIsAccessible() {
    let app = launch(screen: "stack")
    XCTAssertTrue(app.staticTexts["Home Services"].waitForExistence(timeout: 10))
    let menu = app.buttons["stack-actions-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 5))
    menu.tap()
    XCTAssertTrue(app.buttons["Restart"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testStackEditReloadsCanonicalState() {
    let app = launch(screen: "stack")
    let composeSource = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Git repository")
    ).firstMatch
    XCTAssertTrue(composeSource.waitForExistence(timeout: 10))
    let files = app.buttons["stack-configuration-files"].firstMatch
    XCTAssertTrue(files.waitForExistence(timeout: 5))
    files.tap()
    let directory = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "stacks/home")
    ).firstMatch
    XCTAssertTrue(directory.waitForExistence(timeout: 5))
    let protectedEnvironment = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Configured · contents hidden")
    ).firstMatch
    let list = app.collectionViews.firstMatch
    XCTAssertTrue(list.waitForExistence(timeout: 5))
    for _ in 0..<3 where !protectedEnvironment.exists { list.swipeUp() }
    XCTAssertTrue(protectedEnvironment.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "LOG_LEVEL=info")).firstMatch.exists)
    let menu = app.buttons["stack-actions-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    menu.tap()
    let edit = app.buttons["Edit"]
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    edit.tap()

    let branch = app.textFields["stack-editor-branch-field"]
    XCTAssertTrue(branch.waitForExistence(timeout: 5))
    branch.tap()
    let oldValue = branch.value as? String ?? ""
    branch.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + "stable")
    XCTAssertEqual(branch.value as? String, "stable")

    let review = app.buttons["Review Changes"]
    XCTAssertTrue(review.waitForExistence(timeout: 5))
    review.tap()
    let save = app.buttons["Save"]
    XCTAssertTrue(save.waitForExistence(timeout: 5))
    save.tap()

    let canonicalBranch = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Branch, stable")
    ).firstMatch
    let detailList = app.collectionViews.firstMatch
    XCTAssertTrue(detailList.waitForExistence(timeout: 5))
    for _ in 0..<3 where !canonicalBranch.exists { detailList.swipeDown() }
    XCTAssertTrue(canonicalBranch.waitForExistence(timeout: 10))
  }

  @MainActor
  func testStackComposeHostEditReloadsCanonicalSourceAndPath() {
    let app = launch(screen: "stack")
    let menu = app.buttons["stack-actions-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    menu.tap()
    app.buttons["Edit"].tap()

    let source = app.buttons["stack-editor-source-picker"].firstMatch
    let form = app.collectionViews.firstMatch
    XCTAssertTrue(form.waitForExistence(timeout: 5))
    for _ in 0..<3 where !source.isHittable { form.swipeUp() }
    XCTAssertTrue(source.waitForExistence(timeout: 5))
    source.tap()
    let hostSource = app.buttons["Files on the host"]
    XCTAssertTrue(hostSource.waitForExistence(timeout: 5))
    hostSource.tap()

    let directory = app.textFields["stack-editor-run-directory"]
    XCTAssertTrue(directory.waitForExistence(timeout: 5))
    directory.tap()
    let oldDirectory = directory.value as? String ?? ""
    directory.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldDirectory.count) + "/opt/stacks/home")
    let review = app.buttons["Review Changes"]
    XCTAssertTrue(review.isEnabled)
    review.tap()
    let sourceReview = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Change Compose source from Git repository to Files on the host")
    ).firstMatch
    XCTAssertTrue(sourceReview.waitForExistence(timeout: 5))
    app.buttons["Save"].tap()

    let canonicalSource = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Compose source, Files on the host")
    ).firstMatch
    XCTAssertTrue(canonicalSource.waitForExistence(timeout: 10))
    let files = app.buttons["stack-configuration-files"].firstMatch
    XCTAssertTrue(files.waitForExistence(timeout: 5))
    files.tap()
    let canonicalDirectory = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "/opt/stacks/home")
    ).firstMatch
    XCTAssertTrue(canonicalDirectory.waitForExistence(timeout: 5))
  }

  @MainActor
  func testContainerMenuExposesRestartAction() {
    let app = launch(screen: "container")
    XCTAssertTrue(app.staticTexts["home-web-1"].waitForExistence(timeout: 10))
    let menu = app.buttons["container-actions-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 5))
    menu.tap()
    XCTAssertTrue(app.buttons["Restart"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testContainerLogsAreAccessible() {
    let app = launch(screen: "container")
    XCTAssertTrue(app.staticTexts["home-web-1"].waitForExistence(timeout: 10))
    let menu = app.buttons["container-actions-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 5))
    let logs = app.descendants(matching: .any)["container-logs-link"]
    let list = app.collectionViews.firstMatch
    XCTAssertTrue(list.waitForExistence(timeout: 5))
    for _ in 0..<4 where !logs.isHittable {
      list.swipeUp()
    }
    XCTAssertTrue(logs.waitForExistence(timeout: 5))
    XCTAssertTrue(logs.isHittable)
    logs.tap()
    XCTAssertTrue(app.descendants(matching: .any)["log-search-field"].waitForExistence(timeout: 5))
    let follow = app.buttons["log-follow-toggle"]
    XCTAssertTrue(follow.waitForExistence(timeout: 5))
    let initialLabel = follow.label
    follow.tap()
    XCTAssertNotEqual(follow.label, initialLabel)
    follow.tap()
    XCTAssertEqual(follow.label, initialLabel)
  }

  @MainActor
  func testLogSettingsUseOneRefreshPicker() {
    let app = launch(screen: "settings")
    let picker = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Refresh Logs")
    ).firstMatch
    let form = app.collectionViews.firstMatch
    XCTAssertTrue(form.waitForExistence(timeout: 10))
    for _ in 0..<4 where !picker.isHittable {
      form.swipeUp()
    }
    XCTAssertTrue(picker.isHittable)
    XCTAssertFalse(app.switches["Follow new lines"].exists)
    picker.tap()
    let manual = app.buttons["Manual"]
    XCTAssertTrue(manual.waitForExistence(timeout: 5))
    manual.tap()
    XCTAssertTrue(picker.label.contains("Manual"))
  }

  @MainActor
  func testResourceToolbarOmitsRefreshButton() {
    for screen in ["server", "stack", "container"] {
      let app = launch(screen: screen)
      let status = app.buttons["Live connection active"]
      let refresh = app.buttons["Refresh"]
      XCTAssertTrue(status.waitForExistence(timeout: 10), "Missing status on \(screen)")
      XCTAssertFalse(refresh.exists, "Redundant refresh button on \(screen)")
      app.terminate()
    }
  }

  @MainActor
  func testOverviewsShowCountsAndFilterByMetric() {
    for (screen, total, activeCountValue, active, failed) in [
      ("stack-list", "2", "1", "stack-list-item-stack-home", "stack-list-item-stack-failed"),
      ("container-list", "3", "2", "container-list-item-container-web", "container-list-item-container-failed"),
    ] {
      let app = launch(screen: screen)
      let totalCount = app.buttons["overview-total"]
      let activeCount = app.buttons["overview-active"]
      let problems = app.buttons["overview-problems"]
      XCTAssertTrue(totalCount.waitForExistence(timeout: 10))
      XCTAssertTrue(activeCount.exists)
      XCTAssertTrue(problems.exists)
      XCTAssertTrue(totalCount.label.contains(total))
      XCTAssertTrue(activeCount.label.contains(activeCountValue))
      XCTAssertTrue(problems.label.contains("1"))
      XCTAssertTrue(app.descendants(matching: .any)[active].exists)
      XCTAssertTrue(app.descendants(matching: .any)[failed].exists)

      activeCount.tap()
      XCTAssertTrue(app.descendants(matching: .any)[active].exists)
      XCTAssertFalse(app.descendants(matching: .any)[failed].exists)

      problems.tap()
      XCTAssertTrue(app.descendants(matching: .any)[failed].exists)
      XCTAssertFalse(app.descendants(matching: .any)[active].exists)

      totalCount.tap()
      XCTAssertTrue(app.descendants(matching: .any)[active].exists)
      XCTAssertTrue(app.descendants(matching: .any)[failed].exists)
      app.terminate()
    }
  }

  @MainActor
  func testOverviewSummaryStaysBelowSearchWhenPulledDown() {
    for (screen, firstItem) in [
      ("stack-list", "stack-list-item-stack-home"),
      ("container-list", "container-list-item-container-web"),
    ] {
      let app = launch(screen: screen)
      let summary = app.descendants(matching: .any)["overview-total"]
      let active = app.descendants(matching: .any)["overview-active"]
      let problems = app.buttons["overview-problems"]
      let search = app.searchFields.firstMatch
      let row = app.descendants(matching: .any)[firstItem]
      XCTAssertTrue(summary.waitForExistence(timeout: 10))
      XCTAssertTrue(active.exists)
      XCTAssertTrue(problems.exists)
      XCTAssertTrue(search.exists)
      XCTAssertTrue(row.exists)
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "\(screen) compact overview"
      attachment.lifetime = .keepAlways
      add(attachment)
      XCTAssertGreaterThan(row.frame.minY - summary.frame.maxY, 6)
      let metricsCenter = (summary.frame.midX + active.frame.midX + problems.frame.midX) / 3
      XCTAssertLessThan(abs(metricsCenter - search.frame.midX), 12)
      let spaceAbove = summary.frame.minY - search.frame.maxY
      let spaceBelow = row.frame.minY - summary.frame.maxY
      XCTAssertGreaterThan(spaceAbove, 0)
      XCTAssertLessThan(spaceAbove, 42)
      XCTAssertGreaterThan(spaceBelow, 0)
      XCTAssertLessThan(spaceBelow, 28)

      app.swipeDown()
      XCTAssertGreaterThanOrEqual(summary.frame.minY, search.frame.maxY - 2)
      app.terminate()
    }
  }

  @MainActor
  private func openServerConfiguration(in app: XCUIApplication) {
    let link = app.buttons["server-configuration-link"].firstMatch
    let list = app.collectionViews.firstMatch
    XCTAssertTrue(link.waitForExistence(timeout: 10))
    for _ in 0..<3 where !link.isHittable { list.swipeDown() }
    let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: link)
    wait(for: [enabled], timeout: 10)
    link.tap()
    XCTAssertTrue(app.navigationBars["Configuration"].waitForExistence(timeout: 5))
  }

  @MainActor
  private func openServerMonitoringEditor(in app: XCUIApplication) {
    openServerEditor(in: app)
    XCTAssertTrue(app.textFields["server-editor-address-field"].waitForExistence(timeout: 5))
    let list = app.collectionViews.firstMatch
    let mounts = app.textViews["server-editor-ignore-mounts"]
    for _ in 0..<3 where !mounts.exists || !mounts.isHittable { list.swipeUp() }
    XCTAssertTrue(mounts.waitForExistence(timeout: 5))
    XCTAssertTrue(app.switches["server-editor-stats-monitoring"].firstMatch.exists)
  }

  @MainActor
  private func openServerEditor(in app: XCUIApplication) {
    let menu = app.buttons["server-actions-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    menu.tap()
    let edit = app.buttons["server-edit-button"]
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    edit.tap()
  }

  @MainActor
  private func launch(screen: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "--screenshot-demo", "--screenshot-screen", screen,
      "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
    ]
    app.launch()
    return app
  }
}
