import AthkarCore
import Foundation
import GRDB
import XCTest
@testable import AthkarModels

private let progressTable = "ruqyah_segment_progress"
/// A count is an upsert: rejecting both kinds of statement rejects it whether or not its row exists.
private let countWrites = ["INSERT", "UPDATE"]
/// 2026-10-14T04:00:00Z and 2026-10-01T05:00:00Z.
private let todayCompletedAt = Date(timeIntervalSince1970: 1_791_950_400)
private let earlierCompletedAt = Date(timeIntervalSince1970: 1_790_830_800)

/// The ruqyah deck shows a reading, reset or completion only once SQLite has stored it, and never shows a day it
/// could not read. The failures are real SQLite errors in the production database (``RuqyahStore``).
final class RuqyahPersistenceTests: XCTestCase {
    @MainActor
    func testRejectedReadingIsNotCountedAndARetryCountsItOnce() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        let single = try XCTUnwrap(deck.cards.firstIndex { $0.target == 1 })
        let repeated = try XCTUnwrap(deck.cards.firstIndex { $0.target > 2 })
        XCTAssertNotNil(deck.tap(cardAt: repeated))
        let shown = Shown(deck)
        let stored = try store.stored()

        try store.reject(countWrites, on: progressTable)
        XCTAssertNil(deck.tap(cardAt: single), "no haptic, advance or announcement for an unsaved reading")
        XCTAssertNil(deck.tap(cardAt: repeated))
        XCTAssertEqual(store.reported.count, 2)
        XCTAssertEqual(Shown(deck), shown)
        XCTAssertEqual(try store.stored(), stored)

