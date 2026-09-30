import XCTest
@testable import Varan

@MainActor
final class EditorSaveGateTests: XCTestCase {
  func testConcurrentSaveRunsOnlyOnce() async throws {
    let gate = EditorSaveGate()
    let started = expectation(description: "First save started")
    let first = Task {
      try await gate.perform {
        started.fulfill()
        try await Task.sleep(for: .milliseconds(200))
      }
    }

    await fulfillment(of: [started], timeout: 1)
    XCTAssertTrue(gate.isSaving)
    try await gate.perform { XCTFail("A concurrent save must not run") }
    try await first.value
    XCTAssertFalse(gate.isSaving)
  }

  func testFailedSaveAllowsRetry() async throws {
    let gate = EditorSaveGate()
    enum ExpectedFailure: Error { case failed }

    do {
      try await gate.perform { throw ExpectedFailure.failed }
      XCTFail("The first save should fail")
    } catch ExpectedFailure.failed {
      XCTAssertFalse(gate.isSaving)
    }

    var retried = false
    try await gate.perform { retried = true }
    XCTAssertTrue(retried)
  }
}
