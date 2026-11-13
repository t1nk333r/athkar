import XCTest

/// «الصلاة على النبي ﷺ» in أخرى: al-Ahzab 56, the Friday virtue and the two salawat, read with no counter.
final class SalawatUITests: DeckTestCase {
    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The section opens from the list and shows its text; its title leads back to the list.
    func testOpensThePageFromTheList() {
        launch()
        app.buttons["tab.other"].tap()
        let row = app.buttons["other.salawat"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.isEnabled, "the section opens")
        let value = row.value as? String ?? ""
        XCTAssertTrue(["ليلة الجمعة", "يوم الجمعة", "صيغتان"].contains(value), value)
        row.tap()

        XCTAssertTrue(element("salawat.quran").waitForExistence(timeout: 3))
        XCTAssertTrue(element("salawat.virtue").exists)
        XCTAssertTrue(element("salawat.salawat-01").label.contains("الصلاة على النبي"), element("salawat.salawat-01").label)
        XCTAssertTrue(element("salawat.salawat-02").label.contains("الصلاة الإبراهيمية"),
                      element("salawat.salawat-02").label)
        XCTAssertEqual(element("salawat.friday").exists, value != "صيغتان", "the page names the Friday window")

        app.buttons["header.back"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
    }
}
