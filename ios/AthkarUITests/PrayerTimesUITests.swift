import XCTest

/// أوقات الصلاة in أخرى, driven with manual coordinates so no permission prompt is involved.
final class PrayerTimesUITests: DeckTestCase {
    private func openPrayerTimes() {
        app.buttons["tab.other"].tap()
        let row = app.buttons["other.prayerTimes"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
    }

    private func enterLocation(_ latitude: String, _ longitude: String) {
        app.buttons["prayer.manual"].tap()
        let lat = app.textFields["prayer.manual.latitude"]
        XCTAssertTrue(lat.waitForExistence(timeout: 3))
        lat.tap()
        lat.typeText(latitude)
        let lon = app.textFields["prayer.manual.longitude"]
        lon.tap()
        lon.typeText(longitude)
        app.buttons["prayer.manual.save"].tap()
    }

    private func time(_ key: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "prayer.time.\(key)").firstMatch
    }

    /// Without a location the section asks for one; manual coordinates (Arabic-Indic digits and «٫») give six times,
    /// a countdown and the location line; days move and return; the Asr school changes Asr; all of it survives a
    /// relaunch.
    func testManualLocationScheduleDaysSettingsAndRelaunch() {
        launch()
        app.buttons["tab.other"].tap()
        XCTAssertTrue(app.buttons["other.prayerTimes"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["other.prayerTimes"].value as? String, "حدّد موقعك لعرض المواقيت")
        app.buttons["other.prayerTimes"].tap()
        XCTAssertTrue(app.buttons["prayer.locate"].waitForExistence(timeout: 3))
        XCTAssertFalse(headerReset.isEnabled, "nothing to reset here")
        XCTAssertFalse(time("fajr").exists)

        enterLocation("٢١٫٤٢", "٣٩٫٨٢")
        XCTAssertTrue(time("fajr").waitForExistence(timeout: 4))
        for key in ["sunrise", "dhuhr", "asr", "maghrib", "isha"] { XCTAssertTrue(time(key).exists, key) }
        XCTAssertTrue(time("fajr").label.hasPrefix("الفجر"), time("fajr").label)
        XCTAssertFalse(time("fajr").label.contains("—"), time("fajr").label)
        XCTAssertTrue(app.descendants(matching: .any)["prayer.countdown"].exists)
        XCTAssertTrue(app.staticTexts["prayer.location"].label.contains("٢١٫٤٢، ٣٩٫٨٢"),
                      app.staticTexts["prayer.location"].label)
        // No method chosen: Umm al-Qura below 48°.
        XCTAssertTrue(app.staticTexts["prayer.method"].label.contains("أم القرى"), app.staticTexts["prayer.method"].label)

        let today = app.staticTexts["prayer.date"].label
        XCTAssertTrue(today.hasPrefix("اليوم"), today)
        app.buttons["prayer.nextDay"].tap()
        XCTAssertTrue(wait { self.app.staticTexts["prayer.date"].label != today })
        XCTAssertFalse(app.descendants(matching: .any)["prayer.countdown"].exists, "countdown only on today")
        app.buttons["prayer.today"].tap()
        XCTAssertTrue(wait { self.app.staticTexts["prayer.date"].label == today })

        let standardAsr = time("asr").label
        app.buttons["prayer.settings"].tap()
        choose("الحنفي", in: "prayer.settings.asrSchool")
        app.buttons["prayer.settings.done"].tap()
        XCTAssertTrue(wait { self.time("asr").label != standardAsr }, "Hanafi Asr is later")
        let hanafiAsr = time("asr").label

        launch(reset: false, answer: nil)
        openPrayerTimes()
        XCTAssertTrue(time("asr").waitForExistence(timeout: 4))
        XCTAssertEqual(time("asr").label, hanafiAsr)
        XCTAssertTrue(app.staticTexts["prayer.location"].label.contains("٢١٫٤٢، ٣٩٫٨٢"))
    }

    /// The header title leads back to the list, whose row then shows the next prayer.
    func testBackToListShowsTheNextPrayer() {
        launch()
        openPrayerTimes()
        enterLocation("24.71", "46.68")
        XCTAssertTrue(time("fajr").waitForExistence(timeout: 4))
        app.buttons["header.back"].tap()
        let row = app.buttons["other.prayerTimes"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let value = row.value as? String ?? ""
        XCTAssertTrue(["الفجر", "الظهر", "العصر", "المغرب", "العشاء"].contains { value.hasPrefix($0) }, value)
    }
}
