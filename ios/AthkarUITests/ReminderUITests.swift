import XCTest

/// Reminders (NATIVE_APP_PLAN.md §7.5): turning one on asks for notification permission, and the status note then
/// shows the earliest request iOS holds, so the test checks the real pending requests rather than the plan.
final class ReminderUITests: DeckTestCase {
    private func allowNotificationsIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "السماح"]))
            .firstMatch
        if allow.waitForExistence(timeout: 4) { allow.tap() }
    }

    private var nextReminderNote: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "التذكير القادم")).firstMatch
    }

    private func enterRiyadh() {
        app.buttons["tab.other"].tap()
        let row = app.buttons["other.prayerTimes"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
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

    /// A prayer reminder and both adhkar reminders are planned with iOS; the toggles survive a relaunch.
    func testRemindersArePlannedAndPersist() {
        launch()
        enterRiyadh()

        app.buttons["prayer.reminders"].tap()
        XCTAssertTrue(app.switches["prayer.reminder.fajr"].waitForExistence(timeout: 3))
        toggle("prayer.reminder.fajr", to: true)
        allowNotificationsIfAsked()
        XCTAssertTrue(app.buttons["prayer.reminder.fajr.offset"].waitForExistence(timeout: 3), "offset picker")
        XCTAssertTrue(nextReminderNote.waitForExistence(timeout: 5), "a pending prayer reminder")
        XCTAssertTrue(nextReminderNote.label.contains("صلاة الفجر"), nextReminderNote.label)
        app.buttons["prayer.reminders.done"].tap()

        openSettings()
        toggle("settings.reminder.morning", to: true)
        toggle("settings.reminder.evening", to: true)
        XCTAssertTrue(nextReminderNote.waitForExistence(timeout: 5), "a pending reminder")
        closeSettings()

        launch(reset: false, answer: nil)
        openSettings()
        XCTAssertTrue(isOn(app.switches["settings.reminder.morning"]))
        XCTAssertTrue(isOn(app.switches["settings.reminder.evening"]))
        closeSettings()
    }
}
