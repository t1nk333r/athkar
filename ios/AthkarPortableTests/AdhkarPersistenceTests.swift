import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

/// A change the database rejects, or a day it cannot load, leaves the adhkar session exactly as last committed.
///
/// Every failure is SQLite's own, on the migrated schema the app ships: a `RAISE(ABORT)` trigger rejects writes to
/// one table, and renaming a table makes every statement that touches it fail. Undoing either shows recovery.
final class AdhkarPersistenceTests: XCTestCase {
    @MainActor
    func testRejectedTapKeepsTheCommittedCountAndReportsOnce() throws {
        let support = try makeSupport()
        let reports = Reports()
        let faults = Faults(database: support.database)
        let session = try makeSession(support, reports)
        let deck = AdhkarDeckModel(period: .morning, session: session)
        let index = try position(of: "morning-02", in: session)
        XCTAssertEqual(deck.cards[index].target, 3)
        XCTAssertEqual(deck.tap(cardAt: index), DeckChange())
        let committed = Snapshot(session)
        let stored = try records(support.database, [support.today])

        try faults.rejectWrites(to: "adhkar_item_progress")
        XCTAssertNil(deck.tap(cardAt: index))
        XCTAssertEqual(Snapshot(session), committed)
        XCTAssertFalse(deck.canMoveForward(from: index))
        XCTAssertEqual(try records(support.database, [support.today]), stored)
        XCTAssertEqual(reports.messages.count, 1)
        XCTAssertTrue(reports.messages.first?.contains(Faults.marker) == true)

        try faults.allowWrites(to: "adhkar_item_progress")
        XCTAssertEqual(deck.tap(cardAt: index), DeckChange())
        XCTAssertEqual(deck.cards[index].count, 2)
        XCTAssertEqual(try support.database.adhkar.session(on: support.today, period: .morning)
            .progress["morning-02"], 2)
        XCTAssertEqual(reports.messages.count, 1)
    }

    @MainActor
    func testRejectedFinalTapOffersNoHapticAdvanceOrDialogAndRollsBackTheCounter() throws {
        let support = try makeSupport()
        let reports = Reports()
        let faults = Faults(database: support.database)
        // Every morning counter at its target except morning-02, which is one tap short.
        for card in try makeSession(support, reports).cards.morning where !card.isReview {
            try support.database.adhkar.setCount(card.id == "morning-02" ? card.target - 1 : card.target,
                                                 for: card.id, on: support.today, period: .morning)
        }
        let session = try makeSession(support, reports)
        let deck = AdhkarDeckModel(period: .morning, session: session)
        let index = try position(of: "morning-02", in: session)
        XCTAssertFalse(deck.isComplete)
        let committed = Snapshot(session)
        let stored = try records(support.database, [support.today])

        // The counter's upsert succeeds, then the completion row's insert fails: the transaction undoes both.
        try faults.rejectWrites(to: "adhkar_days")
        XCTAssertNil(deck.tap(cardAt: index))
        XCTAssertEqual(Snapshot(session), committed)
        XCTAssertFalse(deck.isComplete)
        XCTAssertNil(session.state.completedAt.morning)
        XCTAssertEqual(try records(support.database, [support.today]), stored)
        XCTAssertEqual(reports.messages.count, 1)
        XCTAssertTrue(reports.messages.first?.contains(Faults.marker) == true)

        try faults.allowWrites(to: "adhkar_days")
        XCTAssertEqual(deck.tap(cardAt: index), DeckChange(completedCard: true, completedDeck: true, advance: false))
        XCTAssertTrue(deck.isComplete)
        let saved = try support.database.adhkar.session(on: support.today, period: .morning)
        XCTAssertEqual(saved.progress["morning-02"], 3)
        XCTAssertEqual(saved.completion?.completionOrigin, .counters)
        XCTAssertEqual(reports.messages.count, 1)
    }

