import XCTest

/// «اليوم» and «التقويم» in أخرى: the quick log and its undo, Friday's Jumu'ah or Dhuhr in one slot, a past day edited
/// and cleared through the calendar with a confirmation, and a calendar that never marks a day as missed.
final class PrayerTrackerUITests: DeckTestCase {
    private func open(_ section: String) {
        if app.buttons["header.back"].exists {
            app.buttons["header.back"].tap()
        }
        app.buttons["tab.other"].tap()
        let cell = app.buttons["other.\(section)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 3), section)
        cell.tap()
    }

    private func row(_ prayer: String) -> XCUIElement { app.buttons["tracker.row.\(prayer)"] }
    private func log(_ prayer: String) -> XCUIElement { app.buttons["tracker.log.\(prayer)"] }

    private func expectState(_ prayer: String, _ state: String, file: StaticString = #filePath, line: UInt = #line) {
        let matched = wait { (self.row(prayer).value as? String) == state }
        XCTAssertTrue(matched, "\(prayer): expected «\(state)», found «\(row(prayer).value ?? "<missing>")»",
                      file: file, line: line)
    }

    /// Today in the app's zone (no location: the device's), and a day of the month before it.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    /// The first Friday (weekday 6) of the previous month, or its 15th.
    private func previousMonthDay(friday: Bool) -> String {
        let firstOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let first = calendar.date(byAdding: .month, value: -1, to: firstOfThisMonth)!
        let offset = friday ? (6 - calendar.component(.weekday, from: first) + 7) % 7 : 14
        return key(calendar.date(byAdding: .day, value: offset, to: first)!)
    }

    private func openPreviousMonthDay(_ date: String) {
        open("calendar")
        let previous = app.buttons["calendar.previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 3))
        previous.tap()
        let cell = app.buttons["calendar.day.\(date)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 3), date)
        cell.tap()
        XCTAssertTrue(row("fajr").waitForExistence(timeout: 3), "the day opens with its prayers")
    }

    func testQuickLogRecordsAtOnceAndUndoTakesItBack() {
        launch()
        open("today")
        XCTAssertTrue(app.descendants(matching: .any)["today.date"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["today.next"].exists)
        XCTAssertTrue(app.buttons["today.adhkar.morning"].exists)
        for prayer in ["fajr", "dhuhr", "asr", "maghrib", "isha"] {
            expectState(prayer, "لم تُسجَّل")
        }

        log("fajr").tap()
        expectState("fajr", "صلّيتُها")
        let undo = app.buttons["tracker.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "the quick log offers undo")
        XCTAssertEqual(app.staticTexts["tracker.undoMessage"].label, "الفجر: صلّيتُها")
        undo.tap()
        expectState("fajr", "لم تُسجَّل")
        XCTAssertTrue(wait { !undo.exists })

        log("asr").tap()
        expectState("asr", "صلّيتُها")
        // A second tap on a recorded prayer opens its details instead of logging again.
        log("asr").tap()
        XCTAssertTrue(app.buttons["tracker.state.prayed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tracker.state.prayed"].isSelected)
        app.buttons["tracker.timing.late"].tap()
        XCTAssertTrue(wait { self.app.buttons["tracker.timing.late"].isSelected })
        app.buttons["tracker.sheet.done"].tap()
        expectState("asr", "صلّيتُها، متأخرة")

        launch(reset: false, answer: nil)
        open("today")
        expectState("asr", "صلّيتُها، متأخرة")
        XCTAssertFalse(app.buttons["tracker.undo"].exists, "a relaunch offers nothing to undo")
    }

    func testFridayDhuhrSlotRecordsJumuahOrDhuhr() {
        let friday = previousMonthDay(friday: true)
        launch()
        openPreviousMonthDay(friday)
        XCTAssertTrue(row("dhuhr").label.hasPrefix("الظهر أو الجمعة"), row("dhuhr").label)

        row("dhuhr").tap()
        let jumuah = app.buttons["tracker.noon.jumuah"]
        XCTAssertTrue(jumuah.waitForExistence(timeout: 3), "a Friday's Dhuhr offers the choice")
        jumuah.tap()
        XCTAssertTrue(wait { jumuah.isSelected })
        XCTAssertTrue(app.buttons["tracker.state.prayed"].isSelected, "choosing Jumu'ah records the slot")
        app.buttons["tracker.noon.dhuhr"].tap()
        XCTAssertTrue(wait { self.app.buttons["tracker.noon.dhuhr"].isSelected && !jumuah.isSelected })
        jumuah.tap()
        XCTAssertTrue(wait { jumuah.isSelected })
        app.buttons["tracker.sheet.done"].tap()
        XCTAssertTrue(wait { self.row("dhuhr").label.hasPrefix("الجمعة") }, row("dhuhr").label)
        expectState("dhuhr", "صلّيتُها")

        // The day's other prayers have no such choice.
        row("asr").tap()
        XCTAssertTrue(app.buttons["tracker.state.prayed"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["tracker.noon.jumuah"].exists)
        app.buttons["tracker.sheet.done"].tap()
    }

    func testAPastDayIsEditedInTheCalendarAndClearedAfterConfirmation() {
        let day = previousMonthDay(friday: false)
        launch()
        openPreviousMonthDay(day)
        XCTAssertFalse(app.buttons["calendar.clearDay"].exists, "nothing to clear yet")
        log("fajr").tap()
        expectState("fajr", "صلّيتُها")
        row("isha").tap()
        app.buttons["tracker.state.not_applicable"].tap()
        XCTAssertTrue(wait { self.app.buttons["tracker.state.not_applicable"].isSelected })
        app.buttons["tracker.sheet.done"].tap()
        expectState("isha", "لا تنطبق")
        app.buttons["calendar.dayDone"].tap()

        let cell = app.buttons["calendar.day.\(day)"]
        XCTAssertTrue(wait { (cell.value as? String) == "الصلوات المسجّلة: \(ar(1)) من \(ar(4))" },
                      "\(cell.value ?? "")")

        cell.tap()
        let clear = app.buttons["calendar.clearDay"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        let alert = app.alerts["مسح تسجيلات هذا اليوم؟"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "clearing a day asks first")
        alert.buttons["إلغاء"].tap()
        expectState("fajr", "صلّيتُها")
        clear.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["مسح"].tap()
        expectState("fajr", "لم تُسجَّل")
        expectState("isha", "لم تُسجَّل")
        app.buttons["calendar.dayDone"].tap()
        XCTAssertTrue(wait { (cell.value as? String) == "لا تسجيل للصلوات" }, "\(cell.value ?? "")")
    }

    /// Days without records read like any other day: no missed, failed or score wording anywhere, and future days are
    /// read-only.
    func testTheCalendarHasNoMissedState() {
        launch()
        open("today")
        log("maghrib").tap()
        expectState("maghrib", "صلّيتُها")
        app.buttons["today.calendar"].tap()

        let today = key(Date())
        let todayCell = app.buttons["calendar.day.\(today)"]
        XCTAssertTrue(todayCell.waitForExistence(timeout: 3))
        XCTAssertEqual(todayCell.value as? String, "الصلوات المسجّلة: \(ar(1)) من \(ar(5))")
        XCTAssertTrue(app.descendants(matching: .any)["calendar.totals"].exists)

        let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar.day.'"))
        XCTAssertGreaterThanOrEqual(days.count, 28)
        let allowed = ["لا تسجيل للصلوات", "لم يأتِ بعد"]
        for index in 0..<days.count {
            let cell = days.element(boundBy: index)
            let value = cell.value as? String ?? ""
            if cell.identifier == "calendar.day.\(today)" { continue }
            XCTAssertTrue(allowed.contains(value), "\(cell.identifier): «\(value)»")
            if value == "لم يأتِ بعد" { XCTAssertFalse(cell.isEnabled, "\(cell.identifier) is in the future") }
        }
        for word in ["فائت", "فاتت", "missed", "Missed"] {
            let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", word, word)
            let found = app.descendants(matching: .any).matching(predicate)
            XCTAssertEqual(found.count, 0, word)
        }
    }
}
