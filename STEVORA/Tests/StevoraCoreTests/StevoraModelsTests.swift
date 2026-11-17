import XCTest
@testable import StevoraCore

final class StevoraModelsTests: XCTestCase {
    func testLocalizedNavigation() {
        XCTAssertEqual(StevoraSection.climate.title(language: .bulgarian), "Климат")
        XCTAssertEqual(StevoraSection.settings.title(language: .english), "Settings")
    }

    func testServerValidation() {
        XCTAssertNotNil(StevoraServer(address: "https://example.com:8123"))
        XCTAssertNil(StevoraServer(address: "javascript:alert(1)"))
        XCTAssertNil(StevoraServer(address: "https://user:password@example.com"))
        XCTAssertNil(StevoraServer(address: "https://example.com?token=secret"))
    }

    func testAPIPath() {
        let server = StevoraServer(address: "https://example.com")!
        XCTAssertEqual(server.apiURL(path: "/api/states")?.absoluteString, "https://example.com/api/states")
        XCTAssertNil(server.apiURL(path: "https://evil.example/api/states"))
    }
}
