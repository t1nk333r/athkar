import AthkarCore
import Foundation
import SwiftUI
import XCTest
@testable import Athkar

/// The app's settings and long-order flows when SQLite refuses a change: the decks and settings keep the last saved
/// state, the failure is shown, and the same change succeeds once the database accepts writes again.
final class SettingsAppModelTests: XCTestCase {
    @MainActor
    func testFailedLongOrderToggleKeepsDecksAndFocusThenRecovers() throws {
        // The tab on screen and the adhkar period long-order keeps; the أخرى tab keeps the period shown before it.
        for (tab, active) in [(DeckID.morning, Period.morning), (.evening, .evening), (.ruqyah, .evening)] {
            let context = "\(tab) on screen"
            let support = try NativeTestSupport()
            let app = try support.makeAppModel()
            app.selection = active == .morning ? .morning : .evening
            app.selection = tab
            try prepareDecks(app)
            let before = DeckState(app)

            try rejectWrites(of: "long_order", in: support.database)
            app.setLongOrder(true)
            XCTAssertEqual(DeckState(app), before, context)
            XCTAssertEqual(app.settings.longOrder, .original, context)
            XCTAssertEqual(try support.database.settings.value(for: .longOrder), .original, context)
            XCTAssertEqual(app.failure?.contains(rejection), true, context)
            app.failure = nil

            try acceptWrites(of: "long_order", in: support.database)
            app.setLongOrder(true)
            XCTAssertNil(app.failure, context)
            XCTAssertEqual(app.settings.longOrder, .last, context)
            XCTAssertFalse(app.settings.longOrderPromptAnswered, context)
            assertLongOrderApplied(app, from: before, active: active, longLast: true, context)
            let reloaded = try support.makeAppModel()
            XCTAssertEqual(reloaded.settings.longOrder, .last, context)
            XCTAssertEqual(reloaded.morning.cards.map(\.id), app.morning.cards.map(\.id), context)
            XCTAssertEqual(reloaded.evening.cards.map(\.id), app.evening.cards.map(\.id), context)
        }
    }

    @MainActor
    func testFailedPromptDecisionKeepsDecksAndUnansweredFlagThenRecovers() throws {
        for moveLongLast in [true, false] {
            let context = "answering \(moveLongLast ? "yes" : "no")"
            let support = try NativeTestSupport()
            let app = try support.makeAppModel()
            try prepareDecks(app)
            let before = DeckState(app)

            // The answered flag is written after the order: refusing it must keep the order too.
            try rejectWrites(of: "long_order_prompt_answered", in: support.database)
            app.answerLongOrderPrompt(moveLongLast: moveLongLast)
            XCTAssertEqual(DeckState(app), before, context)
            XCTAssertEqual(app.settings.longOrder, .original, context)
            XCTAssertFalse(app.settings.longOrderPromptAnswered, context)
            XCTAssertEqual(try support.database.settings.value(for: .longOrder), .original, context)
            XCTAssertFalse(try support.database.settings.value(for: .longOrderPromptAnswered), context)
            XCTAssertEqual(app.failure?.contains(rejection), true, context)
            app.failure = nil
            // A relaunch still asks the question.
            XCTAssertFalse(try support.makeAppModel().settings.longOrderPromptAnswered, context)

            try acceptWrites(of: "long_order_prompt_answered", in: support.database)
            app.answerLongOrderPrompt(moveLongLast: moveLongLast)
            XCTAssertNil(app.failure, context)
            XCTAssertEqual(app.settings.longOrder, moveLongLast ? .last : .original, context)
            XCTAssertTrue(app.settings.longOrderPromptAnswered, context)
            assertLongOrderApplied(app, from: before, active: .morning, longLast: moveLongLast, context)
            let reloaded = try support.makeAppModel()
            XCTAssertEqual(reloaded.settings.longOrder, moveLongLast ? .last : .original, context)
            XCTAssertTrue(reloaded.settings.longOrderPromptAnswered, context)
            XCTAssertEqual(reloaded.morning.cards.map(\.id), app.morning.cards.map(\.id), context)
            XCTAssertEqual(reloaded.evening.cards.map(\.id), app.evening.cards.map(\.id), context)
        }
    }

    @MainActor
    func testSettingsBindingsRollbackAndReloadCommittedValues() throws {
        let support = try NativeTestSupport()
        let app = try support.makeAppModel()
        // SettingsView's bindings: `$settings.…` through @Bindable, and its hand-written haptics Binding.
        let settings = Bindable(app.settings)
        let theme = settings.theme
        let textSize = settings.textSize
        let lineSpacing = settings.lineSpacing
        let homePrayerRow = settings.homePrayerRow
        let haptics = Binding(get: { app.settings.haptics }, set: { app.settings.haptics = $0 })
        let keys = ["theme", "text_size", "line_spacing", "haptics", "home_prayer_row"]

        for key in keys { try rejectWrites(of: key, in: support.database) }
        theme.wrappedValue = .dark
        textSize.wrappedValue = .large
        lineSpacing.wrappedValue = .wide
        haptics.wrappedValue = false
        homePrayerRow.wrappedValue = false
        XCTAssertEqual(theme.wrappedValue, .system)
        XCTAssertEqual(textSize.wrappedValue, .medium)
        XCTAssertEqual(lineSpacing.wrappedValue, .comfortable)
        XCTAssertTrue(haptics.wrappedValue)
        XCTAssertTrue(homePrayerRow.wrappedValue)
        XCTAssertEqual(app.failure?.contains(rejection), true)
        XCTAssertEqual(try support.database.reader.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings")
        }, 0)
        app.failure = nil

