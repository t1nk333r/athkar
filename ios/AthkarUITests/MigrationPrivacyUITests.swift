import XCTest

/// Slice 7 in الإعدادات and from outside the app: «تصدير نسخة احتياطية» reaches the share sheet, «حذف كل البيانات» asks
/// twice and leaves «اليوم» empty, «الخصوصية» and «حول التطبيق» show their content, an `athkar://` URL opens its
/// deck, and the first-launch import offer can be closed.
final class MigrationPrivacyUITests: DeckTestCase {
    private func openOther(_ section: String) {
        if app.buttons["header.back"].exists { app.buttons["header.back"].tap() }
        app.buttons["tab.other"].tap()
        let cell = app.buttons["other.\(section)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 3), section)
        cell.tap()
    }

    /// Scrolls the settings form until `element` can be tapped.
    private func scrolledTo(_ element: XCUIElement) -> XCUIElement {
        let form = app.collectionViews.firstMatch
        for _ in 0..<12 where !(element.exists && element.isHittable) { form.swipeUp() }
        XCTAssertTrue(element.exists, element.identifier)
        return element
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    func testExportStartsWithoutTheLocationAndReachesTheShareSheet() {
        launch()
        openSettings()
        scrolledTo(app.buttons["settings.backupExport"]).tap()
        XCTAssertTrue(app.navigationBars["النسخة الاحتياطية"].waitForExistence(timeout: 3))
        let location = app.switches["export.includeLocation"]
        XCTAssertTrue(location.waitForExistence(timeout: 3))
        XCTAssertEqual(location.value as? String, "0", "the location is left out unless switched on")
        app.buttons["export.share"].tap()
        let sheet = app.otherElements["export.shareSheet"]
        let activity = app.otherElements["ActivityListView"]
        XCTAssertTrue(wait(timeout: 10) { sheet.exists || activity.exists }, "the share sheet")
        XCTAssertFalse(element("export.error").exists)
    }

    func testDeleteAllAsksTwiceThenLeavesTodayEmpty() {
        launch()
        openOther("today")
        let fajr = app.buttons["tracker.row.fajr"]
        XCTAssertTrue(fajr.waitForExistence(timeout: 3))
        app.buttons["tracker.log.fajr"].tap()
        XCTAssertTrue(wait { (fajr.value as? String) == "صلّيتُها" })

        openSettings()
        let delete = scrolledTo(app.buttons["settings.deleteAll"])
        // The first question can be cancelled, and nothing is deleted.
        delete.tap()
        let first = app.alerts["حذف كل البيانات؟"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        first.buttons["إلغاء"].tap()
        XCTAssertTrue(wait { !first.exists })

        delete.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        first.buttons["متابعة"].tap()
        let second = app.alerts["تأكيد الحذف"]
        XCTAssertTrue(second.waitForExistence(timeout: 3), "a second confirmation")
        second.buttons["حذف كل البيانات"].tap()
        XCTAssertTrue(wait(timeout: 6) { !self.app.navigationBars["الإعدادات"].exists }, "settings close")

        openOther("today")
        XCTAssertTrue(fajr.waitForExistence(timeout: 3))
        for prayer in ["fajr", "dhuhr", "asr", "maghrib", "isha"] {
            XCTAssertEqual(app.buttons["tracker.row.\(prayer)"].value as? String, "لم تُسجَّل", prayer)
        }
        // Nothing comes back after a relaunch.
        launch(reset: false, answer: "لا، أبقِ الترتيب")
        openOther("today")
        XCTAssertTrue(fajr.waitForExistence(timeout: 3))
        XCTAssertEqual(fajr.value as? String, "لم تُسجَّل")
    }

    func testPrivacyAndAboutShowTheirContent() {
        launch()
        openSettings()
        scrolledTo(app.buttons["settings.privacy"]).tap()
        XCTAssertTrue(app.navigationBars["الخصوصية"].waitForExistence(timeout: 3))
        // In order down the page, which can be longer than the screen.
        for id in ["device", "location", "reminders", "widget", "backups", "delete"] {
            let section = scrolledTo(element("privacy.\(id)"))
            if id == "location" { XCTAssertTrue(section.label.contains("منزلتين عشريتين")) }
        }
        app.navigationBars["الخصوصية"].buttons.firstMatch.tap()

        scrolledTo(app.buttons["settings.about"]).tap()
        XCTAssertTrue(app.navigationBars["حول التطبيق"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("about.content.adhkar").waitForExistence(timeout: 3))
        XCTAssertFalse((element("about.content.adhkar").value as? String ?? "").isEmpty)
        // In order down the page: each pack has a row, so the sources below them can start past the screen.
        for id in ["appVersion", "content.adhkar", "content.ruqyah", "content.salawat", "content.sleep", "content.suwar",
                   "adhkar", "quran", "fonts", "prayerTimes", "prohibitedTimes"] {
            XCTAssertTrue(scrolledTo(element("about.\(id)")).exists, id)
        }
    }

    /// `athkar://ruqyah` opens the ruqyah deck over the settings sheet.
    func testADeepLinkOpensItsDeck() {
        launch()
        openSettings()
        app.open(URL(string: "athkar://ruqyah")!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirm = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "فتح"])).firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        let back = app.buttons["header.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 6), "a section of أخرى")
        XCTAssertEqual(back.value as? String, "رقية القرين")
        XCTAssertTrue(wait { !self.app.navigationBars["الإعدادات"].exists }, "the settings sheet closed")
    }

    /// On a fresh install the أخرى list offers the web import once; closing it keeps it closed after a relaunch.
    func testTheFirstLaunchImportOfferCanBeClosed() {
        launch(environment: ["ATHKAR_UITEST_IMPORT_OFFER": "1"])
        app.buttons["tab.other"].tap()
        let offer = app.buttons["other.importOffer"]
        XCTAssertTrue(offer.waitForExistence(timeout: 3))
        app.buttons["other.importOffer.close"].tap()
        XCTAssertTrue(wait { !offer.exists })
        launch(reset: false, answer: nil, environment: ["ATHKAR_UITEST_IMPORT_OFFER": "1"])
        app.buttons["tab.other"].tap()
        XCTAssertTrue(app.buttons["other.ruqyah"].waitForExistence(timeout: 3))
        XCTAssertFalse(offer.waitForExistence(timeout: 2))
    }
}
