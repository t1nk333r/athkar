import XCTest

/// «أيقونة التطبيق» in الإعدادات: الأفق, then back to الباء. الباء is an alternate copy of the primary icon, so the way
/// back is an ordinary icon change and never `setAlternateIconName(nil)`. iOS confirms each change in its own alert.
final class AppIconUITests: DeckTestCase {
    private func icon(_ id: String) -> XCUIElement { app.buttons["settings.appIcon.\(id)"] }

    /// Taps an icon, dismisses iOS's alert, and waits for the ring to move to it. An icon iOS already shows takes no
    /// change and no alert, as on a retried run.
    private func choose(_ id: String) {
        let tile = reveal(icon(id))
        XCTAssertTrue(tile.exists, id)
        tile.tap()
        let failure = app.alerts["تعذّر تغيير الأيقونة"]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let settled = wait(timeout: 10) {
            if failure.exists { return true }
            for alert in [app.alerts.firstMatch, springboard.alerts.firstMatch] where alert.exists {
                alert.buttons.firstMatch.tap()
            }
            return tile.isSelected && !app.alerts.firstMatch.exists
        }
        XCTAssertFalse(failure.exists, "iOS refused «\(id)»")
        XCTAssertTrue(settled, "«\(id)» is ringed")
    }

    func testHorizonAndBackToTheLetter() {
        launch()
        openSettings()
        choose("horizon")
        XCTAssertFalse(icon("letter").isSelected)
        choose("letter")
        XCTAssertFalse(icon("horizon").isSelected)

        // الإعدادات reads the icon from iOS each time it opens.
        closeSettings()
        openSettings()
        XCTAssertTrue(icon("letter").waitForExistence(timeout: 3))
        XCTAssertTrue(icon("letter").isSelected)
    }
}
