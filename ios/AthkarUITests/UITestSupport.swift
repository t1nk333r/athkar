import XCTest

/// Arabic-Indic digits, as the app writes every number (`Intl.NumberFormat("ar-EG")`).
func ar(_ value: Int) -> String {
    String(String(value).map { character in
        guard let digit = character.wholeNumberValue else { return character }
        return Character(Unicode.Scalar(0x0660 + UInt32(digit))!)
    })
}

/// Launching, answering the long-order question and reading the deck, shared by the deck UI tests.
@MainActor
class DeckTestCase: XCTestCase {
    var app: XCUIApplication!

    static let keepOrder = "لا، أبقِ الترتيب"
    static let moveLongLast = "نعم، أخّرها"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Launches the app, from an empty database unless `reset` is false, and answers the one-time long-order
    /// question when `answer` is given (it is asked 0.7 s after the first launch).
    func launch(reset: Bool = true, answer: String? = keepOrder) {
        app = XCUIApplication()
        app.launchArguments = reset ? ["--reset-data"] : []
        app.launch()
        XCTAssertTrue(app.staticTexts["title"].waitForExistence(timeout: 10))
        if let answer {
            let alert = app.alerts["تأجيل الأذكار الطويلة؟"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5), "long-order question")
            alert.buttons[answer].tap()
            XCTAssertTrue(wait { !alert.exists })
        }
    }

    // MARK: Elements

    var tapTarget: XCUIElement { app.buttons["deck.card.tap"] }
    var counter: XCUIElement { app.descendants(matching: .any).matching(identifier: "deck.card.counter").firstMatch }
    var position: XCUIElement { app.staticTexts["deck.position"] }
    var summary: XCUIElement { app.staticTexts["summary.copy"] }
    var nextButton: XCUIElement { app.buttons["deck.next"] }
    var previousButton: XCUIElement { app.buttons["deck.previous"] }
    var resetCardButton: XCUIElement { app.buttons["deck.card.reset"] }
    var headerReset: XCUIElement { app.buttons["header.reset"] }

    func card(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "deck.card.\(id)").firstMatch
    }

    // MARK: Waiting

    /// Polls `condition` every 50 ms (XCTest predicate expectations poll once a second).
    @discardableResult
    func wait(timeout: TimeInterval = 4, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    func expectLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 4,
                     file: StaticString = #filePath, line: UInt = #line) {
        let matched = wait(timeout: timeout) { element.exists && element.label == label }
        XCTAssertTrue(matched, "expected «\(label)», found «\(element.exists ? element.label : "<missing>")»",
                      file: file, line: line)
    }

    func expectPosition(_ index: Int, of count: Int, noun: String = "الذكر", file: StaticString = #filePath,
                        line: UInt = #line) {
        expectLabel(position, "\(noun) \(ar(index)) من \(ar(count))", file: file, line: line)
    }

    // MARK: Actions

    /// Taps the current card `times` times.
    func tapCard(_ times: Int = 1) {
        for _ in 0..<times { tapTarget.tap() }
    }

    func openSettings() {
        app.buttons["header.settings"].tap()
        XCTAssertTrue(app.navigationBars["الإعدادات"].waitForExistence(timeout: 3))
    }

    func closeSettings() {
        app.buttons["settings.close"].tap()
        XCTAssertTrue(wait { !app.navigationBars["الإعدادات"].exists })
    }

    /// Flips a settings switch (the control itself, not its row) and waits for the new value.
    func toggle(_ identifier: String, to on: Bool) {
        let row = reveal(app.switches[identifier])
        XCTAssertTrue(row.exists, identifier)
        if isOn(row) == on { return }
        let control = row.switches.firstMatch.exists ? row.switches.firstMatch : row
        control.tap()
        XCTAssertTrue(wait { isOn(row) == on }, "\(identifier) did not switch")
    }

    func isOn(_ element: XCUIElement) -> Bool {
        (element.value as? String) == "1"
    }

    /// Scrolls the settings form until `element` is on screen (the form builds rows lazily).
    @discardableResult
    func reveal(_ element: XCUIElement) -> XCUIElement {
        let form = app.collectionViews.firstMatch
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            form.swipeUp()
        }
        return element
    }

    func choose(_ option: String, in identifier: String) {
        let control = app.segmentedControls[identifier]
        XCTAssertTrue(control.waitForExistence(timeout: 3), identifier)
        control.buttons[option].tap()
        XCTAssertTrue(wait { control.buttons[option].isSelected }, "\(identifier) → \(option)")
    }

    func selectTab(_ id: String) {
        app.buttons["tab.\(id)"].tap()
    }

    /// Settings → manual completion of the morning, so the deck can be browsed freely.
    func markMorningCompleteManually() {
        openSettings()
        toggle("settings.manual.morning", to: true)
        closeSettings()
    }

    /// «التالي» `times` times, waiting for each card.
    func next(_ times: Int, count: Int, from start: Int, noun: String = "الذكر") {
        for step in 1...times {
            nextButton.tap()
            expectPosition(start + step, of: count, noun: noun)
        }
    }

    func chooseTarget(_ target: Int) {
        app.buttons["deck.card.target"].tap()
        let option = app.buttons[ar(target)].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3), "target \(target)")
        option.tap()
    }
}
