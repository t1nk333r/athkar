import AthkarCore
import Foundation
import GRDB
import XCTest
@testable import AthkarModels

private let readsTable = "suwar_page_reads"
private let suraTable = "suwar_sura_days"
/// A setting is an upsert: rejecting both kinds of statement rejects it whether or not its row exists.
private let settingWrites = ["INSERT", "UPDATE"]
/// 2026-10-01T05:00:00Z.
private let earlierReadAt = Date(timeIntervalSince1970: 1_790_830_800)

/// «سور» shows a read page, a reset, a completion or a chosen sura only once SQLite has stored it, and never shows
/// a day it could not read. The failures are real SQLite errors in the production database (``SuwarStore``).
final class SuwarPersistenceTests: XCTestCase {
    @MainActor
    func testRejectedReadIsNotShownAndARetryRecordsItOnce() throws {
        let store = try SuwarStore()
        let deck = try store.makeDeck()
        XCTAssertNotNil(deck.tap(cardAt: 0))
        let shown = Shown(deck)
        let stored = try store.stored()

        try store.reject(["INSERT"], on: readsTable)
        XCTAssertNil(deck.tap(cardAt: 1), "no haptic, advance or announcement for an unsaved read")
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(deck), shown)
        XCTAssertFalse(deck.canMoveForward(from: 1))
        XCTAssertEqual(try store.stored(), stored)

