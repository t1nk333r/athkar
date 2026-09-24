import XCTest

/// Light and dark RTL screenshots of the adhkar deck, a ruqyah page (at the three text sizes) and the completion
/// dialog, written to /tmp/slice4-shots/ and attached to the test result.
final class ScreenshotUITests: DeckTestCase {
    private let directory = URL(fileURLWithPath: "/tmp/slice4-shots", isDirectory: true)

    func testCaptureDeckRuqyahAndCompletion() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        launch()

        // A ruqyah page mid-count: segment 4 (سورة ق ٢٣–٢٩, seven readings), three read.
        selectTab("ruqyah")
        next(3, count: 15, from: 1, noun: "المقطع")
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
                expectPosition(4, of: 15, noun: "المقطع")
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

    /// From the counter's spoken label: «ذكر ٢، تم تكراره ١ من أصل ٣ مرات» leaves 2; a single item leaves 1.
    private func remainingTaps() -> Int {
        let label = counter.label
        guard let done = label.range(of: "تم تكراره "), let of = label.range(of: " من أصل "),
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
