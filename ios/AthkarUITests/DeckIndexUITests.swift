import XCTest

/// The quick card index (spec §4, "Native quick index"): the position opens every card of the deck in its current
/// order; reachable rows open their card without counting it, later rows behind an unread card stay disabled.
final class DeckIndexUITests: DeckTestCase {
    static let adhkarIndex = "فهرس الورد"
    static let ruqyahIndex = "فهرس الرقية"

    func testPositionOpensTheMorningIndexWithLaterRowsLocked() {
        launch()
        expectPosition(1, of: 26)
        XCTAssertTrue(position.isHittable)
        XCTAssertGreaterThanOrEqual(position.frame.height, 44)
        openIndex()

        let first = row("morning-01")
        XCTAssertTrue(first.isEnabled)
        XCTAssertTrue(first.isSelected, "the current card")
        XCTAssertEqual(first.label, "ذكر ١، لم يُعلَّم كمقروء")
        XCTAssertEqual(first.value as? String, "١ من ٢٦")
        let second = row("morning-02")
        XCTAssertFalse(second.isEnabled, "locked behind card 1")
        XCTAssertFalse(second.isSelected)
        XCTAssertEqual(second.label, "ذكر ٢، تم تكراره ٠ من أصل ٣ مرات")
        expectLabel(lockNote, "يُتاح بعد إكمال الذكر ١")
        XCTAssertFalse(revealRow("morning-25").isEnabled, "the last row is listed, disabled")

        revealRow("morning-02").tap()
        XCTAssertTrue(app.navigationBars[Self.adhkarIndex].exists, "a locked row does nothing")
        closeIndex()
        expectPosition(1, of: 26)
        expectLabel(counter, "ذكر ١، لم يُعلَّم كمقروء")
    }

    func testChoosingARowNavigatesWithoutCounting() {
        launch()
        tapCard()
        expectPosition(2, of: 26)
        tapCard(3)
        expectPosition(3, of: 26)
        expectLabel(summary, "٢ من ٢٦ ذكرًا")

        openIndex()
        XCTAssertTrue(row("morning-03").isSelected)
        XCTAssertFalse(row("morning-04").isEnabled, "locked behind card 3")
        row("morning-01").tap()
        expectPosition(1, of: 26)
        expectLabel(counter, "ذكر ١، تمت قراءته")
        expectLabel(summary, "٢ من ٢٦ ذكرًا")

        openIndex()
        XCTAssertTrue(row("morning-01").isSelected)
        XCTAssertEqual(row("morning-02").label, "ذكر ٢، تم تكراره ٣ من أصل ٣ مرات، اكتمل")
        row("morning-03").tap()
        expectPosition(3, of: 26)
        expectLabel(counter, "ذكر ٣، تم تكراره ٠ من أصل ٣ مرات")

        // The current row only closes the index.
        openIndex()
        row("morning-03").tap()
        XCTAssertTrue(wait { !self.app.navigationBars[Self.adhkarIndex].exists })
        expectPosition(3, of: 26)
        expectLabel(summary, "٢ من ٢٦ ذكرًا")
    }

    func testManualCompletionOpensEveryRowWithoutCompletingThem() {
        launch()
        markMorningCompleteManually()
        openIndex()
        XCTAssertEqual(row("morning-01").label, "ذكر ١، لم يُعلَّم كمقروء", "rows keep their counters")
        XCTAssertFalse(lockNote.exists)
        let last = revealRow("morning-25")
        XCTAssertTrue(last.isEnabled)
        last.tap()
        expectPosition(26, of: 26)
        XCTAssertTrue(card("morning-25").exists)
        expectLabel(summary, "اكتملت أذكار الصباح خارج التطبيق")
    }