        try store.allow(["INSERT"], on: readsTable)
        XCTAssertEqual(deck.tap(cardAt: 1), DeckChange(completedCard: true, advance: true, haptic: true))
        XCTAssertNil(deck.tap(cardAt: 1))
        XCTAssertEqual(try store.repository.readPages(on: store.today), ["kahf-1-4", "kahf-5-8"])
        XCTAssertEqual(store.reported.count, 1)
        try assertShowsStorage(deck, store)
    }

    /// The page that completes a sura and the sura's record are one transaction: a rejected record stores neither.
    @MainActor
    func testRejectedSuraRecordRollsBackItsPageAndTheRetryRecordsBoth() throws {
        let store = try SuwarStore()
        let deck = try store.makeDeck()
        deck.selectSection("mulk")
        for index in 0..<6 { XCTAssertNotNil(deck.tap(cardAt: index)) }
        let shown = Shown(deck)
        let stored = try store.stored()

        try store.reject(["INSERT"], on: suraTable)
        XCTAssertNil(deck.tap(cardAt: 6), "no haptic or dialog for an unsaved completion")
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(deck), shown)
        XCTAssertFalse(deck.isComplete)
        XCTAssertEqual(try store.stored(), stored)
        XCTAssertFalse(try store.repository.readPages(on: store.today).contains("mulk-27-30"))

        try store.allow(["INSERT"], on: suraTable)
        let retried = Date()
        XCTAssertEqual(deck.tap(cardAt: 6), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        let mulk = try XCTUnwrap(store.repository.suraDays(on: store.today)["mulk"])
        XCTAssertGreaterThanOrEqual(mulk.timeIntervalSince1970, retried.timeIntervalSince1970 - 0.001)
        XCTAssertTrue(deck.isComplete)
        XCTAssertEqual(store.reported.count, 1)
        try assertShowsStorage(deck, store)
    }

    /// A rejected page reset keeps the page read and its sura complete.
    @MainActor
    func testRejectedPageResetKeepsThePageAndItsSura() throws {
        for table in [readsTable, suraTable] {
            let store = try SuwarStore()
            let deck = try store.makeDeck()
            deck.selectSection("mulk")
            for index in deck.cards.indices { XCTAssertNotNil(deck.tap(cardAt: index)) }
            let shown = Shown(deck)
            let stored = try store.stored()

            try store.reject(["DELETE"], on: table)
            deck.resetCard(at: 3)
            XCTAssertEqual(store.reported.count, 1, table)
            XCTAssertEqual(Shown(deck), shown, table)
            XCTAssertEqual(try store.stored(), stored, table)

            try store.allow(["DELETE"], on: table)
            deck.resetCard(at: 3)
            XCTAssertFalse(deck.cards[3].isComplete, table)
            XCTAssertFalse(deck.isComplete, table)
            XCTAssertTrue(try store.repository.suraDays(on: store.today).isEmpty, table)
            XCTAssertEqual(store.reported.count, 1, table)
            try assertShowsStorage(deck, store)
        }
    }

    /// A sura chosen but not stored is not shown: the app would reopen on the old one.
    @MainActor
    func testRejectedSelectionKeepsTheShownSura() throws {
        let store = try SuwarStore()
        let deck = try store.makeDeck()
        XCTAssertNotNil(deck.tap(cardAt: 0))
        deck.show(1)
        let shown = Shown(deck)

        try store.reject(settingWrites, on: "settings")
        deck.selectSection("saffat")
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(deck), shown)
        XCTAssertEqual(try store.support.database.settings.value(for: .suwarSelectedSura), "kahf")

        try store.allow(settingWrites, on: "settings")
        deck.selectSection("saffat")
        XCTAssertEqual(deck.selectedSectionID, "saffat")
        XCTAssertEqual(deck.cards.first?.id, "saffat-1-9")
        XCTAssertEqual(try store.support.database.settings.value(for: .suwarSelectedSura), "saffat")
        deck.selectSection("kahf")
        XCTAssertEqual(deck.currentIndex, 1, "kahf reopens where it was left")
        XCTAssertEqual(store.reported.count, 1)
        try assertShowsStorage(deck, store)
    }

    /// A rejected تقدم اليوم / هذا الأسبوع / كل شيء changes nothing, the reader's position included; deleting the
    /// history and clearing today are one transaction.
    @MainActor
    func testRejectedScopedResetsKeepPagesHistoryAndPosition() throws {
        let cases: [(ResetScope, String)] = [
            (.day, readsTable), (.day, suraTable), (.week, readsTable), (.everything, readsTable),
            (.everything, suraTable),
        ]
        for (scope, table) in cases {
            let label = "\(scope), DELETE on \(table) rejected"
            let store = try SuwarStore()
            try store.repository.markRead("mulk-27-30", of: "mulk", on: "2026-10-01", completingSura: true,
                                          at: earlierReadAt)
            let deck = try store.makeDeck()
            deck.selectSection("mulk")
            for index in deck.cards.indices { XCTAssertNotNil(deck.tap(cardAt: index), label) }
            deck.selectSection("yasin")
            XCTAssertNotNil(deck.tap(cardAt: 0), label)
            deck.show(1)
            let shown = Shown(deck)
            let stored = try store.stored()

            try store.reject(["DELETE"], on: table)
            XCTAssertFalse(deck.reset(scope), label)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertEqual(Shown(deck), shown, label)
            XCTAssertEqual(try store.stored(), stored, label)

            try store.allow(["DELETE"], on: table)
            XCTAssertTrue(deck.reset(scope), label)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertEqual(deck.selectedSectionID, "yasin", label)
            XCTAssertEqual(deck.currentIndex, 0, label)
            XCTAssertTrue(deck.readPages.isEmpty, label)
            XCTAssertEqual(deck.sections.filter(\.isComplete), [], label)
            XCTAssertTrue(try store.repository.suraDays(on: store.today).isEmpty, label)
            switch scope {
            case .day:
                XCTAssertTrue(deck.hasHistory, label)
                XCTAssertEqual(try store.stored().days, 1, label)
            case .week:
                break
            case .everything:
                XCTAssertFalse(deck.canReset, label)
                XCTAssertEqual(try store.stored().days, 0, label)
            }
            try assertShowsStorage(deck, store)
        }
    }

    /// A scoped reset says whether it was stored, so a refused one is not announced. With the history unreadable,
    /// none can be stored.
    @MainActor
    func testScopedResetReturnsWhetherItWasStored() throws {
        let store = try SuwarStore()
        let deck = try store.makeDeck()
        deck.selectSection("waqiah")
        for index in deck.cards.indices { XCTAssertNotNil(deck.tap(cardAt: index)) }
        let shown = Shown(deck)

        try store.hide(suraTable)
        for scope in ResetScope.allCases {
            XCTAssertFalse(deck.reset(scope), "\(scope)")
        }
        XCTAssertEqual(store.reported.count, ResetScope.allCases.count)
        XCTAssertEqual(Shown(deck), shown)
        try store.restore(suraTable)

        for scope in ResetScope.allCases {
            XCTAssertTrue(deck.reset(scope), "\(scope)")
        }
        XCTAssertEqual(store.reported.count, ResetScope.allCases.count)
        try assertShowsStorage(deck, store)
    }

    /// A new day that cannot be read is not shown as empty: the deck keeps its day, and the next roll retries. A
    /// launch that cannot read its day or its sura fails rather than showing an empty one.
    @MainActor
    func testUnreadableNewDayKeepsTheCurrentDayUntilARetryLoadsIt() throws {
        let store = try SuwarStore()
        let deck = try store.makeDeck()
        XCTAssertNotNil(deck.tap(cardAt: 0))
        // A page already read on the next date, as after moving back across a time-zone boundary.
        let next = "2026-10-15"
        try store.repository.markRead("kahf-5-8", of: "kahf", on: next)
        let shown = Shown(deck)

        let tables = [readsTable, suraTable]
        for table in tables {
            try store.hide(table)
            XCTAssertThrowsError(try store.makeDeck(on: next), table)
            deck.roll(to: next)
            try store.restore(table)
            XCTAssertEqual(Shown(deck), shown, table)
        }
        XCTAssertEqual(store.reported.count, tables.count)
        try store.hide("settings")
        XCTAssertThrowsError(try store.makeDeck(), "the stored sura cannot be read")
        try store.restore("settings")

        deck.roll(to: next)
        XCTAssertEqual(store.reported.count, tables.count)
        XCTAssertEqual(deck.date, next)
        XCTAssertEqual(deck.readPages, ["kahf-5-8"])
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertFalse(deck.hasHistory, "today's pages completed no sura")
        try assertShowsStorage(deck, store)
        XCTAssertEqual(try store.repository.readPages(on: store.today), ["kahf-1-4"])
    }

    // MARK: Support

    /// The deck shows exactly what loading its day from the database shows, the chosen sura included.
    @MainActor
    private func assertShowsStorage(_ deck: SuwarDeckModel, _ store: SuwarStore,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let date = deck.date
        XCTAssertEqual(deck.readPages, try store.repository.readPages(on: date), file: file, line: line)
        let suwar = try store.repository.suraDays(on: date)
        XCTAssertEqual(Set(deck.completedSuwar.keys), Set(suwar.keys), file: file, line: line)
        for (sura, completedAt) in suwar {
            XCTAssertEqual(try XCTUnwrap(deck.completedSuwar[sura]).timeIntervalSince1970,
                           completedAt.timeIntervalSince1970, accuracy: 0.001, file: file, line: line)
        }
        XCTAssertEqual(deck.hasHistory, try store.repository.recordedDayCount(.all, before: date) > 0,
                       file: file, line: line)
        let loaded = try store.makeDeck(on: date)
        XCTAssertEqual(loaded.selectedSectionID, deck.selectedSectionID, file: file, line: line)
        XCTAssertEqual(deck.cards, loaded.cards, file: file, line: line)
        XCTAssertEqual(deck.sections, loaded.sections, file: file, line: line)
        XCTAssertEqual(deck.summary, loaded.summary, file: file, line: line)
        XCTAssertEqual(deck.listSummary, loaded.listSummary, file: file, line: line)
    }
}

