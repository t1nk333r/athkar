import AthkarCore
import Foundation
import GRDB
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
        XCTAssertEqual(deck.tap(cardAt: index),
                       DeckChange(completedCard: true, completedDeck: true, advance: false, haptic: true),
                       "morning-02 is read three times, so completing it plays the haptic")
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
        XCTAssertEqual(deck.tap(cardAt: index),
                       DeckChange(completedCard: true, completedDeck: true, advance: false, haptic: true),
                       "morning-02 is read three times, so completing it plays the haptic")
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

        try faults.hide("adhkar_item_progress")
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

        try faults.restore("adhkar_item_progress")
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

        try faults.hide("adhkar_item_progress")
        session.roll(to: Day.tomorrow)
        XCTAssertEqual(Snapshot(session), committed)
        try faults.restore("adhkar_item_progress")
        session.roll(to: Day.tomorrow)
        XCTAssertEqual(session.state.date, Day.tomorrow)
        XCTAssertEqual(reports.messages.count, 2)

        // A second connection to the file sees exactly the committed rows.
        let reopened = try AppDatabase.onDisk(at: url)
        XCTAssertEqual(try reopened.adhkar.session(on: support.today, period: .morning).progress, ["morning-02": 1])
        XCTAssertTrue(try reopened.adhkar.session(on: Day.tomorrow, period: .morning).progress.isEmpty)
    }

    // MARK: Reminder completion

    @MainActor
    func testCompletedPeriodsOnlyIncludesMatchingDate() throws {
        let support = try makeSupport()
        let reports = Reports()
        for card in try makeSession(support, reports).cards.morning where !card.isReview {
            try support.database.adhkar.setCount(card.target, for: card.id, on: support.today, period: .morning)
        }
        let session = try makeSession(support, reports)
        XCTAssertTrue(session.countersComplete(.morning))
        XCTAssertEqual(session.completedPeriods(on: Day.today), [.morning])
        XCTAssertTrue(session.setManualCompletion(.evening, completed: true))
        XCTAssertEqual(session.completedPeriods(on: Day.today), [.morning, .evening])
        for date in [Day.yesterday, Day.tomorrow] {
            XCTAssertEqual(session.completedPeriods(on: date), [], date)
        }

        // A reopened period no longer counts, and a loaded day counts only its own completion.
        XCTAssertTrue(session.setManualCompletion(.evening, completed: false))
        XCTAssertEqual(session.completedPeriods(on: Day.today), [.morning])
        try support.database.adhkar.markComplete(on: Day.tomorrow, period: .evening, origin: .manual, completedAt: nil)
        session.roll(to: Day.tomorrow)
        XCTAssertEqual(session.completedPeriods(on: Day.tomorrow), [.evening])
        XCTAssertEqual(session.completedPeriods(on: Day.today), [])
        XCTAssertTrue(reports.messages.isEmpty)
    }

    /// While the planner's date cannot be loaded, the session still shows the day before, complete. That completion
    /// holds back none of the new day's reminders, ahead or caught up; once the day loads, its own completion does.
    @MainActor
    func testFailedRolloverDoesNotSuppressNewDayRemindersAndCanRecover() throws {
        let support = try makeSupport()
        let reports = Reports()
        let faults = Faults(database: support.database)
        let session = try makeSession(support, reports)
        XCTAssertTrue(session.setManualCompletion(.morning, completed: true))
        XCTAssertTrue(session.setManualCompletion(.evening, completed: true))
        // The new day already has its evening marked complete, as an imported file can leave it.
        try support.database.adhkar.markComplete(on: Day.tomorrow, period: .evening, origin: .manual, completedAt: nil)
        // On the new day: both reminders still ahead, then the morning one ten minutes past, a catch-up.
        let ahead = AdhkarReminders.instant(Day.tomorrow, hour: 4.5)
        let caughtUp = AdhkarReminders.instant(Day.tomorrow, hour: 5 + 10.0 / 60)

        try faults.hide("adhkar_item_progress")
        for now in [ahead, caughtUp] {
            let date = SessionCalendar.localDate(of: now, in: AdhkarReminders.zone)
            XCTAssertEqual(date, Day.tomorrow)
            // The reminder pass's rollover cannot read the new day.
            session.roll(to: date)
            XCTAssertEqual(session.state.date, Day.today)
            XCTAssertTrue(session.isComplete(.morning) && session.isComplete(.evening))
            let completed = session.completedPeriods(on: date)
            XCTAssertEqual(completed, [])
            let plan = AdhkarReminders.plan(now: now, completed: completed)
            XCTAssertEqual(plan.first { $0.id == "adhkar.morning.\(Day.tomorrow)" }?.isCatchUp, now == caughtUp)
            XCTAssertTrue(plan.contains { $0.id == "adhkar.evening.\(Day.tomorrow)" })
        }
        XCTAssertEqual(reports.messages.count, 2)

        try faults.restore("adhkar_item_progress")
        session.roll(to: Day.tomorrow)
        XCTAssertEqual(session.state.date, Day.tomorrow)
        let completed = session.completedPeriods(on: Day.tomorrow)
        XCTAssertEqual(completed, [.evening])
        let ids = AdhkarReminders.plan(now: ahead, completed: completed).map(\.id)
        XCTAssertTrue(ids.contains("adhkar.morning.\(Day.tomorrow)"))
        XCTAssertFalse(ids.contains("adhkar.evening.\(Day.tomorrow)"))
        XCTAssertTrue(ids.contains("adhkar.evening.\(Day.dayAfter)"))
        XCTAssertEqual(reports.messages.count, 2)
    }

    /// The planner's date is the civil date of its instant in its own zone, which need not be the session's: one
    /// instant is still the session's day west of UTC and already the next day east of it.
    @MainActor
    func testCompletionGateUsesPlannerCivilDateAcrossZones() throws {
        let support = try makeSupport()
        let reports = Reports()
        let session = try makeSession(support, reports)
        XCTAssertTrue(session.setManualCompletion(.evening, completed: true))
        let now = Date(timeIntervalSince1970: 1_792_018_800) // 2026-10-14T23:00:00Z
        let west = try XCTUnwrap(TimeZone(secondsFromGMT: -10 * 3600))
        let east = try XCTUnwrap(TimeZone(secondsFromGMT: 10 * 3600))

        // 13:00 on the session's day: its completion holds back this evening's reminder and no other.
        let westDate = SessionCalendar.localDate(of: now, in: west)
        XCTAssertEqual(westDate, Day.today)
        XCTAssertEqual(session.completedPeriods(on: westDate), [.evening])
        let westIds = AdhkarReminders.plan(now: now, zone: west, completed: session.completedPeriods(on: westDate))
            .map(\.id)
        XCTAssertFalse(westIds.contains("adhkar.evening.\(Day.today)"))
        XCTAssertTrue(westIds.contains("adhkar.evening.\(Day.tomorrow)"))

        // 09:00 on the next day: the session's completion is not that day's.
        let eastDate = SessionCalendar.localDate(of: now, in: east)
        XCTAssertEqual(eastDate, Day.tomorrow)
        XCTAssertEqual(session.completedPeriods(on: eastDate), [])
        let eastIds = AdhkarReminders.plan(now: now, zone: east, completed: session.completedPeriods(on: eastDate))
            .map(\.id)
        XCTAssertTrue(eastIds.contains("adhkar.evening.\(Day.tomorrow)"))
        XCTAssertTrue(reports.messages.isEmpty)
    }

    // MARK: Reset result

    /// A scoped reset says whether it was stored, so a refused one is not announced: one SQLite rejects, one made while
    /// the next day cannot be loaded, and the one whose retry loads that day.
    @MainActor
    func testScopedResetReturnsWhetherItWasStored() throws {
        let support = try makeSupport()
        let reports = Reports()
        let faults = Faults(database: support.database)
        let session = try makeSession(support, reports)
        let deck = AdhkarDeckModel(period: .morning, session: session)
        XCTAssertEqual(deck.tap(cardAt: try position(of: "morning-02", in: session)), DeckChange())
        // Every scope then deletes today's manual evening completion from adhkar_days.
        XCTAssertTrue(session.setManualCompletion(.evening, completed: true))

        try faults.rejectWrites(to: "adhkar_days")
        for scope in ResetScope.allCases {
            XCTAssertFalse(deck.reset(scope), "\(scope)")
        }
        try faults.allowWrites(to: "adhkar_days")
        XCTAssertTrue(session.isManuallyComplete(.evening))
        XCTAssertEqual(reports.messages.count, ResetScope.allCases.count)

        try faults.hide("adhkar_item_progress")
        session.roll(to: Day.tomorrow)
        XCTAssertFalse(deck.reset(.day), "the next day cannot be loaded")
        try faults.restore("adhkar_item_progress")
        XCTAssertFalse(deck.reset(.day), "the reset whose retry loads the next day")
        XCTAssertEqual(session.state.date, Day.tomorrow)

        for scope in ResetScope.allCases {
            XCTAssertTrue(deck.reset(scope), "\(scope)")
        }
        XCTAssertEqual(reports.messages.count, ResetScope.allCases.count + 2)
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
    ///
    /// Only `adhkar_item_progress` is hidden. A day load and a save both read it first, with a plain filter, so the
    /// error is thrown before anything else runs. `adhkar_days` cannot be hidden: its rows are looked up by key
    /// (`fetchOne(key:)`, `deleteOne(key:)`), and GRDB answers a key lookup on a missing table with a fatal error,
    /// not a thrown one, which ends the whole test process.
    func hide(_ table: String) throws {
        try database.writer.write { db in try db.execute(sql: "ALTER TABLE \(table) RENAME TO hidden_\(table)") }
    }

    func restore(_ table: String) throws {
        try database.writer.write { db in try db.execute(sql: "ALTER TABLE hidden_\(table) RENAME TO \(table)") }
    }

    private static let events = ["INSERT", "UPDATE", "DELETE"]
}

