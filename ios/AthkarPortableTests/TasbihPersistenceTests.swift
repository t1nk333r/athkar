import AthkarCore
import Foundation
import GRDB
import XCTest
@testable import AthkarModels

private let countsTable = "tasbih_counts"
/// A setting is an upsert: rejecting both kinds of statement rejects it whether or not its row exists.
private let settingWrites = ["INSERT", "UPDATE"]

/// «مسبحة» shows a count, a phrase, a target or a reset only once SQLite has stored it, and never shows a day it
/// could not read. The failures are real SQLite errors in the production database (``TasbihStore``).
final class TasbihPersistenceTests: XCTestCase {
    /// A count that is not stored is not shown and returns no change: no haptic, ring or announcement. A retry
    /// stores it once.
    @MainActor
    func testRejectedCountsAreNotShownAndARetryStoresThem() throws {
        let cases: [(String, String, (TasbihModel) -> TasbihModel.Change?)] = [
            ("INSERT", "a first count", { $0.add() }),
            ("UPDATE", "a further count", { $0.add() }),
            ("UPDATE", "an undo", { $0.undo() }),
            ("DELETE", "an undo to zero", { $0.undo() }),
            ("DELETE", "a confirmed reset", { $0.resetCount() }),
        ]
        for (event, label, action) in cases {
            let store = try TasbihStore()
            let model = try store.makeModel()
            XCTAssertNotNil(model.select("hamd"), label)
            if label != "a first count" { XCTAssertNotNil(model.add(), label) }
            if label == "an undo" { XCTAssertNotNil(model.add(), label) }
            let shown = Shown(model)
            let stored = try store.stored()

            try store.reject([event], on: countsTable)
            XCTAssertNil(action(model), label)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertEqual(Shown(model), shown, label)
            XCTAssertEqual(try store.stored(), stored, label)

            try store.allow([event], on: countsTable)
            XCTAssertNotNil(action(model), label)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertNotEqual(Shown(model), shown, label)
            try assertShowsStorage(model, store)
        }
    }

    /// The phrase counted, the target and the saved phrases are stored before they are shown: a rejected write
    /// keeps the counter as it was.
    @MainActor
    func testRejectedPreferencesKeepThePhraseAndTarget() throws {
        let cases: [(String, (TasbihModel) -> TasbihModel.Change?)] = [
            ("select", { $0.select("hamd") }),
            ("setTarget", { $0.setTarget(100) }),
            ("setTarget nil", { $0.setTarget(nil) }),
            ("addPhrase", { $0.addPhrase("حسبي الله") }),
            ("deletePhrase", { $0.deletePhrase("يا رب") }),
        ]
        for (label, action) in cases {
            let store = try TasbihStore()
            let model = try store.makeModel()
            XCTAssertNotNil(model.addPhrase("يا رب"), label)
            XCTAssertNotNil(model.add(), label)
            let shown = Shown(model)
            let stored = try store.stored()

            try store.reject(settingWrites, on: "settings")
            XCTAssertNil(action(model), label)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertEqual(Shown(model), shown, label)
            XCTAssertEqual(try store.stored(), stored, label)

            try store.allow(settingWrites, on: "settings")
            XCTAssertNotNil(action(model), label)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertNotEqual(Shown(model), shown, label)
            try assertShowsStorage(model, store)
        }
    }

