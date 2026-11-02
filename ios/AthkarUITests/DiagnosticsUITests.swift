import XCTest

/// «التشخيص» in الإعدادات (NATIVE_APP_PLAN.md §7.5, §8.4): the planned and pending counts iOS holds, the horizon and
/// budget, the permission and versions, and nothing of the user's worship. Recording a day's prayers on «اليوم» drops
/// their reminders at once.
final class DiagnosticsUITests: DeckTestCase {
    private static let prayers = ["fajr", "dhuhr", "asr", "maghrib", "isha"]

    private func allowNotificationsIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "السماح"]))
            .firstMatch
        if allow.waitForExistence(timeout: 4) { allow.tap() }
    }

    private func openOther(_ section: String) {
        if app.buttons["header.back"].exists { app.buttons["header.back"].tap() }
        app.buttons["tab.other"].tap()
        let cell = app.buttons["other.\(section)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 3), section)
        cell.tap()
    }

    private func enterRiyadh() {
        openOther("prayerTimes")
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
    }

    private func row(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)["diagnostics.\(id)"]
    }

    private func value(_ id: String) -> String { row(id).value as? String ?? "" }

    /// A count the screen writes in Arabic-Indic digits, or `nil`.
    private func count(_ id: String) -> Int? {
        Int(String(value(id).compactMap { $0.wholeNumberValue.map { Character(String($0)) } }))
    }

    private func openDiagnostics() {
        openSettings()
        let link = reveal(app.buttons["settings.diagnostics"])
        XCTAssertTrue(link.exists, "settings.diagnostics")
        link.tap()
        XCTAssertTrue(app.navigationBars["التشخيص"].waitForExistence(timeout: 3))
        XCTAssertTrue(row("planned").waitForExistence(timeout: 3))
    }

    private func closeDiagnostics() {
        app.navigationBars["التشخيص"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["الإعدادات"].waitForExistence(timeout: 3))
        closeSettings()
    }

    /// No diagnostics row names a prayer state, adhkar progress or completion. Each row is one accessibility element
    /// whose label and value are all it shows (the headers and footers are fixed text). App-wide static texts would
    /// also read «اليوم», which stays in the accessibility tree under the settings sheet.
    private func expectNoWorshipData() {
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'diagnostics.'")).allElementsBoundByIndex
        XCTAssertFalse(rows.isEmpty, "no diagnostics rows")
        let texts = rows.flatMap { [$0.label, $0.value as? String ?? ""] }
        for word in ["صلّيتُ", "لم تُسجَّل", "لا تنطبق", "مكتمل", "تقدّم", "فائت"] {
            XCTAssertFalse(texts.contains { $0.contains(word) }, "«\(word)» on the diagnostics screen: \(texts)")
        }
    }

    /// Every prayer's reminder on: the screen shows what is planned and held. Once today's five are recorded, the
    /// six following days' 30 reminders are all that is planned and all that iOS holds, whatever the time of day.
    func testDiagnosticsShowCountsAndRecordedPrayersLoseTheirReminders() {
        launch()
        enterRiyadh()
        app.buttons["prayer.reminders"].tap()
        // From the last row up, so turning one on (which adds its offset row) never moves the next one.
        for (index, prayer) in Self.prayers.reversed().enumerated() {
            let toggleRow = app.switches["prayer.reminder.\(prayer)"]
            XCTAssertTrue(toggleRow.waitForExistence(timeout: 3), prayer)
            let control = toggleRow.switches.firstMatch.exists ? toggleRow.switches.firstMatch : toggleRow
            control.tap()
            if index == 0 { allowNotificationsIfAsked() }
            XCTAssertTrue(wait(timeout: 5) { self.isOn(toggleRow) }, "\(prayer) did not switch on")
        }
        app.buttons["prayer.reminders.done"].tap()

        openDiagnostics()
        XCTAssertTrue(wait(timeout: 6) { (self.count("planned") ?? 0) >= 30 }, value("planned"))
        let planned = count("planned") ?? 0
        XCTAssertTrue(wait(timeout: 6) { self.count("pending") == planned }, "pending \(value("pending"))")
        XCTAssertEqual(value("dropped"), "٠")
        XCTAssertEqual(value("horizon"), "٧ أيام")
        XCTAssertEqual(value("budget"), "٦٤")
        XCTAssertEqual(value("authorization"), "مسموح")
        XCTAssertNotEqual(value("lastReplan"), "لم تحدث بعد")
        for pack in ["adhkar", "ruqyah", "suwar"] {
            XCTAssertFalse(value("content.\(pack)").isEmpty, pack)
        }
        expectNoWorshipData()
        // The app section is last, below the fold: the Form builds its rows only once they scroll into view.
        XCTAssertTrue(reveal(row("appVersion")).exists, "diagnostics.appVersion")
        expectNoWorshipData()
        closeDiagnostics()

        openOther("today")
        for prayer in Self.prayers {
            let log = app.buttons["tracker.log.\(prayer)"]
            XCTAssertTrue(log.waitForExistence(timeout: 3), prayer)
            log.tap()
            XCTAssertTrue(wait { (self.app.buttons["tracker.row.\(prayer)"].value as? String) == "صلّيتُها" }, prayer)
        }

        openDiagnostics()
        XCTAssertTrue(wait(timeout: 6) { self.count("planned") == 30 }, "planned \(value("planned"))")
        XCTAssertTrue(wait(timeout: 6) { self.count("pending") == 30 }, "pending \(value("pending"))")
        expectNoWorshipData()
        closeDiagnostics()
    }
}