    @MainActor
    func testRejectedTargetChangeKeepsTargetAndCountAndOffersNoAdvance() throws {
        let support = try makeSupport()
        let reports = Reports()
        let faults = Faults(database: support.database)
        let session = try makeSession(support, reports)
        let deck = AdhkarDeckModel(period: .morning, session: session)
        let index = try position(of: "morning-20", in: session)
        XCTAssertEqual(deck.cards[index].targetOptions, [1, 10, 100])
        XCTAssertEqual(deck.cards[index].target, 100)
        for _ in 1...3 { XCTAssertEqual(deck.tap(cardAt: index), DeckChange()) }
        let committed = Snapshot(session)
        let stored = try records(support.database, [support.today])

        try faults.rejectWrites(to: "adhkar_item_progress")
        XCTAssertNil(deck.setTarget(1, forCardAt: index))
        XCTAssertEqual(Snapshot(session), committed)
        XCTAssertEqual(deck.cards[index].target, 100)
        XCTAssertEqual(deck.cards[index].count, 3)
        XCTAssertEqual(try records(support.database, [support.today]), stored)
        XCTAssertEqual(reports.messages.count, 1)

        try faults.allowWrites(to: "adhkar_item_progress")
        XCTAssertEqual(deck.setTarget(1, forCardAt: index), DeckChange(advance: true))
        XCTAssertEqual(deck.cards[index].target, 1)
        XCTAssertEqual(deck.cards[index].count, 1)
        let saved = try support.database.adhkar.session(on: support.today, period: .morning)
        XCTAssertEqual(saved.targets["morning-20"], 1)
        XCTAssertEqual(saved.progress["morning-20"], 1)
        XCTAssertEqual(reports.messages.count, 1)
    }

    @MainActor
    func testRejectedTargetChangeUnderLongOrderKeepsDeckOrderAndFocus() throws {
        let support = try makeSupport()
        let reports = Reports()
        let faults = Faults(database: support.database)
        let session = try makeSession(support, reports, longAdhkarLast: true)
        let deck = AdhkarDeckModel(period: .morning, session: session)
        let contentIndex = try XCTUnwrap(support.content.packs.adhkar.morning.firstIndex { $0.id == "morning-20" })
        let longIndex = try position(of: "morning-20", in: session)
        XCTAssertGreaterThan(longIndex, contentIndex)
        deck.show(longIndex)
        let committed = Snapshot(session)
        let stored = try records(support.database, [support.today])

        try faults.rejectWrites(to: "adhkar_item_progress")
        XCTAssertNil(deck.setTarget(1, forCardAt: longIndex))
        XCTAssertEqual(Snapshot(session), committed)
        XCTAssertEqual(deck.cards[longIndex].id, "morning-20")
        XCTAssertEqual(deck.currentIndex, longIndex)
        XCTAssertEqual(try records(support.database, [support.today]), stored)
        XCTAssertEqual(reports.messages.count, 1)

        // Saved, the short target moves the item back among the short adhkar and the deck stays on it.
        try faults.allowWrites(to: "adhkar_item_progress")
        XCTAssertEqual(deck.setTarget(1, forCardAt: longIndex), DeckChange())
        let moved = try position(of: "morning-20", in: session)
        XCTAssertEqual(moved, contentIndex)
        XCTAssertEqual(deck.currentIndex, moved)
        XCTAssertEqual(deck.cards[moved].target, 1)
        XCTAssertEqual(try support.database.adhkar.session(on: support.today, period: .morning)
            .targets["morning-20"], 1)
        XCTAssertEqual(reports.messages.count, 1)
    }

    @MainActor
    func testRejectedCardResetKeepsTheCountAndTheCountersCompletion() throws {
        let support = try makeSupport()
        let reports = Reports()
        let faults = Faults(database: support.database)
        for card in try makeSession(support, reports).cards.morning where !card.isReview {
            try support.database.adhkar.setCount(card.id == "morning-02" ? card.target - 1 : card.target,
                                                 for: card.id, on: support.today, period: .morning)
        }
        let session = try makeSession(support, reports)
        let deck = AdhkarDeckModel(period: .morning, session: session)
        let index = try position(of: "morning-02", in: session)
        XCTAssertEqual(deck.tap(cardAt: index), DeckChange(completedCard: true, completedDeck: true, advance: false))
        let committed = Snapshot(session)
        let stored = try records(support.database, [support.today])

        // Clearing the counter would delete the completion row; that delete fails and the counter's update with it.
        try faults.rejectWrites(to: "adhkar_days")
        deck.resetCard(at: index)
        XCTAssertEqual(Snapshot(session), committed)
        XCTAssertEqual(deck.cards[index].count, 3)
        XCTAssertTrue(deck.isComplete)
        XCTAssertEqual(try records(support.database, [support.today]), stored)
        XCTAssertEqual(reports.messages.count, 1)

        try faults.allowWrites(to: "adhkar_days")
        deck.resetCard(at: index)
        XCTAssertEqual(deck.cards[index].count, 0)
        XCTAssertFalse(deck.isComplete)
        let saved = try support.database.adhkar.session(on: support.today, period: .morning)
        XCTAssertEqual(saved.progress["morning-02"], 0)
        XCTAssertNil(saved.completion)
        XCTAssertEqual(reports.messages.count, 1)
    }

