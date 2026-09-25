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

    /// Coming back to the foreground on a new local date starts that day's session in all three decks
    /// (NATIVE_APP_PLAN.md §6.3), and returning to the earlier date shows its counters again: rollover deletes
    /// nothing.
    func testReturningToTheForegroundOnANewDayStartsItAfresh() throws {
        let clock = try makeDayClock()
        launch(environment: ["ATHKAR_UITEST_DAY_OFFSET_FILE": clock.path])
        tapCard()
        expectPosition(2, of: 26)
        expectLabel(summary, "١ من ٢٦ ذكرًا")
        selectTab("ruqyah")
        tapCard()
        expectPosition(2, of: 15, noun: "المقطع")
        expectLabel(summary, "١ من ٣٣ تكرارًا")
        selectTab("morning")

        XCUIDevice.shared.press(.home)
        try setDayOffset(1, clock)
        app.activate()
        expectLabel(summary, "٠ من ٢٦ ذكرًا")
        expectPosition(1, of: 26)
        selectTab("ruqyah")
        expectLabel(summary, "٠ من ٣٣ تكرارًا")
        expectPosition(1, of: 15, noun: "المقطع")

        XCUIDevice.shared.press(.home)
        try setDayOffset(0, clock)
        app.activate()
        expectLabel(summary, "١ من ٣٣ تكرارًا")
        expectPosition(2, of: 15, noun: "المقطع")
        selectTab("morning")
        expectLabel(summary, "١ من ٢٦ ذكرًا")
        expectPosition(2, of: 26)
    }

    /// A tap or a card reset that finds the date changed only starts the new day (spec §5, §9): the tap is not
    /// counted and the reset does not touch the earlier day's counter.
    func testTapOrResetOnANewDayOnlyStartsThatDay() throws {
        let clock = try makeDayClock()
        launch(environment: ["ATHKAR_UITEST_DAY_OFFSET_FILE": clock.path])
        tapCard()
        expectPosition(2, of: 26)
        tapCard(2)
        expectLabel(counter, "ذكر ٢، تم تكراره ٢ من أصل ٣ مرات")

        // Midnight passes with the app open: the reset rolls over and resets nothing.
        try setDayOffset(1, clock)
        resetCardButton.tap()
        expectPosition(1, of: 26)
        expectLabel(summary, "٠ من ٢٦ ذكرًا")
        expectLabel(counter, "ذكر ١، لم يُعلَّم كمقروء")

        // Again: the tap rolls over and is not counted; the next one is.
        try setDayOffset(2, clock)
        tapCard()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        expectPosition(1, of: 26)
        expectLabel(summary, "٠ من ٢٦ ذكرًا")
        expectLabel(counter, "ذكر ١، لم يُعلَّم كمقروء")
        tapCard()
        expectPosition(2, of: 26)
        expectLabel(summary, "١ من ٢٦ ذكرًا")

        // The first day still has its counters.
        XCUIDevice.shared.press(.home)
        try setDayOffset(0, clock)
        app.activate()
        expectPosition(2, of: 26)
        expectLabel(counter, "ذكر ٢، تم تكراره ٢ من أصل ٣ مرات")
    }

    /// A counter of 50 or more asks before its reset, and the question can be declined; a target change that
    /// finds the date changed only starts the new day.
    func testLargeCounterResetAsksAndTargetChangeRollsOverFirst() throws {
        let clock = try makeDayClock()
        launch(environment: ["ATHKAR_UITEST_DAY_OFFSET_FILE": clock.path])
        markMorningCompleteManually()
        next(19, count: 26, from: 1)
        tapCard(2)
        expectLabel(counter, "ذكر ٢٠، تم تكراره ٢ من أصل ١٠٠ مرات")

        let question = app.alerts["إعادة عداد الذكر ٢٠؟"]
        resetCardButton.tap()
        XCTAssertTrue(question.waitForExistence(timeout: 3), "no question before resetting a counter of 100")
        XCTAssertTrue(question.staticTexts["سيعود العداد من ٢ إلى الصفر."].exists)
        question.buttons["إلغاء"].tap()
        XCTAssertTrue(wait { !question.exists })
        expectLabel(counter, "ذكر ٢٠، تم تكراره ٢ من أصل ١٠٠ مرات")
        resetCardButton.tap()
        XCTAssertTrue(question.waitForExistence(timeout: 3))
        question.buttons["إعادة"].tap()
        expectLabel(counter, "ذكر ٢٠، تم تكراره ٠ من أصل ١٠٠ مرات")

        try setDayOffset(1, clock)
        chooseTarget(10)
        expectPosition(1, of: 26)
        expectLabel(summary, "٠ من ٢٦ ذكرًا")
    }

    /// A tap that ends a horizontal drag does not count (the 450 ms `suppressCardClicksUntil`); a tap after it
    /// does.
    func testTapEndingAHorizontalDragDoesNotCount() {
        launch()
        let start = card("morning-01").coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 24, dy: 0)))
        tapCard()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        expectPosition(1, of: 26)
        expectLabel(counter, "ذكر ١، لم يُعلَّم كمقروء")
        tapCard()
        expectPosition(2, of: 26)
    }

    /// Resetting a card of a period completed by its counters makes it incomplete again, so completing it once
    /// more opens the dialog again (`syncCompletionState` after the reset). The card is read once, so the tap that
    /// completes the period again is the first change after the reset.
    func testCompletingAgainAfterACardResetReopensTheDialog() throws {
        let pack = try makeContentPack(morning: ["morning-05"], evening: ["evening-05", "evening-02"],
                                       ruqyah: ["qaf-1-8"])
        launch(environment: ["ATHKAR_UITEST_CONTENT_DIR": pack.path])
        selectTab("evening")
        tapCard()
        expectPosition(2, of: 2)
        tapCard(3)
        let title = app.staticTexts["completion.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        XCTAssertEqual(title.label, "اكتملت أذكار المساء بحمد الله")
        app.buttons["completion.dismiss"].tap()
        XCTAssertTrue(wait { !title.exists })
        XCTAssertEqual(app.buttons["tab.evening"].label, "أذكار المساء، مكتملة اليوم")

        previousButton.tap()
        expectPosition(1, of: 2)
        resetCardButton.tap()
        expectLabel(counter, "ذكر ١، لم يُعلَّم كمقروء")
        expectLabel(summary, "١ من ٢ ذكرًا")
        XCTAssertTrue(wait { self.app.buttons["tab.evening"].label == "أذكار المساء" })
        tapCard()
        XCTAssertTrue(title.waitForExistence(timeout: 4), "no dialog on completing the evening again")
    }

    /// Every completion of the ruqyah opens its dialog, not only the first of the day; a segment reset always asks.
    func testCompletingTheRuqyahAgainReopensTheDialog() throws {
        let pack = try makeContentPack(morning: ["morning-05"], evening: ["evening-05"],
                                       ruqyah: ["qaf-1-8", "qaf-9-14"])
        launch(environment: ["ATHKAR_UITEST_CONTENT_DIR": pack.path])
        selectTab("ruqyah")
        tapCard()
        expectPosition(2, of: 2, noun: "المقطع")
        tapCard()
        let title = app.staticTexts["completion.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        XCTAssertEqual(title.label, "تمت الرقية بحمد الله")
        app.buttons["completion.dismiss"].tap()
        XCTAssertTrue(wait { !title.exists })

        let question = app.alerts["إعادة العداد؟"]
        resetCardButton.tap()
        XCTAssertTrue(question.waitForExistence(timeout: 3), "no question before resetting a segment")
        XCTAssertTrue(question.staticTexts["سيعود عداد سورة ق الآيات ٩ – ١٤ إلى الصفر."].exists)
        question.buttons["إعادة"].tap()
        expectLabel(summary, "١ من ٢ تكرارًا")
        tapCard()
        XCTAssertTrue(title.waitForExistence(timeout: 4), "no dialog on completing the ruqyah again")
    }

    /// A review item (`kind: review`) loads, and its card shows the badge, `reviewTitle` and `reviewCopy` with no
    /// counter, reset or tap target; it is not counted and never locks «التالي».
    func testReviewItemShowsBadgeTitleAndCopyOnly() throws {
        let pack = try makeContentPack(morning: ["morning-05", "review", "morning-06"], evening: ["evening-05"],
                                       ruqyah: ["qaf-1-8"])
        launch(environment: ["ATHKAR_UITEST_CONTENT_DIR": pack.path])
        expectLabel(summary, "٠ من ٢ ذكرًا متاحًا")
        tapCard()
        expectPosition(2, of: 3)
        XCTAssertTrue(card("morning-90").exists)
        XCTAssertTrue(app.staticTexts["deck.card.review.badge"].exists)
        expectLabel(app.staticTexts["deck.card.review.title"], Self.reviewTitle)
        expectLabel(app.staticTexts["deck.card.review.copy"], Self.reviewCopy)
        XCTAssertFalse(counter.exists, "a review card has no counter")
        XCTAssertFalse(resetCardButton.exists, "a review card has no reset")
        XCTAssertFalse(tapTarget.exists, "a review card cannot be tapped")
        XCTAssertTrue(nextButton.isEnabled)

        nextButton.tap()
        expectPosition(3, of: 3)
        tapCard()
        let title = app.staticTexts["completion.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4), "the review item is not needed to complete the morning")
        XCTAssertEqual(title.label, "اكتملت أذكار الصباح بحمد الله")
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
