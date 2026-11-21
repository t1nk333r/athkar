import AthkarCore
import Foundation
import GRDB
import XCTest
@testable import AthkarModels

private let progressTable = "reading_item_progress"
private let daysTable = "reading_days"
/// A count is an upsert: rejecting both kinds of statement rejects it whether or not its row exists.
private let countWrites = ["INSERT", "UPDATE"]
/// 2026-10-01T20:00:00Z.
private let earlierCompletion = Date(timeIntervalSince1970: 1_790_884_800)

/// A reading deck shows a count, a reset or a completion only once SQLite has stored it, and never shows a day it
/// could not read. The failures are real SQLite errors in the production database (``ReadingStore``).
final class ReadingPersistenceTests: XCTestCase {
    @MainActor
    func testRejectedReadingIsNotShownAndARetryCountsItOnce() throws {
        let store = try ReadingStore()
        let deck = try store.makeDeck(.sleep)
        XCTAssertNotNil(deck.tap(cardAt: 0))
        let shown = Shown(deck)
        let stored = try store.stored(.sleep)

        try store.reject(countWrites, on: progressTable)
        XCTAssertNil(deck.tap(cardAt: 3), "no haptic, advance or announcement for an unsaved reading")
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(deck), shown)
        XCTAssertEqual(try store.stored(.sleep), stored)