    @MainActor
    func testRejectedManualCompletionChangesNothingAndReturnsFalse() throws {
        let support = try makeSupport()
        let reports = Reports()
        let faults = Faults(database: support.database)
        let session = try makeSession(support, reports)
        let committed = Snapshot(session)
        let stored = try records(support.database, [support.today])

        try faults.rejectWrites(to: "adhkar_days")
        XCTAssertFalse(session.setManualCompletion(.evening, completed: true))
        XCTAssertEqual(Snapshot(session), committed)
        XCTAssertFalse(session.isManuallyComplete(.evening))
        XCTAssertEqual(try records(support.database, [support.today]), stored)
        XCTAssertEqual(reports.messages.count, 1)

        try faults.allowWrites(to: "adhkar_days")
        XCTAssertTrue(session.setManualCompletion(.evening, completed: true))
        XCTAssertTrue(session.isManuallyComplete(.evening))
        XCTAssertEqual(try support.database.adhkar.session(on: support.today, period: .evening)
            .completion?.completionOrigin, .manual)
        let manual = Snapshot(session)
        let manualStored = try records(support.database, [support.today])

        try faults.rejectWrites(to: "adhkar_days")
        XCTAssertFalse(session.setManualCompletion(.evening, completed: false))
        XCTAssertEqual(Snapshot(session), manual)
        XCTAssertTrue(session.isManuallyComplete(.evening))
        XCTAssertEqual(try records(support.database, [support.today]), manualStored)
        XCTAssertEqual(reports.messages.count, 2)

        try faults.allowWrites(to: "adhkar_days")
        XCTAssertTrue(session.setManualCompletion(.evening, completed: false))
        XCTAssertFalse(session.isManuallyComplete(.evening))
        XCTAssertNil(try support.database.adhkar.session(on: support.today, period: .evening).completion)
        XCTAssertEqual(reports.messages.count, 2)
    }

    @MainActor
    func testRejectedScopedResetsKeepEveryRecordAndPosition() throws {
        let support = try makeSupport()
        let reports = Reports()
        let faults = Faults(database: support.database)
        try support.database.adhkar.markComplete(on: Day.yesterday, period: .morning, origin: .counters,
                                                 completedAt: nil)
        let session = try makeSession(support, reports)
        XCTAssertEqual(session.tap(.morning, at: try position(of: "morning-02", in: session)), DeckChange())
        XCTAssertTrue(session.setManualCompletion(.evening, completed: true))
        session.show(.morning, at: 3)
        XCTAssertEqual(session.state.history.map(\.date), [Day.yesterday])
        let committed = Snapshot(session)
        let dates = [Day.yesterday, support.today]
        let stored = try records(support.database, dates)

        try faults.rejectWrites(to: "adhkar_days")
        for (attempt, scope) in ResetScope.allCases.enumerated() {
            session.reset(scope)
            XCTAssertEqual(Snapshot(session), committed, "\(scope)")
            XCTAssertEqual(try records(support.database, dates), stored, "\(scope)")
            XCTAssertEqual(reports.messages.count, attempt + 1, "\(scope)")
        }

        try faults.allowWrites(to: "adhkar_days")
        session.reset(.everything)
        XCTAssertEqual(session.indices, SessionPeriods(morning: 0, evening: 0))
        XCTAssertTrue(session.state.history.isEmpty)
        XCTAssertFalse(session.canReset)
        for record in try records(support.database, dates) { XCTAssertTrue(record.isEmpty, "\(record)") }
        XCTAssertEqual(reports.messages.count, ResetScope.allCases.count)
    }

