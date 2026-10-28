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
        XCTAssertEqual(deck.tap(cardAt: single), DeckChange(completedCard: true, advance: true, haptic: true))
        XCTAssertEqual(deck.tap(cardAt: repeated), DeckChange())
        XCTAssertEqual(deck.cards[repeated].count, 2)
        XCTAssertEqual(store.reported.count, 2)
        try assertShowsStorage(deck, store)
    }

    @MainActor
    func testRejectedFinalReadingRecordsNothingAndTheRetryRecordsTheFirstCompletion() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        try read(deck, leaving: 1)
        XCTAssertEqual(deck.selectedSectionID, "nas")
        let last = deck.cards.count - 1
        let shown = Shown(deck)
        let stored = try store.stored()
        XCTAssertNil(stored.day)
        XCTAssertEqual(Set(stored.suwar.keys), ["qaf", "jinn", "takwir", "kafirun"])

        try store.reject(["INSERT"], on: "ruqyah_days")
        XCTAssertNil(deck.tap(cardAt: last), "no completion dialog for an unsaved completion")
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(deck), shown)
        XCTAssertFalse(deck.isComplete)
        XCTAssertFalse(deck.isDayComplete)
        XCTAssertEqual(deck.summary.status, "رقية اليوم: ٣٢ من ٣٣ تكرارًا")
        XCTAssertFalse(deck.summary.statusIsComplete)
        // The reading, the sura and the day are one transaction: none was stored.
        XCTAssertEqual(try store.stored(), stored)

        try store.allow(["INSERT"], on: "ruqyah_days")
        let retried = Date()
        XCTAssertEqual(deck.tap(cardAt: last), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        let day = try XCTUnwrap(store.repository.day(on: store.today))
        XCTAssertEqual(day.completionOrigin, .counters)
        XCTAssertGreaterThanOrEqual(day.completedAt.timeIntervalSince1970, retried.timeIntervalSince1970 - 0.001)
        let sura = try XCTUnwrap(store.repository.suraDays(on: store.today)["nas"])
        XCTAssertEqual(sura.timeIntervalSince1970, day.completedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(deck.isComplete)
        XCTAssertTrue(deck.isDayComplete)
        XCTAssertTrue(deck.summary.isComplete)
        XCTAssertTrue(deck.summary.statusIsComplete)
        XCTAssertEqual(deck.completion.primary, .restart, "every segment is complete: the day's dialog")
        XCTAssertEqual(store.reported.count, 1)
        try assertShowsStorage(deck, store)
        XCTAssertTrue(try store.makeDeck().isDayComplete)
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
        XCTAssertEqual(deck.listSummary.value, 0)
        XCTAssertEqual(deck.selectedSectionID, "qaf", "a new ruqyah starts at ق")
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertTrue(deck.isDayComplete)
        XCTAssertEqual(deck.sections.filter(\.isComplete), [])
        XCTAssertTrue(try store.repository.suraDays(on: store.today).isEmpty)
        XCTAssertTrue(deck.canReset)
        XCTAssertEqual(try store.repository.day(on: store.today), first)
        try assertShowsStorage(deck, store)

        XCTAssertEqual(try read(deck), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        let last = deck.cards.count - 1
        deck.resetCard(at: last)
        XCTAssertTrue(deck.isDayComplete)
        XCTAssertNil(try store.repository.suraDays(on: store.today)[deck.selectedSectionID ?? ""])
        XCTAssertEqual(try read(deck), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        XCTAssertEqual(deck.completion.primary, .restart)
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
            (.day, ["DELETE"], "ruqyah_sura_days"), (.everything, ["DELETE"], "ruqyah_sura_days"),
        ]
        for (scope, events, table) in cases {
            let label = "\(scope), \(events) on \(table) rejected"
            let store = try RuqyahStore()
            try store.repository.markComplete(on: "2026-10-01", completedAt: earlierCompletedAt, origin: .imported)
            let deck = try store.makeDeck()
            try read(deck)
            deck.selectSection("jinn")
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
            XCTAssertEqual(deck.listSummary.value, 0, label)
            XCTAssertEqual(deck.selectedSectionID, "qaf", label)
            XCTAssertEqual(deck.currentIndex, 0, label)
            XCTAssertEqual(deck.sections.filter(\.isComplete), [], label)
            XCTAssertTrue(try store.stored().suwar.isEmpty, label)
            switch scope {
            case .day:
                XCTAssertTrue(deck.isDayComplete, label)
                XCTAssertEqual(try store.stored().days, stored.days, label)
            case .week:
                break
            case .everything:
                XCTAssertFalse(deck.isDayComplete, label)
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
        deck.selectSection("qaf")
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
        XCTAssertTrue(deck.isDayComplete)
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

        let tables = [progressTable, "ruqyah_days", "ruqyah_sura_days"]
        for table in tables {
            try store.hide(table)
            XCTAssertThrowsError(try store.makeDeck(on: next), table)
            deck.roll(to: next)
            try store.restore(table)
            XCTAssertEqual(Shown(deck), shown, table)
        }
        XCTAssertEqual(store.reported.count, tables.count)

        deck.roll(to: next)
        XCTAssertEqual(store.reported.count, tables.count)
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
        XCTAssertTrue(deck.isDayComplete)
        XCTAssertTrue(deck.listSummary.isComplete)
        XCTAssertTrue(deck.summary.statusIsComplete)
        XCTAssertEqual(deck.completedAt, importedAt)
        XCTAssertEqual(deck.summary.status, "تمت رقية اليوم في \(ArabicFormat.time(importedAt))")
        XCTAssertGreaterThan(deck.listSummary.value, 0)
        XCTAssertLessThan(deck.listSummary.value, deck.listSummary.total)
        XCTAssertTrue(deck.canReset)
        try assertShowsStorage(deck, store)

        XCTAssertEqual(try read(deck), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        XCTAssertEqual(try store.repository.day(on: store.today),
                       RuqyahDay(localDate: store.today, completedAt: importedAt, completionOrigin: .imported))
        XCTAssertEqual(deck.completedAt, importedAt)
        XCTAssertTrue(store.reported.isEmpty)
        try assertShowsStorage(deck, store)
    }

    /// A scoped reset, «بدء رقية جديدة» included, says whether it was stored, so a refused one is not announced.
    @MainActor
    func testScopedResetReturnsWhetherItWasStored() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        try read(deck)
        XCTAssertEqual(deck.completion.primary, .restart)
        let shown = Shown(deck)

        try store.reject(["UPDATE"], on: progressTable)
        for scope in ResetScope.allCases {
            XCTAssertFalse(deck.reset(scope), "\(scope)")
        }
        XCTAssertEqual(store.reported.count, ResetScope.allCases.count)
        XCTAssertEqual(Shown(deck), shown)
        try store.allow(["UPDATE"], on: progressTable)

        for scope in ResetScope.allCases {
            XCTAssertTrue(deck.reset(scope), "\(scope)")
        }
        XCTAssertEqual(store.reported.count, ResetScope.allCases.count)
        try assertShowsStorage(deck, store)
    }

    // MARK: Suras

    /// `openSuraCompletionDialog`: completing a sura records it and opens its dialog, whose primary action opens the
    /// next sura in order that is still incomplete, wrapping round; the summary row follows the shown sura and the
    /// today line the whole day.
    @MainActor
    func testCompletingASuraOpensItsDialogWithTheNextIncompleteSura() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        XCTAssertEqual(deck.sections.map(\.title), ["ق", "الجن", "التكوير", "الكافرون", "الناس"])
        XCTAssertEqual(deck.sections.map(\.accessibilityLabel),
                       ["سورة ق", "سورة الجن", "سورة التكوير", "سورة الكافرون", "سورة الناس"])
        XCTAssertEqual(deck.summary.copy, "٠ من ١٢ تكرارًا")
        XCTAssertEqual(deck.summary.accessibilityLabel, "سورة ق: ٠ من ١٢ تكرارًا")
        XCTAssertEqual(deck.summary.status, "رقية اليوم: ٠ من ٣٣ تكرارًا")
        XCTAssertEqual(deck.listSummary.copy, "٠ من ٣٣ تكرارًا")
        XCTAssertEqual(deck.cardsLabel, "مقاطع سورة ق")

        let started = Date()
        XCTAssertEqual(try read(deck, sura: "qaf"), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        let qaf = try XCTUnwrap(store.repository.suraDays(on: store.today)["qaf"])
        XCTAssertGreaterThanOrEqual(qaf.timeIntervalSince1970, started.timeIntervalSince1970 - 0.001)
        XCTAssertNil(try store.repository.day(on: store.today))
        XCTAssertTrue(deck.isComplete)
        XCTAssertFalse(deck.isDayComplete)
        XCTAssertEqual(deck.summary.copy, "اكتملت سورة ق اليوم")
        XCTAssertEqual(deck.summary.accessibilityLabel, "سورة ق: ١٢ من ١٢ تكرارًا")
        XCTAssertEqual(deck.summary.status, "رقية اليوم: ١٢ من ٣٣ تكرارًا")
        XCTAssertFalse(deck.summary.statusIsComplete)
        XCTAssertEqual(deck.listSummary.copy, "١٢ من ٣٣ تكرارًا")
        XCTAssertFalse(deck.listSummary.isComplete)
        XCTAssertEqual(deck.sections[0], DeckSection(id: "qaf", title: "ق", isComplete: true,
                                                     accessibilityLabel: "سورة ق، مكتملة اليوم"))
        XCTAssertEqual(deck.completion, DeckCompletion(
            title: "اكتملت قراءة سورة ق بحمد الله", message: "تم حفظ إكمال اليوم محليًا على هذا الجهاز.",
            time: "وقت الإكمال: \(ArabicFormat.time(qaf))", dismissTitle: "تم",
            primaryTitle: "الانتقال إلى سورة الجن", primary: .openSection("jinn")))

        // The next incomplete sura in order, wrapping past the end: after الناس, ق and الجن are done, so التكوير.
        XCTAssertNotNil(try read(deck, sura: "jinn"))
        XCTAssertEqual(deck.completion.primary, .openSection("takwir"))
        XCTAssertEqual(try read(deck, sura: "nas"), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        XCTAssertEqual(deck.completion.primary, .openSection("takwir"))
        XCTAssertEqual(deck.completion.primaryTitle, "الانتقال إلى سورة التكوير")
        XCTAssertEqual(Set(try store.repository.suraDays(on: store.today).keys), ["qaf", "jinn", "nas"])
        XCTAssertTrue(store.reported.isEmpty)
        try assertShowsStorage(deck, store)
    }

    /// A rejected sura record rejects the reading that completes it: nothing is counted, recorded or shown.
    @MainActor
    func testRejectedSuraRecordRecordsNothingAndTheRetryRecordsIt() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        try read(deck, sura: "jinn", leaving: 1)
        let last = deck.cards.count - 1
        let shown = Shown(deck)
        let stored = try store.stored()

        try store.reject(["INSERT"], on: "ruqyah_sura_days")
        XCTAssertNil(deck.tap(cardAt: last), "no haptic or dialog for an unsaved completion")
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(deck), shown)
        XCTAssertEqual(try store.stored(), stored)

        try store.allow(["INSERT"], on: "ruqyah_sura_days")
        XCTAssertEqual(deck.tap(cardAt: last), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        XCTAssertNotNil(try store.repository.suraDays(on: store.today)["jinn"])
        XCTAssertEqual(deck.sections.filter(\.isComplete).map(\.id), ["jinn"])
        XCTAssertEqual(store.reported.count, 1)
        try assertShowsStorage(deck, store)
    }

    /// A chip opens its sura where the reader left it, or on its first incomplete segment; a new day and a reset
    /// forget the positions, and a reset reopens ق.
    @MainActor
    func testEachSuraReopensWhereItWasLeft() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        XCTAssertEqual(deck.selectedSectionID, "qaf")
        XCTAssertNotNil(deck.tap(cardAt: 0))
        XCTAssertTrue(deck.canMoveForward(from: 0))
        XCTAssertFalse(deck.canMoveForward(from: 1), "«التالي» waits for the shown segment")
        deck.show(1)
        deck.selectSection("jinn")
        XCTAssertEqual(deck.cards.map(\.id), ["jinn-1-7", "jinn-8-13", "jinn-14-21", "jinn-22-28"])
        XCTAssertEqual(deck.currentIndex, 0)
        try read(deck, sura: "jinn")
        XCTAssertEqual(deck.currentIndex, 0, "taps do not move the deck; the view advances it")
        deck.show(3)
        deck.selectSection("qaf")
        XCTAssertEqual(deck.currentIndex, 1)
        deck.selectSection("jinn")
        XCTAssertEqual(deck.currentIndex, 3)
        deck.selectSection("missing")
        XCTAssertEqual(deck.selectedSectionID, "jinn")

        // A sura first opened after its earlier segments were read opens on its first incomplete one.
        let fresh = try store.makeDeck()
        fresh.selectSection("qaf")
        XCTAssertEqual(fresh.currentIndex, 1)
        fresh.selectSection("jinn")
        XCTAssertEqual(fresh.currentIndex, 0, "a complete sura opens on its first segment")

        deck.roll(to: "2026-10-15")
        XCTAssertEqual(deck.selectedSectionID, "jinn", "a new day keeps the shown sura")
        XCTAssertEqual(deck.currentIndex, 0)
        deck.selectSection("qaf")
        XCTAssertEqual(deck.currentIndex, 0)
        deck.selectSection("jinn")
        XCTAssertNotNil(deck.tap(cardAt: 0))
        deck.show(1)
        XCTAssertTrue(deck.reset(.day))
        XCTAssertEqual(deck.selectedSectionID, "qaf")
        XCTAssertEqual(deck.currentIndex, 0)
        deck.selectSection("jinn")
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertTrue(store.reported.isEmpty)
    }

    /// `resetSegment` asks first, and its sura is no longer complete today until its segments are read again.
    @MainActor
    func testSegmentResetClearsItsSuraCompletion() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        try read(deck, sura: "qaf")
        try read(deck, sura: "jinn")
        deck.selectSection("qaf")
        let last = deck.cards.count - 1
        XCTAssertEqual(deck.resetConfirmation(forCardAt: last), DeckConfirmation(
            title: "إعادة العداد؟", message: "سيعود عداد سورة ق الآيات ٣٨ – ٤٥ إلى الصفر."))
        XCTAssertEqual(deck.cards[last].resetLabel, "إعادة عداد المقطع ٦")
        deck.resetCard(at: last)
        XCTAssertEqual(deck.cards[last].count, 0)
        XCTAssertEqual(deck.sections.filter(\.isComplete).map(\.id), ["jinn"])
        XCTAssertEqual(Set(try store.repository.suraDays(on: store.today).keys), ["jinn"])
        XCTAssertNil(deck.resetConfirmation(forCardAt: last), "nothing to reset")
        try assertShowsStorage(deck, store)

        let again = Date()
        XCTAssertEqual(deck.tap(cardAt: last), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        let qaf = try XCTUnwrap(store.repository.suraDays(on: store.today)["qaf"])
        XCTAssertGreaterThanOrEqual(qaf.timeIntervalSince1970, again.timeIntervalSince1970 - 0.001)
        XCTAssertTrue(store.reported.isEmpty)
        try assertShowsStorage(deck, store)
    }

    /// A rejected segment reset keeps both the counter and its sura's completion.
    @MainActor
    func testRejectedSegmentResetKeepsTheSuraComplete() throws {
        let store = try RuqyahStore()
        let deck = try store.makeDeck()
        try read(deck, sura: "kafirun")
        let shown = Shown(deck)
        let stored = try store.stored()

        try store.reject(["DELETE"], on: "ruqyah_sura_days")
        deck.resetCard(at: 0)
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(deck), shown)
        XCTAssertEqual(try store.stored(), stored)

        try store.allow(["DELETE"], on: "ruqyah_sura_days")
        deck.resetCard(at: 0)
        XCTAssertEqual(deck.cards[0].count, 0)
        XCTAssertTrue(try store.repository.suraDays(on: store.today).isEmpty)
        XCTAssertEqual(store.reported.count, 1)
        try assertShowsStorage(deck, store)
    }

    /// `backfillSuwarCompletions`: a sura complete by its counters with no record of its own takes the day's record
    /// time, and with no day record it has no time; none is invented.
    @MainActor
    func testSuraCompleteByItsCountersTakesOnlyTheDayRecordTime() throws {
        let store = try RuqyahStore()
        for id in ["qaf-1-8", "qaf-9-14", "qaf-15-22", "qaf-30-37", "qaf-38-45"] {
            try store.repository.setCount(1, for: id, on: store.today)
        }
        try store.repository.setCount(7, for: "qaf-23-29", on: store.today)
        let unrecorded = try store.makeDeck()
        XCTAssertTrue(unrecorded.isComplete)
        XCTAssertEqual(unrecorded.sections[0].isComplete, true)
        XCTAssertNil(unrecorded.completion.time)
        XCTAssertEqual(unrecorded.completion.primary, .openSection("jinn"))
        XCTAssertTrue(try store.repository.suraDays(on: store.today).isEmpty)

        try store.repository.markComplete(on: store.today, completedAt: todayCompletedAt, origin: .imported)
        let recorded = try store.makeDeck()
        XCTAssertEqual(recorded.completion.time, "وقت الإكمال: \(ArabicFormat.time(todayCompletedAt))")
        XCTAssertTrue(try store.repository.suraDays(on: store.today).isEmpty, "the backfill is not stored")
        XCTAssertNil(recorded.tap(cardAt: 0), "a complete segment counts no further")
    }

    /// The scoped reset counts the days it deletes as the PWA's `historyDates`: completed days, and earlier days with
    /// a completed sura; a day with a completed sura alone is history the reset can delete.
    @MainActor
    func testEarlierSuraCompletionsAreHistory() throws {
        let store = try RuqyahStore()
        try store.repository.setCount(7, for: "nas-1-6", on: "2026-10-01", completingSura: "nas")
        try store.repository.markComplete(on: "2026-10-02", completedAt: earlierCompletedAt, origin: .imported)
        try store.repository.setCount(7, for: "nas-1-6", on: "2026-10-02", completingSura: "nas")
        let deck = try store.makeDeck()
        XCTAssertTrue(deck.hasHistory)
        XCTAssertTrue(deck.canReset)
        XCTAssertEqual(deck.confirmation(for: .everything)?.message,
                       "ستُعاد العدادات وسيُحذف السجل كاملًا (يومين). لا يمكن التراجع.")
        // Today's completed sura is today's progress, not history.
        try read(deck, sura: "nas")
        XCTAssertEqual(deck.confirmation(for: .everything)?.message,
                       "ستُعاد العدادات وسيُحذف السجل كاملًا (يومين). لا يمكن التراجع.")

        XCTAssertTrue(deck.reset(.everything))
        XCTAssertFalse(deck.hasHistory)
        XCTAssertFalse(deck.canReset)
        XCTAssertEqual(try store.repository.recordedDayCount(.all, before: "9999-12-31"), 0)
        XCTAssertNil(deck.confirmation(for: .day))
        XCTAssertEqual(deck.confirmation(for: .everything)?.message,
                       "ستُعاد العدادات وسيُحذف السجل كاملًا. لا يمكن التراجع.")
        XCTAssertTrue(store.reported.isEmpty)
        try assertShowsStorage(deck, store)
    }

    // MARK: Support

    /// Selects `sura` and taps its remaining readings in order, except the last `leaving` ones; returns the final
    /// change.
    @MainActor
    @discardableResult
    private func read(_ deck: RuqyahDeckModel, sura: String, leaving: Int = 0) throws -> DeckChange? {
        deck.selectSection(sura)
        XCTAssertEqual(deck.selectedSectionID, sura)
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

    /// Taps every remaining reading of the day in pack order, sura by sura, except the last `leaving` ones, and
    /// returns the final change. The deck is left on the sura of the last reading counted.
    @MainActor
    @discardableResult
    private func read(_ deck: RuqyahDeckModel, leaving: Int = 0) throws -> DeckChange? {
        var left = deck.listSummary.total - deck.listSummary.value - leaving
        var change: DeckChange?
        for section in deck.sections where left > 0 {
            deck.selectSection(section.id)
            for index in deck.cards.indices {
                while left > 0, deck.cards[index].count < deck.cards[index].target {
                    change = try XCTUnwrap(deck.tap(cardAt: index))
                    left -= 1
                }
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
        XCTAssertEqual(deck.isDayComplete, day != nil, file: file, line: line)
        XCTAssertEqual(deck.completedAt == nil, day == nil, file: file, line: line)
        let suwar = try store.repository.suraDays(on: date)
        XCTAssertEqual(Set(deck.completedSuwar.keys), Set(suwar.keys), file: file, line: line)
        for (sura, completedAt) in suwar {
            XCTAssertEqual(try XCTUnwrap(deck.completedSuwar[sura]).timeIntervalSince1970,
                           completedAt.timeIntervalSince1970, accuracy: 0.001, file: file, line: line)
        }
        if let shown = deck.completedAt, let day {
            XCTAssertEqual(shown.timeIntervalSince1970, day.completedAt.timeIntervalSince1970, accuracy: 0.001,
                           file: file, line: line)
        }
        XCTAssertEqual(deck.hasHistory, try store.repository.recordedDayCount(.all, before: date) > 0,
                       file: file, line: line)
        let loaded = try store.makeDeck(on: date)
        if let sura = deck.selectedSectionID { loaded.selectSection(sura) }
        XCTAssertEqual(deck.cards, loaded.cards, file: file, line: line)
        XCTAssertEqual(deck.sections, loaded.sections, file: file, line: line)
    }
}

/// What the deck shows: compared before and after a rejected change.
private struct Shown: Equatable {
    var progress: RuqyahProgress
    var completedAt: Date?
    var isComplete: Bool
    var hasHistory: Bool
    var selectedSectionID: String?
    var currentIndex: Int
    var cards: [DeckCard]
    var sections: [DeckSection]
    var completedSuwar: [String: Date]
    var summary: DeckSummary
    var listSummary: DeckSummary

    @MainActor
    init(_ deck: RuqyahDeckModel) {
        progress = deck.progress
        completedAt = deck.completedAt
        isComplete = deck.isDayComplete
        hasHistory = deck.hasHistory
        selectedSectionID = deck.selectedSectionID
        currentIndex = deck.currentIndex
        cards = deck.cards
        sections = deck.sections
        completedSuwar = deck.completedSuwar
        summary = deck.summary
        listSummary = deck.listSummary
    }
}

/// A ruqyah deck on the production database, with real SQLite failures: a temporary trigger aborts one kind of
/// write to a table (and with it the whole transaction), and a renamed table fails every statement that uses it.
@MainActor
private final class RuqyahStore {
    struct Stored: Equatable {
        var counts: [String: Int]
        var day: RuqyahDay?
        var suwar: [String: Date]
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
               suwar: try repository.suraDays(on: today), days: try repository.dayCount(.all))
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