        try store.allow(countWrites, on: progressTable)
        XCTAssertEqual(deck.tap(cardAt: single), DeckChange(completedCard: true, advance: true))
        XCTAssertEqual(deck.tap(cardAt: repeated), DeckChange())
        XCTAssertEqual(deck.cards[repeated].count, 2)
        XCTAssertEqual(store.reported.count, 2)
        try assertShowsStorage(deck, store)
    }

    @MainActor
    func testRejectedFinalReadingRecordsNothingAndTheRetryRecordsTheFirstCompletion() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        let last = deck.cards.count - 1
        try read(deck, leaving: 1)
        let shown = Shown(deck)
        let stored = try store.stored()
        XCTAssertNil(stored.day)

        try store.reject(["INSERT"], on: "ruqyah_days")
        XCTAssertNil(deck.tap(cardAt: last), "no completion dialog for an unsaved completion")
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(deck), shown)
        XCTAssertFalse(deck.isComplete)
        XCTAssertEqual(deck.summary.status, "رقية اليوم لم تكتمل بعد.")
        // The reading and the day are one transaction: neither was stored.
        XCTAssertEqual(try store.stored(), stored)

        try store.allow(["INSERT"], on: "ruqyah_days")
        let retried = Date()
        XCTAssertEqual(deck.tap(cardAt: last), DeckChange(completedCard: true, completedDeck: true))
        let day = try XCTUnwrap(store.repository.day(on: store.today))
        XCTAssertEqual(day.completionOrigin, .counters)
        XCTAssertGreaterThanOrEqual(day.completedAt.timeIntervalSince1970, retried.timeIntervalSince1970 - 0.001)
        XCTAssertTrue(deck.isComplete)
        XCTAssertTrue(deck.summary.isComplete)
        XCTAssertEqual(store.reported.count, 1)
        try assertShowsStorage(deck, store)
        XCTAssertTrue(try store.makeDeck().isComplete)
    }

    /// «بدء رقية جديدة» and a segment reset restart the counters; today keeps its first completion time, and
    /// completing again opens the dialog again.
    @MainActor
    func testStartingAnotherReadingKeepsTheFirstCompletion() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        try read(deck)
        let first = try XCTUnwrap(store.repository.day(on: store.today))

        XCTAssertEqual(deck.completion.primary, .restart)
        deck.reset(.day)
        XCTAssertEqual(deck.summary.value, 0)
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertTrue(deck.isComplete)
        XCTAssertTrue(deck.canReset)
        XCTAssertEqual(try store.repository.day(on: store.today), first)
        try assertShowsStorage(deck, store)

        XCTAssertEqual(try read(deck), DeckChange(completedCard: true, completedDeck: true))
        let last = deck.cards.count - 1
        deck.resetCard(at: last)
        XCTAssertTrue(deck.isComplete)
        XCTAssertEqual(try read(deck), DeckChange(completedCard: true, completedDeck: true))
        XCTAssertEqual(try store.repository.day(on: store.today), first)
        XCTAssertEqual(try XCTUnwrap(deck.completedAt).timeIntervalSince1970,
                       first.completedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(store.reported.isEmpty)
        try assertShowsStorage(deck, store)
    }

    @MainActor
    func testRejectedCardResetKeepsTheCounterUntilARetryStoresIt() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        let index = try XCTUnwrap(deck.cards.firstIndex { $0.target > 2 })
        for _ in 1...3 { XCTAssertNotNil(deck.tap(cardAt: index)) }
        XCTAssertNotNil(deck.resetConfirmation(forCardAt: index))
        let shown = Shown(deck)
        let stored = try store.stored()

        try store.reject(countWrites, on: progressTable)
        deck.resetCard(at: index)
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(deck), shown)
        XCTAssertEqual(deck.cards[index].count, 3)
        XCTAssertEqual(try store.stored(), stored)

        try store.allow(countWrites, on: progressTable)
        deck.resetCard(at: index)
        XCTAssertEqual(deck.cards[index].count, 0)
        XCTAssertEqual(try store.repository.counts(on: store.today)[deck.cards[index].id], 0)
        XCTAssertEqual(store.reported.count, 1)
        try assertShowsStorage(deck, store)
    }

    /// A rejected تقدم اليوم / هذا الأسبوع / كل شيء changes nothing, the reader's position included; deleting the
    /// history and zeroing the counters are one transaction.
    @MainActor
    func testRejectedScopedResetsKeepCountersHistoryAndPosition() throws {
        let cases: [(ResetScope, [String], String)] = [
            (.day, ["UPDATE"], progressTable), (.week, ["UPDATE"], progressTable),
            (.everything, ["UPDATE"], progressTable), (.everything, ["DELETE"], "ruqyah_days"),
        ]
        for (scope, events, table) in cases {
            let label = "\(scope), \(events) on \(table) rejected"
            let store = try RuqyahStore()
            try store.repository.markComplete(on: "2026-10-01", completedAt: earlierCompletedAt, origin: .imported)
            let deck = try store.makeDeck()
            try read(deck)
            deck.show(2)
            let shown = Shown(deck)
            let stored = try store.stored()

            try store.reject(events, on: table)
            deck.reset(scope)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertEqual(Shown(deck), shown, label)
            XCTAssertEqual(try store.stored(), stored, label)

            try store.allow(events, on: table)
            deck.reset(scope)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertEqual(deck.summary.value, 0, label)
            XCTAssertEqual(deck.currentIndex, 0, label)
            switch scope {
            case .day:
                XCTAssertTrue(deck.isComplete, label)
                XCTAssertEqual(try store.stored().days, stored.days, label)
            case .week:
                break
            case .everything:
                XCTAssertFalse(deck.isComplete, label)
                XCTAssertFalse(deck.canReset, label)
                XCTAssertEqual(try store.stored().days, 0, label)
            }
            try assertShowsStorage(deck, store)
        }
    }

    /// When the completed days cannot be read, the deck neither hides today's completion nor shows an empty day.
    @MainActor
    func testUnreadableHistoryNeitherHidesTodaysCompletionNorEmptiesTheDay() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        try read(deck)
        deck.show(2)
        let shown = Shown(deck)
        let stored = try store.stored()

        try store.hide("ruqyah_days")
        // كل شيء removes the days, so it fails and changes nothing.
        deck.reset(.everything)
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(deck), shown)
        // تقدم اليوم stores only counters; today stays recorded complete.
        deck.reset(.day)
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(deck.summary.value, 0)
        XCTAssertTrue(deck.isComplete)
        XCTAssertEqual(deck.completedAt, shown.completedAt)
        try store.restore("ruqyah_days")

        XCTAssertEqual(try store.stored().day, stored.day)
        try assertShowsStorage(deck, store)
    }

    /// A new day that cannot be read is not shown as empty: the deck keeps its day, and the next roll retries.
    @MainActor
    func testUnreadableNewDayKeepsTheCurrentDayUntilARetryLoadsIt() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        let index = try XCTUnwrap(deck.cards.firstIndex { $0.target > 2 })
        let segmentId = deck.cards[index].id
        XCTAssertNotNil(deck.tap(cardAt: index))
        // Readings already stored on the next date, as after moving back across a time-zone boundary.
        let next = "2026-10-15"
        try store.repository.setCount(2, for: segmentId, on: next)
        let shown = Shown(deck)

        for table in [progressTable, "ruqyah_days"] {
            try store.hide(table)
            XCTAssertThrowsError(try store.makeDeck(on: next), table)
            deck.roll(to: next)
            try store.restore(table)
            XCTAssertEqual(Shown(deck), shown, table)
        }
        XCTAssertEqual(store.reported.count, 2)

        deck.roll(to: next)
        XCTAssertEqual(store.reported.count, 2)
        XCTAssertEqual(deck.progress.date, next)
        XCTAssertEqual(deck.cards[index].count, 2)
        XCTAssertEqual(deck.currentIndex, 0)
        try assertShowsStorage(deck, store)
        XCTAssertEqual(try store.repository.counts(on: store.today)[segmentId], 1)
    }

    /// A ruqyah-pwa file may record today itself as complete. The row is the record: the schema keeps no completion
    /// without its time, so the deck shows the imported time and a later completion keeps it.
    @MainActor
    func testImportedCompletionOfTodayIsCompleteAndKeepsItsTime() throws {
        let store = try RuqyahStore()
        XCTAssertThrowsError(try store.execute("""
            INSERT INTO ruqyah_days (local_date, completed_at, completion_origin)
            VALUES ('\(store.today)', NULL, 'import')
            """))
        let importedAt = todayCompletedAt
        let example = store.repo.appendingPathComponent("spec/backup/examples/ruqyah-pwa.athkarbackup")
        var envelope = try BackupEnvelope.decode(Data(contentsOf: example))
        var ruqyah = try XCTUnwrap(envelope.ruqyah)
        XCTAssertFalse(ruqyah.today.counts.isEmpty)
        ruqyah.today.date = store.today
        ruqyah.history = ["2026-10-01": .init(completedAt: earlierCompletedAt),
                          store.today: .init(completedAt: importedAt)]
        envelope.ruqyah = ruqyah
        try BackupImporter(database: store.support.database, content: store.support.content.packs)
            .importEnvelope(envelope)

        let deck = try store.makeDeck()
        XCTAssertTrue(deck.isComplete)
        XCTAssertTrue(deck.summary.isComplete)
        XCTAssertEqual(deck.completedAt, importedAt)
        XCTAssertEqual(deck.summary.status, "تمت رقية اليوم في \(ArabicFormat.time(importedAt)).")
        XCTAssertGreaterThan(deck.summary.value, 0)
        XCTAssertLessThan(deck.summary.value, deck.summary.total)
        XCTAssertTrue(deck.canReset)
        try assertShowsStorage(deck, store)

        XCTAssertEqual(try read(deck), DeckChange(completedCard: true, completedDeck: true))
        XCTAssertEqual(try store.repository.day(on: store.today),
                       RuqyahDay(localDate: store.today, completedAt: importedAt, completionOrigin: .imported))
        XCTAssertEqual(deck.completedAt, importedAt)
        XCTAssertTrue(store.reported.isEmpty)
        try assertShowsStorage(deck, store)
    }

    // MARK: Support

    /// Taps every remaining reading in deck order, except the last `leaving` ones, and returns the final change.
    @MainActor
    @discardableResult
    private func read(_ deck: RuqyahDeckModel, leaving: Int = 0) throws -> DeckChange? {
        var left = deck.cards.reduce(0) { $0 + $1.target - $1.count } - leaving
        var change: DeckChange?
        for index in deck.cards.indices {
            while left > 0, deck.cards[index].count < deck.cards[index].target {
                change = try XCTUnwrap(deck.tap(cardAt: index))
                left -= 1
            }
        }
        return change
    }

    /// The deck shows exactly what loading its day from the database shows.
    @MainActor
    private func assertShowsStorage(_ deck: RuqyahDeckModel, _ store: RuqyahStore,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let date = deck.progress.date
        XCTAssertEqual(deck.progress, RuqyahProgress(date: date, counts: try store.repository.counts(on: date)),
                       file: file, line: line)
        let day = try store.repository.day(on: date)
        XCTAssertEqual(deck.isComplete, day != nil, file: file, line: line)
        XCTAssertEqual(deck.completedAt == nil, day == nil, file: file, line: line)
        if let shown = deck.completedAt, let day {
            XCTAssertEqual(shown.timeIntervalSince1970, day.completedAt.timeIntervalSince1970, accuracy: 0.001,
                           file: file, line: line)
        }
        XCTAssertEqual(deck.hasHistory, try store.repository.dayCount(.all) > 0, file: file, line: line)
        XCTAssertEqual(deck.cards, try store.makeDeck(on: date).cards, file: file, line: line)
    }
}