        for key in keys { try acceptWrites(of: key, in: support.database) }
        theme.wrappedValue = .dark
        textSize.wrappedValue = .large
        lineSpacing.wrappedValue = .wide
        haptics.wrappedValue = false
        homePrayerRow.wrappedValue = false
        XCTAssertNil(app.failure)
        XCTAssertEqual(theme.wrappedValue, .dark)
        XCTAssertEqual(textSize.wrappedValue, .large)
        XCTAssertEqual(lineSpacing.wrappedValue, .wide)
        XCTAssertFalse(haptics.wrappedValue)
        XCTAssertFalse(homePrayerRow.wrappedValue)

        let reloaded = try support.makeAppModel().settings
        XCTAssertEqual(reloaded.theme, .dark)
        XCTAssertEqual(reloaded.textSize, .large)
        XCTAssertEqual(reloaded.lineSpacing, .wide)
        XCTAssertFalse(reloaded.haptics)
        XCTAssertFalse(reloaded.homePrayerRow)
    }

    /// Finishes each deck's first card, starts a long dhikr and looks at it, so a reorder would move the focus.
    @MainActor
    private func prepareDecks(_ app: AppModel) throws {
        for deck in [app.morning, app.evening] {
            let first = try XCTUnwrap(deck.cards.firstIndex { !$0.isReview })
            for _ in 0..<deck.cards[first].target { XCTAssertNotNil(deck.tap(cardAt: first)) }
            let long = try XCTUnwrap(deck.cards.firstIndex {
                !$0.isReview && $0.count < $0.target && $0.target >= SessionState.longDhikrThreshold
            })
            XCTAssertNotNil(deck.tap(cardAt: long))
            deck.show(long)
        }
        XCTAssertNil(app.failure)
    }

    /// `applyLongOrder` after a saved change: same cards and counters in the new order, the active period still on
    /// its card, the other period on its first unread card.
    @MainActor
    private func assertLongOrderApplied(_ app: AppModel, from before: DeckState, active: Period, longLast: Bool,
                                        _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.adhkar.longAdhkarLast, longLast, context, file: file, line: line)
        XCTAssertEqual(app.adhkar.state, before.session, context, file: file, line: line)
        for (index, period) in Period.allCases.enumerated() {
            let deck = app.deck(period == .morning ? .morning : .evening)
            let cards = deck.cards
            let previous = before.cards[index]
            XCTAssertEqual(Set(cards.map(\.id)), Set(previous.map(\.id)), context, file: file, line: line)
            if longLast {
                XCTAssertNotEqual(cards.map(\.id), previous.map(\.id), "long adhkar moved; \(context)",
                                  file: file, line: line)
            } else {
                XCTAssertEqual(cards, previous, context, file: file, line: line)
            }
            XCTAssertEqual(Dictionary(uniqueKeysWithValues: cards.map { ($0.id, [$0.count, $0.target]) }),
                           Dictionary(uniqueKeysWithValues: previous.map { ($0.id, [$0.count, $0.target]) }),
                           context, file: file, line: line)
            if period == active {
                XCTAssertEqual(cards[deck.currentIndex].id, previous[before.indices[index]].id,
                               "the active period keeps its card; \(context)", file: file, line: line)
            } else {
                let firstUnread = cards.firstIndex { !$0.isReview && $0.count < $0.target } ?? max(0, cards.count - 1)
                XCTAssertEqual(deck.currentIndex, firstUnread, "the other period restarts; \(context)",
                               file: file, line: line)
            }
        }
    }
}

// MARK: Support

private let rejection = "task009 rejected settings write"

/// What a long-order change can move: both adhkar decks' cards and focus, the session and the order flag.
private struct DeckState: Equatable {
    let cards: [[DeckCard]]
    let indices: [Int]
    let session: SessionState
    let longAdhkarLast: Bool

    @MainActor
    init(_ app: AppModel) {
        cards = [app.morning.cards, app.evening.cards]
        indices = [app.morning.currentIndex, app.evening.currentIndex]
        session = app.adhkar.state
        longAdhkarLast = app.adhkar.longAdhkarLast
    }
}

/// SQLite refuses every write of `key`, as a full or failing disk would: test-only triggers on the test's private
/// database. An upsert can reach the row through INSERT or UPDATE, so both are refused.
private func rejectWrites(of key: String, in database: AppDatabase) throws {
    try database.writer.write { db in
        for event in ["INSERT", "UPDATE"] {
            try db.execute(sql: """
                CREATE TRIGGER reject_\(event.lowercased())_\(key) BEFORE \(event) ON settings
                WHEN NEW.key = '\(key)' BEGIN SELECT RAISE(ABORT, '\(rejection)'); END
                """)
        }
    }
}

private func acceptWrites(of key: String, in database: AppDatabase) throws {
    try database.writer.write { db in
        for event in ["insert", "update"] {
            try db.execute(sql: "DROP TRIGGER reject_\(event)_\(key)")
        }
    }
}