    func testEveningAndRuqyahIndexes() {
        launch()
        selectTab("evening")
        expectPosition(1, of: 24)
        openIndex()
        XCTAssertTrue(row("evening-01").isSelected)
        XCTAssertEqual(row("evening-02").value as? String, "٢ من ٢٤")
        XCTAssertFalse(row("evening-02").isEnabled)
        closeIndex()

        selectTab("ruqyah")
        expectPosition(1, of: 15, noun: "المقطع")
        openIndex(Self.ruqyahIndex)
        let first = row("qaf-1-8")
        XCTAssertTrue(first.isSelected)
        XCTAssertEqual(first.label, "المقطع ١: سورة ق الآيات ١ – ٨. لم تُقرأ بعد")
        XCTAssertEqual(first.value as? String, "١ من ١٥")
        XCTAssertFalse(lockNote.exists, "the ruqyah never locks")
        let last = revealRow("nas-1-6")
        XCTAssertTrue(last.isEnabled)
        last.tap()
        expectPosition(15, of: 15, noun: "المقطع")
        expectLabel(summary, "٠ من ٣٣ تكرارًا")
    }

    /// With long adhkar last the rows follow the deck: card ٢٥ (`morning-26`) is the 22nd row and card ٢٠ the 23rd.
    func testLongOrderRowsFollowTheDeckAndKeepTheirNumbers() {
        launch(answer: Self.moveLongLast)
        markMorningCompleteManually()
        openIndex()
        let moved = revealRow("morning-26")
        XCTAssertTrue(moved.label.hasPrefix("ذكر ٢٥،"), moved.label)
        XCTAssertEqual(moved.value as? String, "٢٢ من ٢٦")
        let long = revealRow("morning-20")
        XCTAssertTrue(long.label.hasPrefix("ذكر ٢٠،"), long.label)
        XCTAssertEqual(long.value as? String, "٢٣ من ٢٦")
        long.tap()
        expectPosition(23, of: 26)
        XCTAssertTrue(card("morning-20").exists)
        expectLabel(counter, "ذكر ٢٠، تم تكراره ٠ من أصل ١٠٠ مرات")
    }

    /// Opening the index cancels a pending auto-advance and closing it does not bring it back; a row chosen while an
    /// advance was pending is where the deck stays.
    func testOpeningTheIndexCancelsThePendingAdvance() {
        launch(environment: ["ATHKAR_UITEST_ADVANCE_DELAY_MS": "2500"])
        tapCard()
        openIndex()
        RunLoop.current.run(until: Date().addingTimeInterval(3.5))
        XCTAssertTrue(row("morning-01").isSelected, "the advance moved the deck behind the index")
        closeIndex()
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        expectPosition(1, of: 26)
        expectLabel(counter, "ذكر ١، تمت قراءته")

        nextButton.tap()
        expectPosition(2, of: 26)
        tapCard(3)
        openIndex()
        row("morning-01").tap()
        expectPosition(1, of: 26)
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        expectPosition(1, of: 26)
    }

    /// Midnight passes with the index open: the choice belonged to the earlier day, so the deck stays on the new
    /// day's first card.
    func testRolloverWhileTheIndexIsOpenKeepsTheNewDaysCard() throws {
        let clock = try makeDayClock()
        launch(environment: ["ATHKAR_UITEST_DAY_OFFSET_FILE": clock.path])
        tapCard()
        expectPosition(2, of: 26)
        tapCard(3)
        expectPosition(3, of: 26)
        openIndex()
        XCTAssertTrue(row("morning-02").isEnabled)
        try setDayOffset(1, clock)
        row("morning-02").tap()
        XCTAssertTrue(wait { !self.app.navigationBars[Self.adhkarIndex].exists })
        expectPosition(1, of: 26)
        expectLabel(summary, "٠ من ٢٦ ذكرًا")
        expectLabel(counter, "ذكر ١، لم يُعلَّم كمقروء")
    }