/// What the deck shows: compared before and after a rejected change.
private struct Shown: Equatable {
    var date: String
    var readPages: Set<String>
    var completedSuwar: [String: Date]
    var hasHistory: Bool
    var selectedSectionID: String?
    var currentIndex: Int
    var cards: [DeckCard]
    var sections: [DeckSection]
    var summary: DeckSummary
    var listSummary: DeckSummary
    var canReset: Bool

    @MainActor
    init(_ deck: SuwarDeckModel) {
        date = deck.date
        readPages = deck.readPages
        completedSuwar = deck.completedSuwar
        hasHistory = deck.hasHistory
        selectedSectionID = deck.selectedSectionID
        currentIndex = deck.currentIndex
        cards = deck.cards
        sections = deck.sections
        summary = deck.summary
        listSummary = deck.listSummary
        canReset = deck.canReset
    }
}

/// A «سور» deck on the production database, with real SQLite failures: a temporary trigger aborts one kind of
/// write to a table (and with it the whole transaction), and a renamed table fails every statement that uses it.
@MainActor
private final class SuwarStore {
    struct Stored: Equatable {
        var pages: Set<String>
        var suwar: [String: Date]
        var days: Int
        var selected: String
    }

    let support: PortableTestSupport
    /// Every error the deck reported, in order.
    private(set) var reported: [String] = []

    init() throws {
        support = try PortableTestSupport()
    }

    var today: String { support.today }
    var repository: SuwarRepository { support.database.suwar }

    func makeDeck(on date: String? = nil) throws -> SuwarDeckModel {
        try SuwarDeckModel(database: support.database, content: support.content, today: date ?? today,
                           report: { self.reported.append(String(describing: $0)) })
    }

    /// Today's rows and the stored sura, as stored.
    func stored() throws -> Stored {
        Stored(pages: try repository.readPages(on: today), suwar: try repository.suraDays(on: today),
               days: try repository.recordedDayCount(.all, before: today),
               selected: try support.database.settings.value(for: .suwarSelectedSura))
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
