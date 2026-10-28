import XCTest

/// NATIVE_APP_PLAN.md §10.2: every ruqyah page fits its card without scrolling at the three text sizes, with the
/// default and the widest line spacing (compact lines are shorter than comfortable ones at every step). Run it on
/// the smallest simulator (iPhone SE, 375 × 667 pt). A card that fits shows one of the fit steps
/// (`deck.card.text.fit-N`); one that does not falls back to the scroll view `deck.card.overflow`.
final class AutoFitUITests: DeckTestCase {
    func testRuqyahPagesFitWithoutScrollingAtEveryTextSizeAndSpacing() {
        launch()
        let screen = app.windows.firstMatch.frame.size
        var report: [String] = ["screen \(Int(screen.width))×\(Int(screen.height)) pt"]
        // Each sura's repeats, numbered 1…15 across the pack. Every segment is read first, so «التالي» never waits
        // and each sura's chip reopens the card it showed last.
        let suwar: [(id: String, first: Int, repeats: [Int])] = [
            ("qaf", 1, [1, 1, 1, 7, 1, 1]), ("jinn", 7, [1, 1, 1, 1]), ("takwir", 11, [1, 1, 1]),
            ("kafirun", 14, [7]), ("nas", 15, [7]),
        ]
        selectTab("ruqyah")
        let dialog = app.staticTexts["completion.title"]
        for sura in suwar {
            selectSection(sura.id)
            for (index, times) in sura.repeats.enumerated() {
                expectPosition(index + 1, of: sura.repeats.count, noun: "المقطع")
                tapCard(times)
            }
            XCTAssertTrue(dialog.waitForExistence(timeout: 4), "\(sura.id) dialog")
            app.buttons["completion.dismiss"].tap()
            XCTAssertTrue(wait { !dialog.exists })
        }
        selectTab("morning")

        var pass = 0
        for (spacing, spacingName) in [("مريح", "comfortable"), ("واسع", "wide")] {
            for (size, sizeName) in [("صغير", "small"), ("متوسط", "medium"), ("كبير", "large")] {
                let name = "\(spacingName)/\(sizeName)"
                openSettings()
                choose(size, in: "settings.textSize")
                choose(spacing, in: "settings.lineSpacing")
                closeSettings()
                selectTab("ruqyah")
                // Each sura is left on its last card, so walk back on even passes and forward on odd ones: no pass
                // starts by walking.
                let backward = pass.isMultiple(of: 2)
                pass += 1
                var steps: [Int: String] = [:]
                for sura in suwar {
                    selectSection(sura.id)
                    let count = sura.repeats.count
                    let order = backward ? Array((1...count).reversed()) : Array(1...count)
                    for (visit, segment) in order.enumerated() {
                        if visit > 0 {
                            (backward ? previousButton : nextButton).tap()
                        }
                        expectPosition(segment, of: count, noun: "المقطع")
                        let number = sura.first + segment - 1
                        let text = app.staticTexts
                            .matching(NSPredicate(format: "identifier BEGINSWITH 'deck.card.text.fit-'")).firstMatch
                        let overflow = app.scrollViews["deck.card.overflow"]
                        XCTAssertTrue(wait { text.exists || overflow.exists }, "\(name): segment \(number) has no text")
                        XCTAssertFalse(overflow.exists, "\(name): segment \(number) scrolls")
                        let card = tapTarget.frame
                        XCTAssertTrue(card.contains(text.frame),
                                      "\(name): segment \(number) text \(text.frame) outside card \(card)")
                        steps[number] = String(text.identifier.dropFirst("deck.card.text.fit-".count))
                    }
                }
                report.append("\(name): fit step per segment 1…15 = "
                    + (1...15).map { steps[$0] ?? "?" }.joined(separator: " "))
                selectTab("morning")
            }
        }
        let summary = report.joined(separator: "\n")
        print("AUTO-FIT\n\(summary)")
        let attachment = XCTAttachment(string: summary)
        attachment.name = "auto-fit"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