        try store.allow(countWrites, on: progressTable)
        XCTAssertEqual(deck.tap(cardAt: 3), DeckChange())
        XCTAssertEqual(try store.repository.counts(.sleep, on: store.today), ["sleep-01": 1, "sleep-04": 1])
        XCTAssertEqual(store.reported.count, 1)
        try assertShowsStorage(deck, store)
    }

    /// The reading that completes the day and the day's record are one transaction: a rejected record stores neither,
    /// and the retry records the completion.
    @MainActor
    func testRejectedDayRecordRollsBackItsReadingAndTheRetryRecordsBoth() throws {
        let store = try ReadingStore()
        let deck = try store.makeDeck(.salawat)
        XCTAssertNotNil(deck.tap(cardAt: 1))
        let shown = Shown(deck)
        let stored = try store.stored(.salawat)

        try store.reject(["INSERT"], on: daysTable)
        XCTAssertNil(deck.tap(cardAt: 2), "no haptic or dialog for an unsaved completion")
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(deck), shown)
        XCTAssertFalse(deck.isComplete)
        XCTAssertEqual(try store.stored(.salawat), stored)
        XCTAssertNil(try store.repository.counts(.salawat, on: store.today)["salawat-02"])

        try store.allow(["INSERT"], on: daysTable)
        let retried = Date()
        XCTAssertEqual(deck.tap(cardAt: 2), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        let day = try XCTUnwrap(store.repository.day(.salawat, on: store.today))
        XCTAssertGreaterThanOrEqual(day.completedAt.timeIntervalSince1970, retried.timeIntervalSince1970 - 0.001)
        XCTAssertTrue(deck.isComplete)
        XCTAssertEqual(store.reported.count, 1)
        try assertShowsStorage(deck, store)
    }

    /// A rejected card reset keeps the count and the day's record: the reset and the record's deletion are one
    /// transaction.
    @MainActor
    func testRejectedCardResetKeepsTheCountAndTheRecord() throws {
        for (events, table) in [(countWrites, progressTable), (["DELETE"], daysTable)] {
            let store = try ReadingStore()
            let deck = try store.makeDeck(.salawat)
            XCTAssertNotNil(deck.tap(cardAt: 1), table)
            XCTAssertNotNil(deck.tap(cardAt: 2), table)
            XCTAssertTrue(deck.isComplete, table)
            let shown = Shown(deck)
            let stored = try store.stored(.salawat)

            try store.reject(events, on: table)
            deck.resetCard(at: 1)
            XCTAssertEqual(store.reported.count, 1, table)
            XCTAssertEqual(Shown(deck), shown, table)
            XCTAssertEqual(try store.stored(.salawat), stored, table)

            try store.allow(events, on: table)
            deck.resetCard(at: 1)
            XCTAssertFalse(deck.cards[1].isComplete, table)
            XCTAssertFalse(deck.isComplete, table)
            XCTAssertNil(try store.repository.day(.salawat, on: store.today), table)
            XCTAssertEqual(store.reported.count, 1, table)
            try assertShowsStorage(deck, store)
        }
    }

    /// A rejected تقدم اليوم / هذا الأسبوع / كل شيء changes nothing, the reader's position included; deleting the
    /// history and clearing today are one transaction.
    @MainActor
    func testRejectedScopedResetsKeepCountsHistoryAndPosition() throws {
        let cases: [(ResetScope, String)] = [
            (.day, progressTable), (.day, daysTable), (.week, progressTable), (.everything, progressTable),
            (.everything, daysTable),
        ]
        for (scope, table) in cases {
            let label = "\(scope), DELETE on \(table) rejected"
            let store = try ReadingStore()
            try store.repository.setCount(1, for: "salawat-01", in: .salawat, on: "2026-10-01",
                                          completingDayAt: earlierCompletion, at: earlierCompletion)
            let deck = try store.makeDeck(.salawat)
            XCTAssertNotNil(deck.tap(cardAt: 1), label)
            XCTAssertNotNil(deck.tap(cardAt: 2), label)
            deck.show(0)
            let shown = Shown(deck)
            let stored = try store.stored(.salawat)

            try store.reject(["DELETE"], on: table)
            XCTAssertFalse(deck.reset(scope), label)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertEqual(Shown(deck), shown, label)
            XCTAssertEqual(try store.stored(.salawat), stored, label)

            try store.allow(["DELETE"], on: table)
            XCTAssertTrue(deck.reset(scope), label)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertEqual(deck.currentIndex, 1, label)
            XCTAssertFalse(deck.isComplete, label)
            XCTAssertTrue(try store.repository.counts(.salawat, on: store.today).isEmpty, label)
            switch scope {
            case .day:
                XCTAssertTrue(deck.hasHistory, label)
                XCTAssertEqual(try store.stored(.salawat).days, 1, label)
            case .week:
                break
            case .everything:
                XCTAssertFalse(deck.canReset, label)
                XCTAssertEqual(try store.stored(.salawat).days, 0, label)
            }
            try assertShowsStorage(deck, store)
        }
    }

    /// A new day that cannot be read is not shown as empty: the deck keeps its day, and the next roll retries. A
    /// launch that cannot read its day fails rather than showing an empty one.
    @MainActor
    func testUnreadableNewDayKeepsTheCurrentDayUntilARetryLoadsIt() throws {
        let store = try ReadingStore()
        let deck = try store.makeDeck(.sleep)
        XCTAssertNotNil(deck.tap(cardAt: 0))
        // A reading already on the next date, as after moving back across a time-zone boundary.
        let next = "2026-10-15"
        try store.repository.setCount(1, for: "sleep-02", in: .sleep, on: next)
        let shown = Shown(deck)

        let tables = [progressTable, daysTable]
        for table in tables {
            try store.hide(table)
            XCTAssertThrowsError(try store.makeDeck(.sleep, on: next), table)
            deck.roll(to: next)
            try store.restore(table)
            XCTAssertEqual(Shown(deck), shown, table)
        }
        XCTAssertEqual(store.reported.count, tables.count)

        deck.roll(to: next)
        XCTAssertEqual(store.reported.count, tables.count)
        XCTAssertEqual(deck.date, next)
        XCTAssertEqual(deck.counts, ["sleep-02": 1])
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertFalse(deck.hasHistory, "yesterday was not completed")
        try assertShowsStorage(deck, store)
        XCTAssertEqual(try store.repository.counts(.sleep, on: store.today), ["sleep-01": 1])
    }

    /// A reset says whether it was stored, so a refused one is not announced.
    @MainActor
    func testScopedResetReturnsWhetherItWasStored() throws {
        let store = try ReadingStore()
        let deck = try store.makeDeck(.sleep)
        XCTAssertNotNil(deck.tap(cardAt: 0))
        let shown = Shown(deck)

        try store.hide(daysTable)
        for scope in ResetScope.allCases {
            XCTAssertFalse(deck.reset(scope), "\(scope)")
        }
        XCTAssertEqual(store.reported.count, ResetScope.allCases.count)
        XCTAssertEqual(Shown(deck), shown)
        try store.restore(daysTable)

        for scope in ResetScope.allCases {
            XCTAssertTrue(deck.reset(scope), "\(scope)")
        }
        XCTAssertEqual(store.reported.count, ResetScope.allCases.count)
        try assertShowsStorage(deck, store)
    }

    // MARK: Support

    /// The deck shows exactly what loading its day from the database shows.
    @MainActor
    private func assertShowsStorage(_ deck: ReadingDeckModel, _ store: ReadingStore,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let date = deck.date
        XCTAssertEqual(deck.counts, try store.repository.counts(deck.deck, on: date), file: file, line: line)
        let day = try store.repository.day(deck.deck, on: date)
        XCTAssertEqual(deck.completedDay?.completedAt.timeIntervalSince1970 ?? 0,
                       day?.completedAt.timeIntervalSince1970 ?? 0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(deck.hasHistory, try store.repository.recordedDayCount(deck.deck, .all, before: date) > 0,
                       file: file, line: line)
        let loaded = try store.makeDeck(deck.deck, on: date)
        XCTAssertEqual(deck.cards, loaded.cards, file: file, line: line)
        XCTAssertEqual(deck.summary, loaded.summary, file: file, line: line)
        XCTAssertEqual(deck.listSummary, loaded.listSummary, file: file, line: line)
        XCTAssertEqual(deck.canReset, loaded.canReset, file: file, line: line)
    }
}

