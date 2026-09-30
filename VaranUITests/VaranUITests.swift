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
  func testServerEditReloadsCanonicalState() {
    let app = launch(screen: "server")
    openServerEditor(in: app)

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
    XCTAssertTrue(canonicalBranch.waitForExistence(timeout: 10))
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
