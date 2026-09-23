import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsTitle() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["title"].waitForExistence(timeout: 5))
    }
}
