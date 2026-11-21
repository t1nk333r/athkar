import XCTest

/// «أذكار النوم» in أخرى: a reading deck of the sleep pack (spec/sessions/deck-definition.md §12), one card per item,
/// counted and saved per day. Thirteen cards are counted, sleep-04 and sleep-06 three times; the four situational cards
/// say «عند الحاجة» and are never counted.
final class SleepUITests: DeckTestCase {
    /// Taps one card at a time and waits for the deck to move on to `next`.
    private func read(_ times: Int = 1, thenShow next: Int) {
        tapCard(times)
        expectPosition(next, of: 17, noun: "البطاقة")
    }

    /// The row opens the deck; each card counts to its target and the deck moves on, «التالي» waiting for it. The
    /// thirteenth counted card completes the day and opens its dialog; a card reset clears the completion.
    func testCardsAreCountedAndTheLastCountedCardCompletesTheDay() {
        launch()
        app.buttons["tab.other"].tap()
        let row = app.buttons["other.sleep"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.isEnabled, "the section opens")
        XCTAssertEqual(row.value as? String, "قبل النوم وفي الليل")
        row.tap()

        expectPosition(1, of: 17, noun: "البطاقة")
        expectLabel(summary, "٠ من ١٣")
        XCTAssertTrue(card("sleep-01").exists)
        XCTAssertEqual(app.staticTexts["deck.card.title"].label, "آية الكرسي")
        expectLabel(counter, "البطاقة ١، لم تُعلَّم كمقروءة")
        XCTAssertFalse(nextButton.isEnabled, "next waits for the card to be read")
        read(thenShow: 2)
        expectLabel(summary, "١ من ١٣")
        read(thenShow: 3)
        read(thenShow: 4)

        // المعوّذات, three times.
        expectLabel(counter, "البطاقة ٤، كُرّر ٠ من أصل ٣ مرات")
        tapCard()
        expectLabel(counter, "البطاقة ٤، كُرّر ١ من أصل ٣ مرات")
        XCTAssertFalse(nextButton.isEnabled)
        read(2, thenShow: 5)
        read(thenShow: 6)
        read(3, thenShow: 7)
        for position in 8...12 { read(thenShow: position) }
        // سورة الملك, whole on one card, scrolls inside it: a vertical drag scrolls and stays on the card, and a tap
        // still counts.
        XCTAssertTrue(card("sleep-12").exists)
        let mulk = app.scrollViews["deck.card.overflow"]
        XCTAssertTrue(mulk.waitForExistence(timeout: 3), "al-Mulk scrolls inside its card")
        mulk.swipeUp()
        expectPosition(12, of: 17, noun: "البطاقة")
        mulk.tap()
        expectPosition(13, of: 17, noun: "البطاقة")
        tapCard()

        let title = app.staticTexts["completion.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4), "the day's dialog")
        XCTAssertEqual(title.label, "تمت أذكار النوم بحمد الله")
        XCTAssertTrue(app.staticTexts["completion.time"].label.hasPrefix("وقت الإكمال: "))
        XCTAssertFalse(app.buttons["completion.primary"].exists, "«تم» alone")
        app.buttons["completion.dismiss"].tap()
        XCTAssertTrue(wait { !title.exists })
        expectLabel(summary, "اكتملت أذكار النوم اليوم")

        // A situational card: no counter, no reset, never locking.
        nextButton.tap()
        expectPosition(14, of: 17, noun: "البطاقة")
        expectLabel(counter, "البطاقة ١٤، عند الحاجة")
        XCTAssertFalse(tapTarget.exists, "never counted")
        XCTAssertFalse(resetCardButton.exists)
        XCTAssertTrue(nextButton.isEnabled)

        // A card reset asks nothing and clears today's completion.
        previousButton.tap()
        expectPosition(13, of: 17, noun: "البطاقة")
        resetCardButton.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        expectLabel(summary, "١٢ من ١٣")

        app.buttons["header.back"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertEqual(row.label, "أذكار النوم")
        XCTAssertEqual(row.value as? String, "١٢ من ١٣")
    }

    /// Today's counts survive a relaunch, and «تقدم اليوم» clears them.
    func testCountsSurviveRelaunchAndTheDayReset() {
        launch()
        selectTab("sleep")
        read(thenShow: 2)
        app.terminate()
        launch(reset: false, answer: nil)
        selectTab("sleep")
        expectLabel(summary, "١ من ١٣")
        expectPosition(2, of: 17, noun: "البطاقة")

        headerReset.tap()
        app.buttons["reset.day"].tap()
        expectLabel(summary, "٠ من ١٣")
        expectPosition(1, of: 17, noun: "البطاقة")
        XCTAssertTrue(wait { !self.resetEnabled() })
    }
}
