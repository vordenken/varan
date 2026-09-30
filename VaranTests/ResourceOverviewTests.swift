import XCTest
@testable import Varan

final class ResourceOverviewTests: XCTestCase {
  func testCountsKeepInactiveAndTransitionalResourcesOutOfProblemCount() {
    let counts = ResourceOverviewCounts(states: [
      "running", "healthy", "failed", "ERROR", "unhealthy", "dead", "down",
      "stopped", "exited", "paused", "created", "restarting", "deploying", "removing", "unknown",
    ])

    XCTAssertEqual(counts.total, 15)
    XCTAssertEqual(counts.active, 2)
    XCTAssertEqual(counts.problems, 5)
  }

  func testProblemFilterUsesSameCategoryAsOverviewCounts() {
    for state in ["failed", "error", "unhealthy", "dead", "down"] {
      XCTAssertEqual(ResourceStateCategory(state), .attention)
    }
    XCTAssertEqual(ResourceStateCategory(" restarting "), .transitioning)
    XCTAssertEqual(ResourceStateCategory("exited"), .stopped)
  }

  func testScreenshotOverviewFixturesDecode() throws {
    let stacks = try JSONDecoder().decode(
      [StackListItem].self,
      from: Data(ScreenshotDemo.stackOverviewJSON.utf8)
    )
    let containers = try JSONDecoder().decode(
      [ContainerListItem].self,
      from: Data(ScreenshotDemo.containerOverviewJSON.utf8)
    )

    XCTAssertEqual(stacks.count, 2)
    XCTAssertEqual(containers.count, 3)
  }
}
