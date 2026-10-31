import XCTest

/// The home header's prayer row: without a location it asks for one; with one it names the next adhan with the time
/// left; it opens أوقات الصلاة, which states the rule behind its «أوقات النهي» notice; the settings toggle brings the
/// title back.
final class HomePrayerRowUITests: DeckTestCase {
    private var row: XCUIElement { app.buttons["home.prayerRow"] }

    func testRowShowsPrayersOpensPrayerTimesAndCanGiveWayToTheTitle() {
        launch()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.label.contains("حدّد موقعك"), row.label)
        XCTAssertFalse(app.staticTexts["title"].exists)

        row.tap()
        XCTAssertTrue(app.buttons["prayer.manual"].waitForExistence(timeout: 3), "the row opens أوقات الصلاة")
        app.buttons["prayer.manual"].tap()
        let lat = app.textFields["prayer.manual.latitude"]
        XCTAssertTrue(lat.waitForExistence(timeout: 3))
        lat.tap()
        lat.typeText("24.71")
        let lon = app.textFields["prayer.manual.longitude"]
        lon.tap()
        lon.typeText("46.68")
        app.buttons["prayer.manual.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["prayer.time.fajr"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["prayer.prohibited"].exists)

        app.buttons["tab.morning"].tap()
        XCTAssertTrue(wait { self.row.label.contains("أذان ") }, row.label)
        XCTAssertFalse(row.label.contains("حدّد موقعك"), row.label)
        // One sentence: the next adhan and the time left in words.
        XCTAssertTrue(row.label.contains(" بعد "), row.label)

        openSettings()
        toggle("settings.homePrayerRow", to: false)
        closeSettings()
        XCTAssertTrue(app.staticTexts["title"].waitForExistence(timeout: 3))
        XCTAssertFalse(row.exists)

        launch(reset: false, answer: nil)
        XCTAssertTrue(app.staticTexts["title"].waitForExistence(timeout: 3), "the choice survives a relaunch")
        openSettings()
        toggle("settings.homePrayerRow", to: true)
        closeSettings()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
    }
}