    /// Saving a phrase and taking its earlier spelling's counts are one transaction: when either is refused, the
    /// phrase is not saved and the counts stay where they were.
    @MainActor
    func testRejectedAdoptionSavesNeitherThePhraseNorItsCounts() throws {
        for (event, table) in [("DELETE", countsTable), ("INSERT", countsTable), ("UPDATE", countsTable),
                               ("INSERT", "settings")] {
            let label = "\(event) on \(table) rejected"
            let store = try TasbihStore()
            try store.repository.setCount(2, for: "c:يَا رَبّ", on: "2026-10-10")
            try store.repository.setCount(3, for: "c:يَا رَبّ", on: store.today)
            try store.repository.setCount(4, for: "c:يا رب", on: store.today)
            let model = try store.makeModel()
            let shown = Shown(model)
            let stored = try store.stored()
            let earlier = try store.repository.counts(on: "2026-10-10")

            try store.reject([event], on: table)
            XCTAssertNil(model.addPhrase("يا رب"), label)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertEqual(Shown(model), shown, label)
            XCTAssertEqual(try store.stored(), stored, label)
            XCTAssertEqual(try store.repository.counts(on: "2026-10-10"), earlier, label)

            try store.allow([event], on: table)
            XCTAssertNotNil(model.addPhrase("يا رب"), label)
            XCTAssertEqual(model.counts, [TasbihModel.PhraseCount(key: "c:يا رب", count: 7)], label)
            XCTAssertEqual(try store.repository.counts(on: "2026-10-10").map(\.phraseKey), ["c:يا رب"], label)
            XCTAssertEqual(store.reported.count, 1, label)
            try assertShowsStorage(model, store)
        }
    }

    /// Without the counts table, a phrase is not saved: the earlier spellings it would take cannot be read.
    @MainActor
    func testUnreadableCountsSaveNoPhrase() throws {
        let store = try TasbihStore()
        let model = try store.makeModel()
        XCTAssertNotNil(model.add())
        let shown = Shown(model)

        try store.hide(countsTable)
        XCTAssertNil(model.addPhrase("يا رب"))
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(Shown(model), shown)
        try store.restore(countsTable)
        XCTAssertEqual(try store.support.database.settings.value(for: .tasbihCustomPhrases), [])
        XCTAssertEqual(try store.support.database.settings.value(for: .tasbihSelected), "subhan")

        XCTAssertNotNil(model.addPhrase("يا رب"))
        XCTAssertEqual(store.reported.count, 1)
        try assertShowsStorage(model, store)
    }

    /// A rejected تقدم اليوم / هذا الأسبوع / كل شيء changes nothing; clearing today and deleting the history are one
    /// transaction. With the counts unreadable, no reset can be stored.
    @MainActor
    func testRejectedScopedResetsKeepTodayAndTheHistory() throws {
        for scope in ResetScope.allCases {
            let label = "\(scope)"
            let store = try TasbihStore()
            try store.repository.setCount(4, for: "subhan", on: "2026-10-10")
            let model = try store.makeModel()
            XCTAssertNotNil(model.add(), label)
            XCTAssertNotNil(model.setTarget(100), label)
            let shown = Shown(model)
            let stored = try store.stored()

            try store.reject(["DELETE"], on: countsTable)
            XCTAssertFalse(model.reset(scope), label)
            XCTAssertEqual(store.reported.count, 1, label)
            XCTAssertEqual(Shown(model), shown, label)
            XCTAssertEqual(try store.stored(), stored, label)
            try store.allow(["DELETE"], on: countsTable)

            try store.hide(countsTable)
            XCTAssertFalse(model.reset(scope), label)
            XCTAssertEqual(store.reported.count, 2, label)
            XCTAssertEqual(Shown(model), shown, label)
            try store.restore(countsTable)

            XCTAssertTrue(model.reset(scope), label)
            XCTAssertEqual(store.reported.count, 2, label)
            XCTAssertEqual(model.counts, [], label)
            XCTAssertEqual(model.target, 100, label)
            XCTAssertEqual(try store.stored().days, scope == .everything ? 0 : 1, label)
            try assertShowsStorage(model, store)
        }
    }