    @MainActor
    func testFailedDayLoadKeepsTheCommittedDayAndRetriesBeforeAnyChange() throws {
        let support = try makeSupport()
        let reports = Reports()
        let faults = Faults(database: support.database)
        let session = try makeSession(support, reports)
        let deck = AdhkarDeckModel(period: .morning, session: session)
        let index = try position(of: "morning-02", in: session)
        XCTAssertEqual(deck.tap(cardAt: index), DeckChange())
        XCTAssertTrue(session.setManualCompletion(.evening, completed: true))
        // Rows already saved for the next day: an imported file, or a clock that moved back and forth.
        try support.database.adhkar.setCount(2, for: "morning-03", on: Day.tomorrow, period: .morning)
        try support.database.adhkar.markComplete(on: Day.tomorrow, period: .evening, origin: .manual, completedAt: nil)
        let committed = Snapshot(session)
        let dates = [support.today, Day.tomorrow]
        let stored = try records(support.database, dates)

        try faults.hide("adhkar_days")
        session.roll(to: Day.tomorrow)
        XCTAssertEqual(Snapshot(session), committed)
        XCTAssertEqual(session.state.date, support.today)
        XCTAssertTrue(session.isManuallyComplete(.evening))
        XCTAssertEqual(reports.messages.count, 1)
        XCTAssertTrue(reports.messages.first?.contains("no such table") == true)

        // The caller's next ensureCurrentDay, then changes that would otherwise save the earlier day's rows.
        session.roll(to: Day.tomorrow)
        XCTAssertNil(deck.tap(cardAt: index))
        XCTAssertFalse(session.setManualCompletion(.morning, completed: true))
        session.reset(.day)
        XCTAssertEqual(Snapshot(session), committed)
        XCTAssertEqual(reports.messages.count, 5)

        try faults.restore("adhkar_days")
        XCTAssertEqual(try records(support.database, dates), stored)
        // The first change after recovery loads the new day and is dropped, as a tap that rolls the day is.
        session.reset(.day)
        XCTAssertEqual(session.state.date, Day.tomorrow)
        XCTAssertEqual(try records(support.database, dates), stored)
        let loaded = try position(of: "morning-03", in: session)
        XCTAssertEqual(deck.cards[loaded].count, 2)
        XCTAssertTrue(session.isManuallyComplete(.evening))

        XCTAssertEqual(deck.tap(cardAt: try position(of: "morning-02", in: session)), DeckChange())
        let next = try support.database.adhkar.session(on: Day.tomorrow, period: .morning)
        XCTAssertEqual(next.progress, ["morning-02": 1, "morning-03": 2])
        XCTAssertEqual(try support.database.adhkar.session(on: Day.tomorrow, period: .evening)
            .completion?.completionOrigin, .manual)
        XCTAssertEqual(try records(support.database, [support.today]), Array(stored.prefix(Period.allCases.count)))
        XCTAssertEqual(reports.messages.count, 5)
    }

    @MainActor
    func testCallerRetryLoadsTheNewDayAndReturningToTheShownDayEndsTheRetry() throws {
        let support = try makeSupport()
        let reports = Reports()
        let faults = Faults(database: support.database)
        try support.database.adhkar.setCount(1, for: "morning-01", on: Day.tomorrow, period: .morning)
        try support.database.adhkar.setCount(3, for: "morning-02", on: Day.tomorrow, period: .morning)
        let session = try makeSession(support, reports)

        try faults.hide("adhkar_item_progress")
        session.roll(to: Day.tomorrow)
        XCTAssertEqual(session.state.date, support.today)
        try faults.restore("adhkar_item_progress")
        session.roll(to: Day.tomorrow)
        XCTAssertEqual(session.state.date, Day.tomorrow)
        XCTAssertEqual(session.cards.morning.first { $0.id == "morning-02" }?.count, 3)
        XCTAssertEqual(session.indices.morning, try position(of: "morning-03", in: session))
        XCTAssertEqual(reports.messages.count, 1)

        // A failed load, then the clock returns to the day on screen: no load is pending any more.
        try faults.hide("adhkar_item_progress")
        session.roll(to: Day.dayAfter)
        XCTAssertEqual(reports.messages.count, 2)
        session.roll(to: Day.tomorrow)
        try faults.restore("adhkar_item_progress")
        XCTAssertEqual(session.tap(.morning, at: try position(of: "morning-03", in: session)), DeckChange())
        XCTAssertEqual(session.state.date, Day.tomorrow)
        XCTAssertEqual(try support.database.adhkar.session(on: Day.tomorrow, period: .morning)
            .progress["morning-03"], 1)
        XCTAssertEqual(reports.messages.count, 2)
    }

