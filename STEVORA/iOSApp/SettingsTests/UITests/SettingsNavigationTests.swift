import XCTest

final class SettingsNavigationTests: XCTestCase {
    private func launch(role: String, language: String = "en") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TEST_ROLE"] = role
        app.launchEnvironment["TEST_LANGUAGE"] = language
        app.launch()
        let tab = app.tabBars.buttons[language == "bg" ? "Настройки" : "Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20))
        tab.tap()
        return app
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAdministratorCanOpenDeviceManagerFromBulgarianSettings() {
        let app = launch(role: "admin", language: "bg")
        let devices = app.buttons["settings.manager.devices"]
        XCTAssertTrue(devices.waitForExistence(timeout: 5))
        snapshot(app, "Admin settings BG")
        devices.tap()
        XCTAssertTrue(app.navigationBars["Устройства"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(devices.exists)
    }

    func testMemberCanSearchEntireInventoryWithoutReceivingWritePermission() {
        let app = launch(role: "member")
        XCTAssertFalse(app.buttons["settings.manager.devices"].exists)
        XCTAssertTrue(app.buttons["settings.routines"].exists)
        snapshot(app, "Personal settings EN")
        app.buttons["settings.routines"].tap()
        app.buttons["settings.catalog.Scene or automation"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("fixture_500")
        let result = app.buttons["settings.choice.scene.fixture_500"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        snapshot(app, "Search by entity ID")
        result.tap()
        let run = app.buttons["Run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertFalse(run.isEnabled)
    }

    func testOfflineAdminHasLocalSettingsWithoutManagement() {
        let app = launch(role: "offline")
        XCTAssertFalse(app.buttons["settings.manager.rooms"].exists)
        app.buttons["settings.location"].tap()
        XCTAssertTrue(app.navigationBars["Location sharing"].exists)
    }
}