/// What the deck shows: compared before and after a rejected change.
private struct Shown: Equatable {
    var progress: RuqyahProgress
    var completedAt: Date?
    var isComplete: Bool
    var hasHistory: Bool
    var currentIndex: Int
    var cards: [DeckCard]
    var summary: DeckSummary

    @MainActor
    init(_ deck: RuqyahDeckModel) {
        progress = deck.progress
        completedAt = deck.completedAt
        isComplete = deck.isComplete
        hasHistory = deck.hasHistory
        currentIndex = deck.currentIndex
        cards = deck.cards
        summary = deck.summary
    }
}

/// A ruqyah deck on the production database, with real SQLite failures: a temporary trigger aborts one kind of
/// write to a table (and with it the whole transaction), and a renamed table fails every statement that uses it.
@MainActor
private final class RuqyahStore {
    struct Stored: Equatable {
        var counts: [String: Int]
        var day: RuqyahDay?
        var days: Int
    }

    let support: PortableTestSupport
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    /// Every error the decks reported, in order.
    private(set) var reported: [String] = []

    init() throws {
        support = try PortableTestSupport()
    }

    var today: String { support.today }
    var repository: RuqyahRepository { support.database.ruqyah }

    func makeDeck(on date: String? = nil) throws -> RuqyahDeckModel {
        try RuqyahDeckModel(database: support.database, content: support.content, today: date ?? today,
                            report: { self.reported.append(String(describing: $0)) })
    }

    /// Today's rows, as stored.
    func stored() throws -> Stored {
        Stored(counts: try repository.counts(on: today), day: try repository.day(on: today),
               days: try repository.dayCount(.all))
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
