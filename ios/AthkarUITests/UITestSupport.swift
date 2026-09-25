import CryptoKit
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
    func launch(reset: Bool = true, answer: String? = keepOrder, environment: [String: String] = [:]) {
        app = XCUIApplication()
        app.launchArguments = reset ? ["--reset-data"] : []
        app.launchEnvironment = environment
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

    // MARK: Test hooks (Debug builds only)

    /// A file whose number of days the app adds to today (`ATHKAR_UITEST_DAY_OFFSET_FILE`), starting at 0 and
    /// removed after the test. Pass `["ATHKAR_UITEST_DAY_OFFSET_FILE": clock.path]` to `launch`.
    func makeDayClock() throws -> URL {
        let clock = URL(fileURLWithPath: "/tmp/athkar-uitest-day-\(UUID().uuidString).txt")
        try setDayOffset(0, clock)
        addTeardownBlock { try? FileManager.default.removeItem(at: clock) }
        return clock
    }

    /// Moves the running app's date; it notices at the next rollover check (tap, reset, foreground…).
    func setDayOffset(_ days: Int, _ clock: URL) throws {
        try String(days).write(to: clock, atomically: true, encoding: .utf8)
    }

    /// Writes a small content pack built from the repository's packs (`ATHKAR_UITEST_CONTENT_DIR`), removed after
    /// the test. `morning`, `evening` and `ruqyah` pick items and segments by ID, in that order; an entry of
    /// `review` puts the review item `morning-90` there.
    func makeContentPack(morning: [String], evening: [String], ruqyah: [String]) throws -> URL {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("content")
        func object(_ name: String) throws -> [String: Any] {
            let data = try Data(contentsOf: source.appendingPathComponent(name))
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], name)
        }
        func pick(_ ids: [String], from items: [[String: Any]]) throws -> [[String: Any]] {
            try ids.map { id in
                if id == "review" { return Self.reviewItem }
                return try XCTUnwrap(items.first { $0["id"] as? String == id }, id)
            }
        }

        var manifest = try object("manifest.json")
        var packs = try XCTUnwrap(manifest["packs"] as? [String: [String: Any]])
        var adhkar = try object(try XCTUnwrap(packs["adhkar"]?["file"] as? String))
        var periods = try XCTUnwrap(adhkar["periods"] as? [String: [[String: Any]]])
        periods["morning"] = try pick(morning, from: periods["morning"] ?? [])
        periods["evening"] = try pick(evening, from: periods["evening"] ?? [])
        adhkar["periods"] = periods
        var ruqyahPack = try object(try XCTUnwrap(packs["ruqyah"]?["file"] as? String))
        ruqyahPack["segments"] = try pick(ruqyah, from: ruqyahPack["segments"] as? [[String: Any]] ?? [])

        let directory = URL(fileURLWithPath: "/tmp/athkar-uitest-pack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        for (packId, pack) in [("adhkar", adhkar), ("ruqyah", ruqyahPack)] {
            let data = try JSONSerialization.data(withJSONObject: pack)
            let file = try XCTUnwrap(packs[packId]?["file"] as? String)
            try data.write(to: directory.appendingPathComponent(file))
            packs[packId]?["sha256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        manifest["packs"] = packs
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        return directory
    }

    static let reviewTitle = "ذكر قيد المراجعة"
    static let reviewCopy = "يُراجَع نصه ومصدره قبل اعتماده."

    /// A review item as `content/schema/adhkar.schema.json` allows it: `text` and `details` are required of every
    /// item, but the card shows `reviewTitle` and `reviewCopy`.
    static let reviewItem: [String: Any] = [
        "id": "morning-90", "kind": "review", "review": true, "text": "نص لا يظهر على البطاقة", "details": [],
        "reviewTitle": reviewTitle, "reviewCopy": reviewCopy,
    ]
}