/// What the deck shows: compared before and after a rejected change.
private struct Shown: Equatable {
    var date: String
    var counts: [String: Int]
    var completedDay: ReadingDay?
    var hasHistory: Bool
    var currentIndex: Int
    var cards: [DeckCard]
    var summary: DeckSummary
    var listSummary: DeckSummary
    var canReset: Bool

    @MainActor
    init(_ deck: ReadingDeckModel) {
        date = deck.date
        counts = deck.counts
        completedDay = deck.completedDay
        hasHistory = deck.hasHistory
        currentIndex = deck.currentIndex
        cards = deck.cards
        summary = deck.summary
        listSummary = deck.listSummary
        canReset = deck.canReset
    }
}

/// A reading deck on the production database, with real SQLite failures: a temporary trigger aborts one kind of
/// write to a table (and with it the whole transaction), and a renamed table fails every statement that uses it.
@MainActor
private final class ReadingStore {
    struct Stored: Equatable {
        var counts: [String: Int]
        var day: ReadingDay?
        var days: Int
    }

    let support: PortableTestSupport
    /// Every error the deck reported, in order.
    private(set) var reported: [String] = []

    init() throws {
        support = try PortableTestSupport()
    }

    var today: String { support.today }
    var repository: ReadingRepository { support.database.reading }

    func makeDeck(_ deck: ReadingDeck, on date: String? = nil) throws -> ReadingDeckModel {
        try ReadingDeckModel(deck, database: support.database, content: support.content, today: date ?? today,
                             report: { self.reported.append(String(describing: $0)) })
    }

    /// Today's rows and the earlier recorded days, as stored.
    func stored(_ deck: ReadingDeck) throws -> Stored {
        Stored(counts: try repository.counts(deck, on: today), day: try repository.day(deck, on: today),
               days: try repository.recordedDayCount(deck, .all, before: today))
    }

    /// Until ``allow(_:on:)``, SQLite aborts every `events` statement on `table`.
    func reject(_ events: [String], on table: String) throws {
        for event in events {
            try execute("""
                CREATE TEMP TRIGGER reject_\(event)_\(table) BEFORE \(event) ON \(table)
                BEGIN SELECT RAISE(ABORT, 'test rejects \(event) on \(table)'); END
                """)
        }
    }

    func allow(_ events: [String], on table: String) throws {
        for event in events {
            try execute("DROP TRIGGER temp.reject_\(event)_\(table)")
        }
    }

    /// Until ``restore(_:)``, every statement that reads or writes `table` fails: no such table.
    func hide(_ table: String) throws {
        try execute("ALTER TABLE \(table) RENAME TO hidden_\(table)")
    }

    func restore(_ table: String) throws {
        try execute("ALTER TABLE hidden_\(table) RENAME TO \(table)")
    }

    func execute(_ sql: String) throws {
        try support.database.writer.write { try $0.execute(sql: sql) }
    }
}
