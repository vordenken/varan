import XCTest
@testable import Varan

final class ServerAddressTests: XCTestCase {
  func testAddsHTTPSWhenSchemeIsMissing() throws {
    let address = try ServerAddress("komodo.example.com")

    XCTAssertEqual(address.url.absoluteString, "https://komodo.example.com")
  }

  func testAllowsHTTPForPrivateNetwork() throws {
    let address = try ServerAddress("http://192.168.1.20:9120")

    XCTAssertEqual(address.url.absoluteString, "http://192.168.1.20:9120")
  }

  func testRejectsHTTPForRemoteServer() {
    XCTAssertThrowsError(try ServerAddress("http://komodo.example.com")) { error in
      XCTAssertEqual(error as? ServerAddressError, .insecureRemoteHost)
    }
  }

  func testRejectsHTTPForHostnameWithPrivateIPPrefix() {
    for input in ["http://10.example.com", "http://192.168.evil.com", "http://172.16.example.com"] {
      XCTAssertThrowsError(try ServerAddress(input), input) { error in
        XCTAssertEqual(error as? ServerAddressError, .insecureRemoteHost)
      }
    }
  }

  func testAllowsHTTPForPrivate172Network() throws {
    XCTAssertNoThrow(try ServerAddress("http://172.20.0.5:9120"))
    XCTAssertThrowsError(try ServerAddress("http://172.32.0.5:9120"))
  }

  func testRejectsCredentialsInURL() {
    XCTAssertThrowsError(try ServerAddress("https://user:secret@komodo.example.com")) { error in
      XCTAssertEqual(error as? ServerAddressError, .invalid)
    }
  }

  func testRejectsAPIPath() {
    XCTAssertThrowsError(try ServerAddress("https://komodo.example.com/read")) { error in
      XCTAssertEqual(error as? ServerAddressError, .invalid)
    }
  }
}