    @MainActor
    func testOnDiskDatabaseKeepsCommittedRowsThroughRejectedWritesAndUnreadableDays() throws {
        let support = try makeSupport()
        let parent = ProcessInfo.processInfo.environment["ATHKAR_TEST_TMP"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let directory = parent.appendingPathComponent("Athkar-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("athkar.sqlite")
        // The app's own configuration: a WAL DatabasePool whose reads use separate connections.
        let database = try AppDatabase.onDisk(at: url)
        let reports = Reports()
        let faults = Faults(database: database)
        let session = try AdhkarSessionModel(database: database, content: support.content, longAdhkarLast: false,
                                             today: support.today, report: reports.record)
        let index = try position(of: "morning-02", in: session)
        XCTAssertEqual(session.tap(.morning, at: index), DeckChange())
        let committed = Snapshot(session)

        try faults.rejectWrites(to: "adhkar_item_progress")
        XCTAssertNil(session.tap(.morning, at: index))
        XCTAssertEqual(Snapshot(session), committed)
        try faults.allowWrites(to: "adhkar_item_progress")

        try faults.hide("adhkar_days")
        session.roll(to: Day.tomorrow)
        XCTAssertEqual(Snapshot(session), committed)
        try faults.restore("adhkar_days")
        session.roll(to: Day.tomorrow)
        XCTAssertEqual(session.state.date, Day.tomorrow)
        XCTAssertEqual(reports.messages.count, 2)

        // A second connection to the file sees exactly the committed rows.
        let reopened = try AppDatabase.onDisk(at: url)
        XCTAssertEqual(try reopened.adhkar.session(on: support.today, period: .morning).progress, ["morning-02": 1])
        XCTAssertTrue(try reopened.adhkar.session(on: Day.tomorrow, period: .morning).progress.isEmpty)
    }

    // MARK: Support

    /// The dates around `PortableTestSupport.today`.
    private enum Day {
        static let yesterday = "2026-10-13"
        static let today = "2026-10-14"
        static let tomorrow = "2026-10-15"
        static let dayAfter = "2026-10-16"
    }

    @MainActor
    private func makeSupport() throws -> PortableTestSupport {
        let support = try PortableTestSupport()
        XCTAssertEqual(support.today, Day.today)
        return support
    }

    @MainActor
    private func makeSession(_ support: PortableTestSupport, _ reports: Reports,
                             longAdhkarLast: Bool = false) throws -> AdhkarSessionModel {
        try AdhkarSessionModel(database: support.database, content: support.content, longAdhkarLast: longAdhkarLast,
                               today: support.today, report: reports.record)
    }

    @MainActor
    private func position(of id: String, _ period: Period = .morning, in session: AdhkarSessionModel) throws -> Int {
        try XCTUnwrap(session.cards[period].firstIndex { $0.id == id }, "\(id) in the \(period) deck")
    }

    /// Both periods' stored records for each date, in order.
    private func records(_ database: AppDatabase, _ dates: [String]) throws -> [AdhkarSession] {
        try dates.flatMap { date in try Period.allCases.map { try database.adhkar.session(on: date, period: $0) } }
    }
}

/// Everything the session shows: its state, cards, positions, summaries and order.
private struct Snapshot: Equatable {
    var state: SessionState
    var cards: SessionPeriods<[DeckCard]>
    var indices: SessionPeriods<Int>
    var summaries: SessionPeriods<DeckSummary>
    var longAdhkarLast: Bool

    @MainActor
    init(_ session: AdhkarSessionModel) {
        state = session.state
        cards = session.cards
        indices = session.indices
        summaries = SessionPeriods(morning: session.summary(.morning), evening: session.summary(.evening))
        longAdhkarLast = session.longAdhkarLast
    }
}

/// The errors the session reported, in order.
private final class Reports {
    private(set) var messages: [String] = []

    func record(_ error: any Error) {
        messages.append(String(describing: error))
    }
}

/// Real SQLite failures on the migrated schema.
private struct Faults {
    static let marker = "injected rejection"
    let database: AppDatabase

    /// A `RAISE(ABORT)` trigger before every insert, update and delete on `table`: the statement fails and the
    /// enclosing transaction rolls back.
    func rejectWrites(to table: String) throws {
        try database.writer.write { db in
            for event in Self.events {
                try db.execute(sql: """
                    CREATE TRIGGER reject_\(table)_\(event) BEFORE \(event) ON \(table)
                    BEGIN SELECT RAISE(ABORT, '\(Self.marker) on \(table)'); END
                    """)
            }
        }
    }

    func allowWrites(to table: String) throws {
        try database.writer.write { db in
            for event in Self.events {
                try db.execute(sql: "DROP TRIGGER reject_\(table)_\(event)")
            }
        }
    }

    /// Renames `table`: every read or write of it fails with "no such table".
    func hide(_ table: String) throws {
        try database.writer.write { db in try db.execute(sql: "ALTER TABLE \(table) RENAME TO hidden_\(table)") }
    }

    func restore(_ table: String) throws {
        try database.writer.write { db in try db.execute(sql: "ALTER TABLE hidden_\(table) RENAME TO \(table)") }
    }

    private static let events = ["INSERT", "UPDATE", "DELETE"]
}
