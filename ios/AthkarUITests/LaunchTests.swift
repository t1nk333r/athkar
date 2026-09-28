import XCTest

final class LaunchTests: XCTestCase {
    /// A fresh launch shows the prayer row in the header, not the title.
    @MainActor
    func testLaunchShowsPrayerRow() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-data"]
        app.launch()
        XCTAssertTrue(app.buttons["home.prayerRow"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["title"].exists)
    }
}
