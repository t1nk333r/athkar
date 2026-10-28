import XCTest

/// «سور» as the athkar PWA's «سور» tab: one section per sura, picked by its chip, one card per page.
final class SuwarUITests: DeckTestCase {
    /// A page is read once and the deck moves on; «التالي» waits for it. The last unread page completes the sura and
    /// opens its dialog with «تم» alone; a page reset reopens it, and the أخرى row counts the suras complete today.
    func testPagesAreReadOnceAndTheLastCompletesTheSura() {
        launch()
        selectTab("suwar")
        XCTAssertTrue(sectionChip("kahf").waitForExistence(timeout: 3))
        XCTAssertTrue(sectionChip("kahf").isSelected, "opens on الكهف")
        XCTAssertEqual(sectionChip("kahf").label, "سورة الكهف")
        expectPosition(1, of: 34, noun: "الصفحة")
        expectLabel(summary, "٠ من ٣٤ صفحة")
        expectLabel(counter, "الصفحة ١ من سورة الكهف، الآيات ١ – ٤، لم تُعلَّم كمقروءة")
        XCTAssertFalse(nextButton.isEnabled, "next waits for the page to be read")
        XCTAssertTrue(card("kahf-1-4").exists)

        tapCard()
        expectPosition(2, of: 34, noun: "الصفحة")
        expectLabel(summary, "١ من ٣٤ صفحة")
        previousButton.tap()
        expectPosition(1, of: 34, noun: "الصفحة")
        expectLabel(counter, "الصفحة ١ من سورة الكهف، الآيات ١ – ٤، تمت قراءتها")
        XCTAssertFalse(tapTarget.isEnabled, "a read page no longer counts")
        XCTAssertTrue(nextButton.isEnabled)

        selectSection("mulk")
        expectPosition(1, of: 7, noun: "الصفحة")
        expectLabel(summary, "٠ من ٧ صفحة")
        for page in 1...7 {
            expectPosition(page, of: 7, noun: "الصفحة")
            tapCard()
        }
        let title = app.staticTexts["completion.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4), "sura dialog")
        XCTAssertEqual(title.label, "اكتملت قراءة سورة الملك بحمد الله")
        XCTAssertTrue(app.staticTexts["completion.time"].label.hasPrefix("وقت الإكمال: "))
        XCTAssertFalse(app.buttons["completion.primary"].exists, "«تم» alone")
        app.buttons["completion.dismiss"].tap()
        XCTAssertTrue(wait { !title.exists })
        expectLabel(summary, "اكتملت سورة الملك اليوم")
        XCTAssertEqual(sectionChip("mulk").label, "سورة الملك، مكتملة اليوم")
        expectPosition(7, of: 7, noun: "الصفحة")
        XCTAssertFalse(nextButton.isEnabled, "the last page")

        // `resetSuraPage` asks nothing.
        resetCardButton.tap()
        expectLabel(summary, "٦ من ٧ صفحة")
        XCTAssertEqual(sectionChip("mulk").label, "سورة الملك")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        tapCard()
        XCTAssertTrue(title.waitForExistence(timeout: 4), "completed again")
        app.buttons["completion.dismiss"].tap()

        app.buttons["header.back"].tap()
        XCTAssertTrue(app.buttons["other.suwar"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["other.suwar"].label, "سور")
        XCTAssertEqual(app.buttons["other.suwar"].value as? String, "١ من ٥ سور")
        app.buttons["other.suwar"].tap()
        XCTAssertTrue(sectionChip("mulk").isSelected)
    }

    /// The shown sura and today's pages survive a relaunch, and the sura reopens on its first unread page; «تقدم
    /// اليوم» clears today's pages and keeps the sura.
    func testShownSuraSurvivesRelaunchAndReset() {
        launch()
        selectTab("suwar")
        selectSection("yasin")
        tapCard()
        expectPosition(2, of: 16, noun: "الصفحة")

        app.terminate()
        launch(reset: false, answer: nil)
        selectTab("suwar")
        XCTAssertTrue(wait { self.sectionChip("yasin").isSelected }, "the stored sura")
        expectPosition(2, of: 16, noun: "الصفحة")
        expectLabel(summary, "١ من ١٦ صفحة")

        headerReset.tap()
        app.buttons["reset.day"].tap()
        expectLabel(summary, "٠ من ١٦ صفحة")
        expectPosition(1, of: 16, noun: "الصفحة")
        XCTAssertTrue(sectionChip("yasin").isSelected, "a reset keeps the sura")
        XCTAssertTrue(wait { !self.resetEnabled() })
    }
}
