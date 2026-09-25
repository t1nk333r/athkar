import XCTest

/// The deck workflows of NATIVE_APP_PLAN.md §3.1 against the PWAs' behaviour and wording.
final class DeckUITests: DeckTestCase {
    /// Tap to count; a card at its target locks, fires auto-advance, and «التالي» waits for it.
    func testTapCountsCompletesAndAdvances() {
        launch()
        expectPosition(1, of: 26)
        XCTAssertTrue(card("morning-01").exists)
        expectLabel(counter, "ذكر ١، لم يُعلَّم كمقروء")
        XCTAssertFalse(nextButton.isEnabled, "next waits for the card to be read")
        expectLabel(summary, "٠ من ٢٦ ذكرًا")

        tapCard()
        expectPosition(2, of: 26)
        expectLabel(summary, "١ من ٢٦ ذكرًا")

        // A counted item: three taps, then it advances.
        expectLabel(counter, "ذكر ٢، تم تكراره ٠ من أصل ٣ مرات")
        tapCard(2)
        expectLabel(counter, "ذكر ٢، تم تكراره ٢ من أصل ٣ مرات")
        expectPosition(2, of: 26)
        XCTAssertFalse(nextButton.isEnabled)
        tapCard()
        expectPosition(3, of: 26)
        expectLabel(summary, "٢ من ٢٦ ذكرًا")

        // Back to the first card: read, locked, and resettable without a question (target below 50).
        previousButton.tap()
        previousButton.tap()
        expectPosition(1, of: 26)
        expectLabel(counter, "ذكر ١، تمت قراءته")
        XCTAssertFalse(tapTarget.isEnabled, "a completed card no longer counts")
        XCTAssertTrue(nextButton.isEnabled)
        resetCardButton.tap()
        expectLabel(counter, "ذكر ١، لم يُعلَّم كمقروء")
        expectLabel(summary, "١ من ٢٦ ذكرًا")
        XCTAssertFalse(resetCardButton.isEnabled)
    }

    /// Swipe with axis lock: rightward is forward (RTL), a card not yet read cannot be left forward, vertical
    /// drags never navigate.
    func testSwipeNavigatesWithAxisLock() {
        launch()
        swipe("morning-01", .right)
        expectPosition(1, of: 26)
        tapCard()
        expectPosition(2, of: 26)
        swipe("morning-02", .left)
        expectPosition(1, of: 26)
        swipe("morning-01", .up)
        swipe("morning-01", .down)
        expectPosition(1, of: 26)
        swipe("morning-01", .right)
        expectPosition(2, of: 26)
        swipe("morning-02", .right)
        expectPosition(2, of: 26)
    }

    private enum Direction { case left, right, up, down }

