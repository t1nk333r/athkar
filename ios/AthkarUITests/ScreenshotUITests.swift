import XCTest

/// Light and dark RTL screenshots of the adhkar deck, a ruqyah page (at the three text sizes), the completion dialog,
/// الإعدادات and أوقات الصلاة, written to /tmp/slice4-shots/ and attached to the test result.
final class ScreenshotUITests: DeckTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/slice4-shots", isDirectory: true)

    func testCaptureDeckRuqyahAndCompletion() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        launch()

        // A ruqyah page mid-count: segment 4 (سورة ق ٢٣–٢٩, seven readings), three read once 1–3 are read.
        selectTab("ruqyah")
        for segment in 1...3 {
            expectPosition(segment, of: 6, noun: "المقطع")
            tapCard()
        }
        expectPosition(4, of: 6, noun: "المقطع")
        tapCard(3)
        selectTab("morning")

        for (theme, themeName) in [("فاتح", "light"), ("داكن", "dark")] {
            for (size, sizeName) in [("صغير", "small"), ("متوسط", "medium"), ("كبير", "large")] {
                openSettings()
                choose(theme, in: "settings.theme")
                choose(size, in: "settings.textSize")
                closeSettings()
                selectTab("morning")
                shot("adhkar-deck-\(themeName)-\(sizeName)")
                selectTab("ruqyah")
                expectPosition(4, of: 6, noun: "المقطع")
                shot("ruqyah-page-\(themeName)-\(sizeName)")
            }
        }

        openSettings()
        choose("فاتح", in: "settings.theme")
        choose("متوسط", in: "settings.textSize")
        closeSettings()
        selectTab("morning")
        completeDeck(count: 26)
        XCTAssertTrue(app.staticTexts["completion.title"].waitForExistence(timeout: 4))
        shot("completion-morning-light")
        app.buttons["completion.primary"].tap()

        openSettings()
        choose("داكن", in: "settings.theme")
        closeSettings()
        expectLabel(summary, "٠ من ٢٤ ذكرًا")
        completeDeck(count: 24)
        XCTAssertTrue(app.staticTexts["completion.title"].waitForExistence(timeout: 4))
        shot("completion-evening-dark")
    }

    /// الإعدادات in light and dark: the top of the page, its middle and its end.
    func testCaptureSettings() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        launch()
        for (theme, themeName) in [("فاتح", "light"), ("داكن", "dark")] {
            openSettings()
            choose(theme, in: "settings.theme")
            shot("settings-\(themeName)-top")
            let form = app.collectionViews.firstMatch
            form.swipeUp()
            shot("settings-\(themeName)-middle")
            for _ in 0..<3 { form.swipeUp() }
            shot("settings-\(themeName)-end")
            closeSettings()
        }
    }

    /// أوقات الصلاة in light and dark, for Riyadh entered by hand: the day, the prayer counted to and the times.
    func testCapturePrayerTimes() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        launch()
        for (index, (theme, themeName)) in [("فاتح", "light"), ("داكن", "dark")].enumerated() {
            openSettings()
            choose(theme, in: "settings.theme")
            closeSettings()
            app.buttons["tab.other"].tap()
            let row = app.buttons["other.prayerTimes"]
            XCTAssertTrue(row.waitForExistence(timeout: 3))
            row.tap()
            if index == 0 {
                app.buttons["prayer.manual"].tap()
                let latitude = app.textFields["prayer.manual.latitude"]
                XCTAssertTrue(latitude.waitForExistence(timeout: 3))
                latitude.tap()
                latitude.typeText("24.71")
                let longitude = app.textFields["prayer.manual.longitude"]
                longitude.tap()
                longitude.typeText("46.68")
                app.buttons["prayer.manual.save"].tap()
            }
            XCTAssertTrue(app.descendants(matching: .any)["prayer.time.fajr"].waitForExistence(timeout: 4))
            shot("prayer-times-\(themeName)")
            app.buttons["header.back"].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 3))
        }
    }

    /// Reads every card of the current adhkar deck to its target, choosing 1 where the reader may.
    private func completeDeck(count: Int) {
        for index in 1...count {
            expectPosition(index, of: count)
            if app.buttons["deck.card.target"].exists {
                chooseTarget(1)
            }
            tapCard(remainingTaps())
        }
    }

    /// From the counter's spoken label: «ذكر ٢، كُرّر ١ من أصل ٣ مرات» leaves 2; a single item leaves 1.
    private func remainingTaps() -> Int {
        let label = counter.label
        guard let done = label.range(of: "كُرّر "), let of = label.range(of: " من أصل "),
              let times = label.range(of: " مرات")
        else { return 1 }
        return max(0, number(label[of.upperBound..<times.lowerBound]) - number(label[done.upperBound..<of.lowerBound]))
    }

    private func number(_ digits: Substring) -> Int {
        Int(String(digits.map { character in
            character.unicodeScalars.first.map { scalar in
                (0x0660...0x0669).contains(scalar.value) ? Character(String(scalar.value - 0x0660)) : character
            } ?? character
        })) ?? 0
    }

    private func shot(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let device = (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device")
            .lowercased().replacingOccurrences(of: " ", with: "-")
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(device)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let file = directory.appendingPathComponent("\(device)-\(name).png")
        XCTAssertNoThrow(try screenshot.pngRepresentation.write(to: file))
    }
}
