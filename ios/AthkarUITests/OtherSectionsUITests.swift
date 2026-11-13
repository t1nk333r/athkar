import XCTest

/// The أخرى list's two layouts: «قائمة», one section to a row, and «شبكة», two to a row. The «⋯» menu switches them,
/// and the choice outlives a relaunch.
final class OtherSectionsUITests: DeckTestCase {
    private func section(_ id: String) -> XCUIElement { app.buttons["other.\(id)"] }

    /// Picks a layout in the «⋯» menu of the أخرى list.
    private func chooseLayout(_ title: String) {
        app.buttons["header.more"].firstMatch.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 3), "«\(title)» in the «⋯» menu")
        option.tap()
        XCTAssertTrue(wait { !option.exists }, "the menu closes")
    }

    /// Whether رقية القرين and سور share a row, as the grid puts them.
    private var sideBySide: Bool {
        abs(section("ruqyah").frame.minY - section("suwar").frame.minY) < 1
    }

    func testGridAndListLayouts() {
        launch()
        app.buttons["tab.other"].tap()
        XCTAssertTrue(section("ruqyah").waitForExistence(timeout: 3))
        XCTAssertFalse(sideBySide, "the list is the default")

        chooseLayout("شبكة")
        XCTAssertTrue(wait { sideBySide }, "the grid puts two sections on a row")
        XCTAssertGreaterThan(section("ruqyah").frame.midX, section("suwar").frame.midX,
                             "the first section is at the leading edge, on the right")
        XCTAssertEqual(section("ruqyah").frame.height, section("suwar").frame.height, accuracy: 1,
                       "both sections of a row take its height")
        XCTAssertFalse(section("afterPrayer").isEnabled, "a section listed as «قريبًا» does not open")

        // A section opens from the grid, and its title leads back to the grid.
        section("tasbih").tap()
        let back = app.buttons["header.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
        XCTAssertTrue(section("ruqyah").waitForExistence(timeout: 3))
        XCTAssertTrue(sideBySide)

        app.terminate()
        launch(reset: false, answer: nil)
        app.buttons["tab.other"].tap()
        XCTAssertTrue(section("ruqyah").waitForExistence(timeout: 3))
        XCTAssertTrue(sideBySide, "the grid is kept for the next launch")

        chooseLayout("قائمة")
        XCTAssertTrue(wait { !sideBySide })
        XCTAssertLessThan(section("ruqyah").frame.minY, section("suwar").frame.minY, "one section to a row")
    }
}