    /// A review row shows its warning, no counter, and never locks the rows after it.
    func testReviewRowNeverLocksTheIndex() throws {
        let pack = try makeContentPack(morning: ["morning-05", "review", "morning-06"], evening: ["evening-05"],
                                       ruqyah: ["qaf-1-8"])
        launch(environment: ["ATHKAR_UITEST_CONTENT_DIR": pack.path])
        openIndex()
        XCTAssertFalse(row("morning-90").isEnabled)
        expectLabel(lockNote, "يُتاح بعد إكمال الذكر ١")
        closeIndex()

        tapCard()
        expectPosition(2, of: 3)
        openIndex()
        XCTAssertEqual(row("morning-90").label, "ذكر ٢، لم يُعلَّم كمقروء، بحاجة إلى مراجعة")
        XCTAssertTrue(row("morning-90").isSelected)
        XCTAssertTrue(row("morning-06").isEnabled, "past the review item")
        row("morning-06").tap()
        expectPosition(3, of: 3)
    }

    /// For UI review: read, current and locked rows in the dark palette.
    func testDarkIndexScreenshot() {
        launch()
        openSettings()
        choose("داكن", in: "settings.theme")
        closeSettings()
        tapCard()
        tapCard(3)
        expectPosition(3, of: 26)
        shot("deck-position-dark")
        openIndex()
        shot("deck-index-dark")
    }

    /// The position stays whole at the largest standard size (the deck's cap), and the index rows grow and stay
    /// usable at the largest accessibility size.
    func testLargestTextSizesKeepThePositionAndRowsUsable() {
        launch(contentSize: "UICTContentSizeCategoryXXXL")
        expectPosition(1, of: 26)
        XCTAssertTrue(position.isHittable)
        XCTAssertTrue(previousButton.isHittable)
        XCTAssertTrue(nextButton.isHittable)
        shot("deck-position-xxxl")
        app.terminate()

        launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        openIndex()
        XCTAssertTrue(row("morning-01").isHittable)
        XCTAssertGreaterThanOrEqual(row("morning-01").frame.height, 44)
        shot("deck-index-ax-xxxl")
        XCTAssertFalse(revealRow("morning-25").isEnabled)
        closeIndex()
    }

    // MARK: Helpers

    private func row(_ id: String) -> XCUIElement { app.buttons["deck.index.row.\(id)"] }

    /// The note above the locked rows, a combined element whose type the query does not assume.
    private var lockNote: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "deck.index.lock").firstMatch
    }

    private func openIndex(_ title: String = DeckIndexUITests.adhkarIndex, file: StaticString = #filePath,
                           line: UInt = #line) {
        position.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3), title, file: file, line: line)
    }

    private func closeIndex(file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["deck.index.close"].tap()
        XCTAssertTrue(wait { !self.app.buttons["deck.index.close"].exists }, "index still open", file: file, line: line)
    }

    /// Scrolls the index until the row is on screen (the list builds its rows lazily).
    @discardableResult
    private func revealRow(_ id: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = row(id)
        let list = app.scrollViews["deck.index.list"]
        for _ in 0..<10 where !(element.exists && element.isHittable) { list.swipeUp() }
        for _ in 0..<10 where !(element.exists && element.isHittable) { list.swipeDown() }
        XCTAssertTrue(element.exists && element.isHittable, "row \(id)", file: file, line: line)
        return element
    }

    /// `launch()` at a Dynamic Type size, answering the long-order question with «لا، أبقِ الترتيب».
    private func launch(contentSize: String) {
        app = XCUIApplication()
        app.launchArguments = ["--reset-data", "-UIPreferredContentSizeCategoryName", contentSize]
        app.launch()
        XCTAssertTrue(app.buttons["header.more"].firstMatch.waitForExistence(timeout: 10))
        let alert = app.alerts["تأجيل الأذكار الطويلة؟"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "long-order question")
        alert.buttons[Self.keepOrder].tap()
        XCTAssertTrue(wait { !alert.exists })
    }

    private func shot(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