    /// A new day that cannot be read is not shown as empty: the counter keeps its day, and the next roll retries.
    /// A launch that cannot read its counts or preferences fails rather than showing an empty counter.
    @MainActor
    func testUnreadableNewDayKeepsTheCurrentDayUntilARetryLoadsIt() throws {
        let store = try TasbihStore()
        let model = try store.makeModel()
        XCTAssertNotNil(model.add())
        let next = "2026-10-15"
        try store.repository.setCount(2, for: "hamd", on: next)
        let shown = Shown(model)

        try store.hide(countsTable)
        XCTAssertThrowsError(try store.makeModel(on: next))
        model.roll(to: next)
        try store.restore(countsTable)
        XCTAssertEqual(Shown(model), shown)
        XCTAssertEqual(store.reported.count, 1)
        try store.hide("settings")
        XCTAssertThrowsError(try store.makeModel(), "the stored preferences cannot be read")
        try store.restore("settings")

        model.roll(to: next)
        XCTAssertEqual(store.reported.count, 1)
        XCTAssertEqual(model.date, next)
        XCTAssertEqual(model.counts, [TasbihModel.PhraseCount(key: "hamd", count: 2)])
        XCTAssertTrue(model.hasHistory)
        try assertShowsStorage(model, store)
    }

    // MARK: Support

    /// The counter shows exactly what loading its day from the database shows.
    @MainActor
    private func assertShowsStorage(_ model: TasbihModel, _ store: TasbihStore,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let date = model.date
        let rows = try store.repository.counts(on: date)
        XCTAssertEqual(model.counts.map { Array($0.key.utf16) }, rows.map { Array($0.phraseKey.utf16) },
                       file: file, line: line)
        XCTAssertEqual(model.counts.map(\.count), rows.map(\.count), file: file, line: line)
        XCTAssertEqual(model.hasHistory, try store.repository.recordedDayCount(.all, before: date) > 0,
                       file: file, line: line)
        let loaded = try store.makeModel(on: date)
        XCTAssertEqual(Shown(loaded), Shown(model), file: file, line: line)
    }
}

/// What the counter shows: compared before and after a rejected change.
private struct Shown: Equatable {
    var date: String
    var counts: [[UInt16]: Int]
    var order: [[UInt16]]
    var selected: [UInt16]
    var target: Int?
    var custom: [[UInt16]]
    var hasHistory: Bool
    var status: String
    var summaryLabel: String
    var totalText: String
    var presetOptions: [TasbihModel.Option]
    var customOptions: [TasbihModel.Option]
    var canReset: Bool

    @MainActor
    init(_ model: TasbihModel) {
        date = model.date
        counts = Dictionary(uniqueKeysWithValues: model.counts.map { (Array($0.key.utf16), $0.count) })
        order = model.counts.map { Array($0.key.utf16) }
        selected = Array(model.selected.utf16)
        target = model.target
        custom = model.custom.map { Array($0.utf16) }
        hasHistory = model.hasHistory
        status = model.status.text
        summaryLabel = model.summaryLabel
        totalText = model.totalText
        presetOptions = model.presetOptions
        customOptions = model.customOptions
        canReset = model.canReset
    }
}

/// A counter on the production database, with real SQLite failures: a temporary trigger aborts one kind of write to
/// a table (and with it the whole transaction), and a renamed table fails every statement that uses it.
@MainActor
private final class TasbihStore {
    struct Stored: Equatable {
        var counts: [TasbihCount]
        var days: Int
        var selected: String
        var target: Int
        var custom: [String]
    }

    let support: PortableTestSupport
    /// Every error the counter reported, in order.
    private(set) var reported: [String] = []

    init() throws {
        support = try PortableTestSupport()
    }

    var today: String { support.today }
    var repository: TasbihRepository { support.database.tasbih }

    func makeModel(on date: String? = nil) throws -> TasbihModel {
        try TasbihModel(database: support.database, today: date ?? today,
                        report: { self.reported.append(String(describing: $0)) })
    }

    /// Today's rows and the stored preferences, as stored.
    func stored() throws -> Stored {
        let settings = support.database.settings
        return Stored(counts: try repository.counts(on: today),
                      days: try repository.recordedDayCount(.all, before: today),
                      selected: try settings.value(for: .tasbihSelected),
                      target: try settings.value(for: .tasbihTarget),
                      custom: try settings.value(for: .tasbihCustomPhrases))
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
