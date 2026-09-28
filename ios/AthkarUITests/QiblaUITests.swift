import XCTest

/// القبلة in أخرى. The simulator has no compass, so the dial stays north-up and the bearing is given in degrees.
final class QiblaUITests: DeckTestCase {
    private func openQibla() {
        app.buttons["tab.other"].tap()
        let row = app.buttons["other.qibla"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
    }

    /// Without a location the section sends the user to أوقات الصلاة; with Riyadh it gives about 244° and the distance.
    func testBearingFromTheStoredLocation() {
        launch()
        openQibla()
        let setLocation = app.buttons["qibla.setLocation"]
        XCTAssertTrue(setLocation.waitForExistence(timeout: 3))
        setLocation.tap()

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

        app.buttons["header.back"].tap()
        XCTAssertTrue(app.buttons["other.qibla"].waitForExistence(timeout: 3))
        XCTAssertTrue((app.buttons["other.qibla"].value as? String ?? "").contains("من الشمال"))
        app.buttons["other.qibla"].tap()

        let bearing = app.descendants(matching: .any)["qibla.bearing"]
        XCTAssertTrue(bearing.waitForExistence(timeout: 3))
        XCTAssertTrue(bearing.label.contains("٢٤٤°") || bearing.label.contains("٢٤٣°"), bearing.label)
        XCTAssertTrue(app.staticTexts["qibla.status"].label.contains("من الشمال"), app.staticTexts["qibla.status"].label)
        XCTAssertTrue(app.staticTexts["المسافة إلى الكعبة"].exists || app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "كم")).count > 0)
    }
}
