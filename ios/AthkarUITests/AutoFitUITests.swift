import XCTest

/// NATIVE_APP_PLAN.md §10.2: every ruqyah page fits its card without scrolling at the three text sizes. Run it on
/// the smallest simulator (iPhone SE, 375 × 667 pt). A card that fits shows one of the fit steps
/// (`deck.card.text.fit-N`); one that does not falls back to the scroll view `deck.card.overflow`.
final class AutoFitUITests: DeckTestCase {
    func testRuqyahPagesFitWithoutScrollingAtEveryTextSize() {
        launch()
        let screen = app.windows.firstMatch.frame.size
        var report: [String] = ["screen \(Int(screen.width))×\(Int(screen.height)) pt"]
        var index = 1
        for (pass, (size, name)) in [("صغير", "small"), ("متوسط", "medium"), ("كبير", "large")].enumerated() {
            openSettings()
            choose(size, in: "settings.textSize")
            closeSettings()
            selectTab("ruqyah")
            // Walk forward on even passes and back on odd ones, so no pass starts by walking back.
            let order = pass.isMultiple(of: 2) ? Array(1...15) : Array((1...15).reversed())
            var steps: [Int: String] = [:]
            for (visit, segment) in order.enumerated() {
                if visit > 0 {
                    (segment > index ? nextButton : previousButton).tap()
                }
                index = segment
                expectPosition(segment, of: 15, noun: "المقطع")
                let text = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'deck.card.text.fit-'"))
                    .firstMatch
                let overflow = app.scrollViews["deck.card.overflow"]
                XCTAssertTrue(wait { text.exists || overflow.exists }, "\(name): segment \(segment) has no text")
                XCTAssertFalse(overflow.exists, "\(name): segment \(segment) scrolls")
                let card = tapTarget.frame
                XCTAssertTrue(card.contains(text.frame),
                              "\(name): segment \(segment) text \(text.frame) outside card \(card)")
                steps[segment] = String(text.identifier.dropFirst("deck.card.text.fit-".count))
            }
            report.append("\(name): fit step per segment 1…15 = "
                + (1...15).map { steps[$0] ?? "?" }.joined(separator: " "))
            selectTab("morning")
        }
        let summary = report.joined(separator: "\n")
        print("AUTO-FIT\n\(summary)")
        let attachment = XCTAttachment(string: summary)
        attachment.name = "auto-fit"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