/// Both adhkar reminders as the production planner plans them from a completion set, at Fajr + 60 and Asr + 60.
private enum AdhkarReminders {
    /// Three hours east of UTC, as in Riyadh.
    static let zone = TimeZone(secondsFromGMT: 3 * 3600)!
    static let rules = Period.allCases.map {
        ReminderRule.adhkar($0, enabled: true, updatedAt: Date(timeIntervalSince1970: 0))
    }

    static func plan(now: Date, zone: TimeZone = AdhkarReminders.zone,
                     completed: Set<Period>) -> [PlannedNotification] {
        ReminderPlanner.plan(now: now, zone: zone, rules: rules, schedule: { schedule($0, in: zone) },
                             completeToday: completed, firedToday: [])
    }

    /// `hour` o'clock local time on `localDate` in `zone`.
    static func instant(_ localDate: String, hour: Double, in zone: TimeZone = AdhkarReminders.zone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = localDate.split(separator: "-").compactMap { Int($0) }
        let midnight = parts.count == 3
            ? calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) : nil
        return (midnight ?? .distantPast).addingTimeInterval(hour * 3600)
    }

    /// Fajr 04:00, Sunrise 05:30, Dhuhr 12:00, Asr 15:30, Maghrib 18:00 and Isha 19:30 local, every day.
    private static func schedule(_ localDate: String, in zone: TimeZone) -> PrayerSchedule {
        func at(_ hour: Double) -> Date { instant(localDate, hour: hour, in: zone) }
        return PrayerSchedule(localDate: localDate, zone: zone, fajr: at(4), sunrise: at(5.5), dhuhr: at(12),
                              asr: at(15.5), maghrib: at(18), isha: at(19.5))
    }
}
