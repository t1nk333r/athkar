import XCTest

/// «الصلاة على النبي ﷺ» in أخرى: a reading deck (spec/sessions/deck-definition.md §12). Its opening card holds al-Ahzab
/// 56 and the Friday virtue and is never counted; each of the two salawat is read once.
final class SalawatUITests: DeckTestCase {
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The deck opens on its first salawat; the opening card before it says «اقرأ ثم اسحب» and names the Friday
    /// window. Reading both salawat completes the day, and «تقدم اليوم» clears it.
    func testTheTwoSalawatCompleteTheDay() {
        launch()
        app.buttons["tab.other"].tap()
        let row = app.buttons["other.salawat"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.isEnabled, "the section opens")
        let value = row.value as? String ?? ""
        XCTAssertTrue(["ليلة الجمعة", "يوم الجمعة", "صيغتان"].contains(value), value)
        row.tap()

        expectPosition(2, of: 3, noun: "البطاقة")
        expectLabel(summary, "٠ من ٢")
        previousButton.tap()
        expectPosition(1, of: 3, noun: "البطاقة")
        XCTAssertTrue(card("salawat-quran").exists)
        expectLabel(counter, "البطاقة ١، الآية والفضل")
        XCTAssertTrue(element("deck.card.quran").exists)
        XCTAssertTrue(element("deck.card.note").exists, "the Friday virtue")
        XCTAssertEqual(element("deck.card.friday").exists, value != "صيغتان", "the card names the Friday window")
        XCTAssertFalse(tapTarget.exists, "never counted")
        XCTAssertTrue(nextButton.isEnabled)

        nextButton.tap()
        expectPosition(2, of: 3, noun: "البطاقة")
        XCTAssertEqual(app.staticTexts["deck.card.title"].label, "الصلاة على النبي ﷺ")
        tapCard()
        expectPosition(3, of: 3, noun: "البطاقة")
        expectLabel(summary, "١ من ٢")
        tapCard()
        let title = app.staticTexts["completion.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4), "the day's dialog")
        XCTAssertEqual(title.label, "تمت الصلاة على النبي ﷺ بحمد الله")
        app.buttons["completion.dismiss"].tap()
        XCTAssertTrue(wait { !title.exists })
        expectLabel(summary, "اكتملت الصلاة على النبي ﷺ اليوم")

        headerReset.tap()
        app.buttons["reset.day"].tap()
        expectLabel(summary, "٠ من ٢")
        expectPosition(2, of: 3, noun: "البطاقة")

        app.buttons["header.back"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertEqual(row.value as? String, value, "no count today again")
    }
}
