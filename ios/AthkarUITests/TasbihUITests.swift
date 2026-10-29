import XCTest

/// «مسبحة» as the athkar PWA's counter: a tap anywhere on the card counts, laps continue past the target, and the
/// phrase and target are chosen in their sheets.
final class TasbihUITests: DeckTestCase {
    private var surface: XCUIElement { app.buttons["tasbih.surface"] }
    private var status: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "tasbih.status").firstMatch
    }
    private var total: XCUIElement { app.staticTexts["tasbih.total"] }
    private var undoButton: XCUIElement { app.buttons["tasbih.undo"] }
    private var resetButton: XCUIElement { app.buttons["tasbih.reset"] }
    private var phraseChip: XCUIElement { app.buttons["tasbih.phrase"] }
    private var targetChip: XCUIElement { app.buttons["tasbih.target"] }

    /// Counting reaches the target, then continues in laps; «تراجع» steps back, and «إعادة» zeroes the phrase once
    /// confirmed.
    func testCountingInLapsUndoAndReset() {
        launch()
        selectTab("tasbih")
        XCTAssertTrue(surface.waitForExistence(timeout: 3))
        XCTAssertEqual(surface.label, "أضف واحدًا")
        XCTAssertEqual(surface.value as? String, "سبحان الله، ٠ من ٣٣")
        expectLabel(status, "الهدف ٣٣")
        expectLabel(total, "مجموع المسبحة اليوم: ٠")
        XCTAssertFalse(undoButton.isEnabled)
        XCTAssertFalse(resetButton.isEnabled)
        XCTAssertTrue(app.staticTexts["tasbih.hint"].exists)

        chooseCustomTarget("3")
        expectLabel(targetChip, "تغيير الهدف، الحالي: ٣")
        surface.tap()
        expectLabel(status, "١ من ٣")
        XCTAssertTrue(undoButton.isEnabled)
        surface.tap()
        surface.tap()
        expectLabel(status, "بلغت الهدف")
        XCTAssertEqual(surface.value as? String, "سبحان الله، ٣ من ٣")
        surface.tap()
        expectLabel(status, "الدورة ٢: ١ من ٣")
        undoButton.tap()
        expectLabel(status, "بلغت الهدف")
        expectLabel(total, "مجموع المسبحة اليوم: ٣")

        XCTAssertEqual(resetButton.label, "إعادة عدّ سبحان الله إلى الصفر")
        resetButton.tap()
        let alert = app.alerts["إعادة عدّ سبحان الله؟"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "the reset asks first")
        alert.buttons["إلغاء"].tap()
        XCTAssertTrue(wait { !alert.exists })
        expectLabel(status, "بلغت الهدف")
        resetButton.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["إعادة"].tap()
        expectLabel(status, "الهدف ٣")
        expectLabel(total, "مجموع المسبحة اليوم: ٠")
        XCTAssertFalse(undoButton.isEnabled)
    }

    /// A suggested phrase is chosen, a typed one is saved and chosen, and deleting it keeps its counts in the day's
    /// total.
    func testPhrasesAreChosenSavedAndDeleted() {
        launch()
        selectTab("tasbih")
        XCTAssertTrue(phraseChip.waitForExistence(timeout: 3))
        XCTAssertEqual(phraseChip.label, "اختيار الذكر، الحالي: سبحان الله")

        phraseChip.tap()
        let hamd = app.buttons["tasbih.preset.hamd"]
        XCTAssertTrue(hamd.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tasbih.preset.subhan"].isSelected)
        hamd.tap()
        expectLabel(phraseChip, "اختيار الذكر، الحالي: الحمد لله")
        surface.tap()
        surface.tap()

        phraseChip.tap()
        let input = app.textFields["tasbih.custom.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["tasbih.custom.add"].isEnabled, "nothing typed yet")
        input.tap()
        input.typeText("Ya Rabb")
        app.buttons["tasbih.custom.add"].tap()
        expectLabel(phraseChip, "اختيار الذكر، الحالي: Ya Rabb")
        surface.tap()
        expectLabel(total, "مجموع المسبحة اليوم: ٣")

        phraseChip.tap()
        let saved = app.buttons["tasbih.custom.0"]
        XCTAssertTrue(saved.waitForExistence(timeout: 3))
        XCTAssertEqual(saved.label, "Ya Rabb، اليوم ١")
        XCTAssertTrue(saved.isSelected)
        XCTAssertEqual(app.buttons["tasbih.preset.hamd"].label, "الحمد لله، اليوم ٢")
        app.buttons["tasbih.custom.0.delete"].tap()
        XCTAssertTrue(wait { !saved.exists }, "deleting keeps the sheet open")
        app.buttons["tasbih.phrases.close"].tap()
        expectLabel(phraseChip, "اختيار الذكر، الحالي: سبحان الله")
        expectLabel(total, "مجموع المسبحة اليوم: ٣")
    }

    /// A target outside ١–٩٩٩٩ is refused in place; «بلا هدف», the counts and the phrase survive a relaunch; the
    /// header's «تقدم اليوم» asks first, then clears today's counts and keeps the target.
    func testTargetSurvivesRelaunchAndTheDayResetKeepsIt() {
        launch()
        selectTab("tasbih")
        XCTAssertTrue(targetChip.waitForExistence(timeout: 3))
        targetChip.tap()
        app.buttons["tasbih.target.custom"].tap()
        let input = app.textFields["tasbih.target.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.typeText("10000")
        app.buttons["tasbih.target.save"].tap()
        XCTAssertTrue(app.staticTexts["tasbih.target.error"].waitForExistence(timeout: 3))
        app.buttons["tasbih.target.cancel"].tap()
        expectLabel(targetChip, "تغيير الهدف، الحالي: ٣٣")

        targetChip.tap()
        let none = app.buttons["tasbih.target.none"]
        XCTAssertTrue(none.waitForExistence(timeout: 3))
        none.tap()
        expectLabel(targetChip, "تغيير الهدف، الحالي: بلا هدف")
        expectLabel(status, "بلا هدف")
        surface.tap()
        surface.tap()
        XCTAssertEqual(surface.value as? String, "سبحان الله، ٢، بلا هدف")

        app.terminate()
        launch(reset: false, answer: nil)
        selectTab("tasbih")
        XCTAssertTrue(surface.waitForExistence(timeout: 3))
        XCTAssertTrue(wait { (self.surface.value as? String) == "سبحان الله، ٢، بلا هدف" }, "the stored count")
        expectLabel(targetChip, "تغيير الهدف، الحالي: بلا هدف")

        app.buttons["header.back"].tap()
        XCTAssertTrue(app.buttons["other.tasbih"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["other.tasbih"].value as? String, "اليوم: ٢")
        app.buttons["other.tasbih"].tap()
        XCTAssertTrue(surface.waitForExistence(timeout: 3))

        headerReset.tap()
        app.buttons["reset.day"].tap()
        let alert = app.alerts["إعادة تقدم اليوم؟"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "today's counts cannot be rebuilt: it asks first")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "(٢)")).count > 0)
        alert.buttons["إلغاء"].tap()
        XCTAssertTrue(wait { !alert.exists })
        expectLabel(total, "مجموع المسبحة اليوم: ٢")

        headerReset.tap()
        app.buttons["reset.day"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["إعادة"].tap()
        expectLabel(total, "مجموع المسبحة اليوم: ٠")
        expectLabel(targetChip, "تغيير الهدف، الحالي: بلا هدف")
        XCTAssertTrue(wait { !self.resetEnabled() }, "nothing left to reset")
    }

    /// «الهدف» → «عدد آخر», typed and saved.
    private func chooseCustomTarget(_ value: String) {
        targetChip.tap()
        let custom = app.buttons["tasbih.target.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 3))
        custom.tap()
        let input = app.textFields["tasbih.target.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.typeText(value)
        app.buttons["tasbih.target.save"].tap()
        XCTAssertTrue(wait { !input.exists }, "the sheet closes")
    }
}