    /// Swipes the card, then waits out the 450 ms in which the PWA ignores taps after a horizontal swipe.
    private func swipe(_ id: String, _ direction: Direction) {
        let element = card(id)
        switch direction {
        case .left: element.swipeLeft()
        case .right: element.swipeRight()
        case .up: element.swipeUp()
        case .down: element.swipeDown()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    /// The «الهدف» picker: 1, 10 or 100; the count is clamped to a lower target; reaching it advances.
    func testTargetChangeOneTenHundred() {
        launch()
        markMorningCompleteManually()
        next(19, count: 26, from: 1)
        XCTAssertTrue(card("morning-20").exists)
        expectLabel(counter, "ذكر ٢٠، تم تكراره ٠ من أصل ١٠٠ مرات")

        chooseTarget(10)
        expectLabel(counter, "ذكر ٢٠، تم تكراره ٠ من أصل ١٠ مرات")
        tapCard(10)
        expectPosition(21, of: 26)
        previousButton.tap()
        expectLabel(counter, "ذكر ٢٠، تم تكراره ١٠ من أصل ١٠ مرات، اكتمل")

        chooseTarget(1)
        expectLabel(counter, "ذكر ٢٠، تم تكراره ١ من أصل ١ مرات، اكتمل")
        chooseTarget(100)
        expectLabel(counter, "ذكر ٢٠، تم تكراره ١ من أصل ١٠٠ مرات")
        XCTAssertTrue(tapTarget.isEnabled)
    }

    /// Manual completion: the period reads complete outside the app and the deck can be browsed; turning it off
    /// restores the counters' view.
    func testManualCompletion() {
        launch()
        XCTAssertFalse(nextButton.isEnabled)
        openSettings()
        XCTAssertTrue(app.staticTexts["لم تُسجل كمكتملة"].exists)
        toggle("settings.manual.morning", to: true)
        XCTAssertTrue(app.staticTexts["اكتملت خارج التطبيق"].exists)
        closeSettings()

        expectLabel(summary, "اكتملت أذكار الصباح خارج التطبيق")
        XCTAssertEqual(app.buttons["tab.morning"].label, "أذكار الصباح، مكتملة اليوم")
        XCTAssertTrue(nextButton.isEnabled)
        nextButton.tap()
        expectPosition(2, of: 26)

        openSettings()
        toggle("settings.manual.morning", to: false)
        closeSettings()
        expectLabel(summary, "٠ من ٢٦ ذكرًا")
        XCTAssertEqual(app.buttons["tab.morning"].label, "أذكار الصباح")
        XCTAssertFalse(nextButton.isEnabled)
    }

    /// «تأخير الأذكار الطويلة» moves items of ten or more repetitions before the last one, keeps their numbers and
    /// the current card, and turning it off restores the content order.
    func testLongOrderReordersDeck() {
        launch()
        markMorningCompleteManually()
        next(19, count: 26, from: 1)
        XCTAssertTrue(card("morning-20").exists)

        openSettings()
        toggle("settings.longOrder", to: true)
        closeSettings()
        // The deck is m01…m19, m22, m23, m26, then the long m20, m21, m24, then m25 (still last).
        expectPosition(23, of: 26)
        XCTAssertTrue(card("morning-20").exists)
        previousButton.tap()
        expectPosition(22, of: 26)
        XCTAssertTrue(card("morning-26").exists)
        next(3, count: 26, from: 22)
        XCTAssertTrue(card("morning-24").exists)
        nextButton.tap()
        expectPosition(26, of: 26)
        XCTAssertTrue(card("morning-25").exists)

        openSettings()
        toggle("settings.longOrder", to: false)
        closeSettings()
        expectPosition(26, of: 26)
        XCTAssertTrue(card("morning-25").exists)
        previousButton.tap()
        XCTAssertTrue(card("morning-26").exists)
        expectPosition(25, of: 26)
    }

    /// The reset picker: today's counters at once; week and everything after a question that can be declined.
    func testScopedReset() {
        launch()
        XCTAssertFalse(headerReset.isEnabled, "nothing to reset yet")
        tapCard()
        expectLabel(summary, "١ من ٢٦ ذكرًا")

        headerReset.tap()
        app.buttons["reset.day"].tap()
        expectLabel(summary, "٠ من ٢٦ ذكرًا")
        expectPosition(1, of: 26)
        XCTAssertTrue(wait { !self.headerReset.isEnabled })

        tapCard()
        expectLabel(summary, "١ من ٢٦ ذكرًا")
        headerReset.tap()
        app.buttons["reset.week"].tap()
        let week = app.alerts["حذف سجل هذا الأسبوع؟"]
        XCTAssertTrue(week.waitForExistence(timeout: 3))
        XCTAssertTrue(week.staticTexts["ستُعاد عدادات اليوم، وسيُحذف سجل آخر سبعة أيام. لا يمكن التراجع."].exists)
        week.buttons["إلغاء"].tap()
        expectLabel(summary, "١ من ٢٦ ذكرًا")

        headerReset.tap()
        app.buttons["reset.everything"].tap()
        let everything = app.alerts["حذف كل شيء؟"]
        XCTAssertTrue(everything.waitForExistence(timeout: 3))
        XCTAssertTrue(everything.staticTexts["ستُعاد العدادات وسيُحذف السجل كاملًا. لا يمكن التراجع."].exists)
        everything.buttons["إعادة"].tap()
        expectLabel(summary, "٠ من ٢٦ ذكرًا")
        XCTAssertTrue(wait { !self.headerReset.isEnabled })
    }

    /// Ruqyah: segments repeat 1 or 7 times, advance when done; all 33 readings record the day and open the
    /// dialog; «بدء رقية جديدة» restarts the counters but keeps today's record; «كل شيء» removes it.
    func testRuqyahRepeatCountingToCompletion() {
        launch()
        selectTab("ruqyah")
        expectPosition(1, of: 15, noun: "المقطع")
        expectLabel(summary, "٠ من ٣٣ تكرارًا")
        expectLabel(app.staticTexts["summary.status"], "رقية اليوم لم تكتمل بعد.")

        let repeats = [1, 1, 1, 7, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 7]
        for (index, times) in repeats.enumerated() {
            expectPosition(index + 1, of: 15, noun: "المقطع")
            if times > 1 {
                tapCard(times - 1)
                XCTAssertTrue(counter.label.hasSuffix("تم \(ar(times - 1)) من \(ar(times))"), counter.label)
                expectPosition(index + 1, of: 15, noun: "المقطع")
            }
            tapCard(times > 1 ? 1 : times)
        }

        let title = app.staticTexts["completion.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        XCTAssertEqual(title.label, "تمت الرقية بحمد الله")
        expectLabel(summary, "٣٣ من ٣٣ تكرارًا")
        XCTAssertTrue(app.staticTexts["summary.status"].label.hasPrefix("تمت رقية اليوم في"))
        XCTAssertEqual(app.buttons["tab.ruqyah"].label, "رقية القرين، مكتملة اليوم")

        app.buttons["completion.primary"].tap()
        expectLabel(summary, "٠ من ٣٣ تكرارًا")
        expectPosition(1, of: 15, noun: "المقطع")
        XCTAssertTrue(app.staticTexts["summary.status"].label.hasPrefix("تمت رقية اليوم في"), "history kept")

        headerReset.tap()
        app.buttons["reset.everything"].tap()
        let everything = app.alerts["حذف كل شيء؟"]
        XCTAssertTrue(everything.waitForExistence(timeout: 3))
        XCTAssertTrue(everything.staticTexts["ستُعاد العدادات وسيُحذف السجل كاملًا (يوم واحد). لا يمكن التراجع."].exists)
        everything.buttons["إعادة"].tap()
        expectLabel(app.staticTexts["summary.status"], "رقية اليوم لم تكتمل بعد.")
        XCTAssertTrue(wait { !self.headerReset.isEnabled })
    }

    /// Counters, targets, settings (theme included) and the answered question survive a relaunch; each deck reopens
    /// on its first unread card.
    func testStateSurvivesRelaunch() {
        launch(answer: Self.moveLongLast)
        tapCard()
        expectPosition(2, of: 26)
        tapCard()
        expectLabel(counter, "ذكر ٢، تم تكراره ١ من أصل ٣ مرات")
        openSettings()
        choose("داكن", in: "settings.theme")
        choose("كبير", in: "settings.textSize")
        choose("واسع", in: "settings.lineSpacing")
        toggle("settings.manual.evening", to: true)
        toggle("settings.haptics", to: false)
        closeSettings()
        selectTab("ruqyah")
        tapCard()
        expectPosition(2, of: 15, noun: "المقطع")

        app.terminate()
        launch(reset: false, answer: nil)
        XCTAssertFalse(app.alerts["تأجيل الأذكار الطويلة؟"].waitForExistence(timeout: 2), "asked only once")
        expectPosition(2, of: 26)
        expectLabel(counter, "ذكر ٢، تم تكراره ١ من أصل ٣ مرات")
        expectLabel(summary, "١ من ٢٦ ذكرًا")
        XCTAssertEqual(app.buttons["tab.evening"].label, "أذكار المساء، مكتملة اليوم")

        openSettings()
        XCTAssertTrue(app.segmentedControls["settings.theme"].buttons["داكن"].isSelected)
        XCTAssertTrue(app.segmentedControls["settings.textSize"].buttons["كبير"].isSelected)
        XCTAssertTrue(app.segmentedControls["settings.lineSpacing"].buttons["واسع"].isSelected)
        XCTAssertTrue(isOn(reveal(app.switches["settings.longOrder"])))
        XCTAssertTrue(isOn(reveal(app.switches["settings.manual.evening"])))
        XCTAssertFalse(isOn(reveal(app.switches["settings.haptics"])))
        closeSettings()

        selectTab("ruqyah")
        expectPosition(2, of: 15, noun: "المقطع")
        expectLabel(summary, "١ من ٣٣ تكرارًا")
    }
}
