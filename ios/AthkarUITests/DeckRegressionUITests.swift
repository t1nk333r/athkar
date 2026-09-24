import XCTest

/// Behaviours the first round of UI tests did not pin down (found by mutation testing), plus the overflow hint.
final class DeckRegressionUITests: DeckTestCase {
    /// A Quran card too long for the card scrolls; until its end is in view it shows «المزيد» over a fade, and the
    /// hadith below cannot be reached by eye. Scrolling to the end reveals it and removes the hint.
    func testOverflowingCardShowsMoreUntilScrolledToTheEnd() {
        launch()
        openSettings()
        choose("كبير", in: "settings.textSize")
        closeSettings()
        XCTAssertTrue(card("morning-01").exists)

        let more = app.buttons["deck.card.more"]
        let detail = app.staticTexts.matching(identifier: "deck.card.detail").firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 3), "no «المزيد» on an overflowing card")
        XCTAssertFalse(detail.isHittable, "the detail should start below the visible area")

        let scroll = app.scrollViews["deck.card.overflow"]
        for _ in 0..<4 where more.exists {
            scroll.swipeUp()
        }
        XCTAssertTrue(wait { !more.exists }, "«المزيد» stays after scrolling to the end")
        XCTAssertTrue(detail.isHittable)
        expectPosition(1, of: 26)
        expectLabel(counter, "ذكر ١، لم يُعلَّم كمقروء")
    }

    /// A chosen target is saved when it is chosen, not only with the next tap.
    func testTargetChoiceSurvivesRelaunch() {
        launch()
        markMorningCompleteManually()
        next(19, count: 26, from: 1)
        chooseTarget(10)
        expectLabel(counter, "ذكر ٢٠، تم تكراره ٠ من أصل ١٠ مرات")

        app.terminate()
        launch(reset: false, answer: nil)
        next(19, count: 26, from: 1)
        expectLabel(counter, "ذكر ٢٠، تم تكراره ٠ من أصل ١٠ مرات")
    }

    /// Coming back to the foreground on a new local date starts that day's session (NATIVE_APP_PLAN.md §6.3), and
    /// returning to the earlier date shows its counters again: rollover deletes nothing.
    func testReturningToTheForegroundOnANewDayStartsItAfresh() throws {
        let clock = URL(fileURLWithPath: "/tmp/athkar-uitest-day-\(UUID().uuidString).txt")
        try "0".write(to: clock, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: clock) }

        launch(environment: ["ATHKAR_UITEST_DAY_OFFSET_FILE": clock.path])
        tapCard()
        expectPosition(2, of: 26)
        expectLabel(summary, "١ من ٢٦ ذكرًا")

        XCUIDevice.shared.press(.home)
        try "1".write(to: clock, atomically: true, encoding: .utf8)
        app.activate()
        expectLabel(summary, "٠ من ٢٦ ذكرًا")
        expectPosition(1, of: 26)

        XCUIDevice.shared.press(.home)
        try "0".write(to: clock, atomically: true, encoding: .utf8)
        app.activate()
        expectLabel(summary, "١ من ٢٦ ذكرًا")
        expectPosition(2, of: 26)
    }

    /// Leaving a deck while its auto-advance is pending cancels it (the PWA's `activePeriod !== period` check), so
    /// the deck is where the reader left it on return.
    func testSwitchingDeckCancelsThePendingAdvance() {
        launch(environment: ["ATHKAR_UITEST_ADVANCE_DELAY_MS": "2500"])
        tapCard()
        selectTab("evening")
        expectPosition(1, of: 24)
        RunLoop.current.run(until: Date().addingTimeInterval(3.5))
        selectTab("morning")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        expectPosition(1, of: 26)
        expectLabel(counter, "ذكر ١، تمت قراءته")
    }
}
