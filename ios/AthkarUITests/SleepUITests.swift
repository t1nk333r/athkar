import XCTest

/// «أذكار النوم» in أخرى: the sleep pack's items, Ayat al-Kursi first and the night waking dhikr last, with no counter.
final class SleepUITests: DeckTestCase {
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The section opens from the list and shows its items; its title leads back to the list.
    func testOpensThePageFromTheList() {
        launch()
        app.buttons["tab.other"].tap()
        let row = app.buttons["other.sleep"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.isEnabled, "the section opens")
        XCTAssertEqual(row.value as? String, "قبل النوم وفي الليل")
        row.tap()

        let first = element("sleep.sleep-01")
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(first.label.contains("آية الكرسي"), first.label)
        XCTAssertTrue(element("sleep.sleep-04").label.contains("ثلاث مرات"), element("sleep.sleep-04").label)
        XCTAssertTrue(element("sleep.sleep-12").label.contains("الملك"), "al-Mulk comes from the suwar pack")
        XCTAssertTrue(element("sleep.sleep-17").exists, "the last item is on the page")

        app.buttons["header.back"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
    }
}
