import AthkarCore
import Foundation
import GRDB
import XCTest
@testable import AthkarModels

/// Each deck's day gate answers for its own session. A day SQLite cannot read keeps only that session's decks on the
/// day before, where every change is dropped; the other decks carry on with the new day. The failure is SQLite's
/// own: a renamed table fails every statement that reads it.
final class DayRolloverTests: XCTestCase {
    @MainActor
    func testUnreadableRuqyahDayLeavesTheAdhkarDecksWorking() throws {
        let decks = try Decks()
        try decks.hide("ruqyah_segment_progress")
        decks.today = Day.tomorrow
        XCTAssertEqual(decks.rollover.roll(to: Day.tomorrow), Set(DeckID.allCases))
        XCTAssertEqual(decks.adhkar.state.date, Day.tomorrow)
        XCTAssertEqual(decks.ruqyah.progress.date, Day.today)
        XCTAssertEqual(decks.reports.messages.count, 1)

        // The adhkar decks show the new day: taps, target changes, card resets and index choices apply to it.
        let first = try decks.position(of: "morning-01", .morning)
        let repeated = try decks.position(of: "morning-02", .morning)
        XCTAssertEqual(decks.tap(.morning, at: first), DeckChange(completedCard: true, advance: true))
        XCTAssertEqual(decks.tap(.morning, at: repeated), DeckChange())
        decks.resetCard(.morning, at: repeated)
        XCTAssertEqual(decks.morning.cards[repeated].count, 0)
        decks.morning.show(repeated)
        XCTAssertEqual(decks.choose("morning-01", on: .morning), first)
        let options = try decks.position(of: "evening-20", .evening)
        XCTAssertEqual(decks.setTarget(1, .evening, at: options), DeckChange())
        XCTAssertEqual(decks.evening.cards[options].target, 1)
        let stored = try decks.database.adhkar.session(on: Day.tomorrow, period: .morning)
        XCTAssertEqual(stored.progress, ["morning-01": 1, "morning-02": 0])
        XCTAssertEqual(try decks.database.adhkar.session(on: Day.tomorrow, period: .evening).targets,
                       ["evening-20": 1])
        XCTAssertTrue(try decks.database.adhkar.session(on: Day.today, period: .morning).progress.isEmpty)

        // The ruqyah deck still shows the day before, so its own gate drops every change made on it.
        let ruqyahCards = decks.ruqyah.cards
        XCTAssertNil(decks.tap(.ruqyah, at: 0))
        XCTAssertNil(decks.choose("qaf-9-14", on: .ruqyah))
        XCTAssertEqual(decks.ruqyah.cards, ruqyahCards)
        XCTAssertEqual(decks.ruqyah.progress.date, Day.today)

        // Once the ruqyah day can be read, the gesture that loads it is dropped and the next one counts on it.
        try decks.restore("ruqyah_segment_progress")
        XCTAssertNil(decks.tap(.ruqyah, at: 0))
        XCTAssertEqual(decks.ruqyah.progress.date, Day.tomorrow)
        XCTAssertNotNil(decks.tap(.ruqyah, at: 0))
        XCTAssertEqual(try decks.database.ruqyah.counts(on: Day.tomorrow)["qaf-1-8"], 1)
        XCTAssertEqual(try decks.database.ruqyah.counts(on: Day.today)["qaf-1-8"] ?? 0, 0)
    }

    @MainActor
    func testUnreadableAdhkarDayLeavesTheRuqyahDeckWorking() throws {
        let decks = try Decks()
        try decks.hide("adhkar_item_progress")
        decks.today = Day.tomorrow
        XCTAssertEqual(decks.rollover.roll(to: Day.tomorrow), Set(DeckID.allCases))
        XCTAssertEqual(decks.adhkar.state.date, Day.today)
        XCTAssertEqual(decks.ruqyah.progress.date, Day.tomorrow)
        XCTAssertEqual(decks.reports.messages.count, 1)

        // The ruqyah deck shows the new day: readings, card resets and index choices apply to it. Every segment
        // before the repeated one is read first, as the «التالي» lock requires to reach it.
        let repeated = try XCTUnwrap(decks.ruqyah.cards.firstIndex { $0.target > 2 })
        XCTAssertEqual(decks.tap(.ruqyah, at: 0), DeckChange(completedCard: true, advance: true, haptic: true))
        for index in 1..<repeated {
            XCTAssertEqual(decks.tap(.ruqyah, at: index), DeckChange(completedCard: true, advance: true, haptic: true))
        }
        XCTAssertEqual(decks.tap(.ruqyah, at: repeated), DeckChange())
        decks.resetCard(.ruqyah, at: repeated)
        XCTAssertEqual(decks.ruqyah.cards[repeated].count, 0)
        XCTAssertEqual(decks.choose(decks.ruqyah.cards[repeated].id, on: .ruqyah), repeated)
        XCTAssertEqual(try decks.database.ruqyah.counts(on: Day.tomorrow)["qaf-1-8"], 1)

        // The adhkar decks still show the day before: their gate drops every change made on them.
        let first = try decks.position(of: "morning-01", .morning)
        let options = try decks.position(of: "evening-20", .evening)
        let adhkarState = decks.adhkar.state
        XCTAssertNil(decks.tap(.morning, at: first))
        XCTAssertNil(decks.setTarget(1, .evening, at: options))
        XCTAssertEqual(decks.adhkar.state, adhkarState)

        // Once the adhkar day can be read, the gesture that loads it is dropped and the next one counts on it.
        try decks.restore("adhkar_item_progress")
        XCTAssertNil(decks.tap(.morning, at: first))
        XCTAssertEqual(decks.adhkar.state.date, Day.tomorrow)
        XCTAssertEqual(decks.tap(.morning, at: first), DeckChange(completedCard: true, advance: true))
        XCTAssertEqual(try decks.database.adhkar.session(on: Day.tomorrow, period: .morning).progress,
                       ["morning-01": 1])
        XCTAssertTrue(try decks.database.adhkar.session(on: Day.today, period: .morning).progress.isEmpty)
    }

    @MainActor
    func testUnreadableSuwarDayLeavesTheOtherDecksWorking() throws {
        let decks = try Decks()
        try decks.hide("suwar_page_reads")
        decks.today = Day.tomorrow
        XCTAssertEqual(decks.rollover.roll(to: Day.tomorrow), Set(DeckID.allCases))
        XCTAssertEqual(decks.adhkar.state.date, Day.tomorrow)
        XCTAssertEqual(decks.ruqyah.progress.date, Day.tomorrow)
        XCTAssertEqual(decks.suwar.date, Day.today)
        XCTAssertEqual(decks.reports.messages.count, 1)

        // The other decks show the new day.
        let first = try decks.position(of: "morning-01", .morning)
        XCTAssertEqual(decks.tap(.morning, at: first), DeckChange(completedCard: true, advance: true))
        XCTAssertEqual(decks.tap(.ruqyah, at: 0), DeckChange(completedCard: true, advance: true, haptic: true))
        XCTAssertEqual(try decks.database.ruqyah.counts(on: Day.tomorrow)["qaf-1-8"], 1)

        // «سور» still shows the day before, so its own gate drops every change made on it.
        let suwarCards = decks.suwar.cards
        XCTAssertNil(decks.tap(.suwar, at: 0))
        XCTAssertNil(decks.choose(decks.suwar.cards[1].id, on: .suwar))
        XCTAssertEqual(decks.suwar.cards, suwarCards)
        XCTAssertEqual(decks.reports.messages.count, 5, "every gate tried the unreadable day again")

        // Once the day can be read, the gesture that loads it is dropped and the next one reads on it.
        try decks.restore("suwar_page_reads")
        XCTAssertNil(decks.tap(.suwar, at: 0))
        XCTAssertEqual(decks.suwar.date, Day.tomorrow)
        XCTAssertEqual(decks.tap(.suwar, at: 0), DeckChange(completedCard: true, advance: true, haptic: true))
        XCTAssertEqual(try decks.database.suwar.readPages(on: Day.tomorrow), ["kahf-1-4"])
        XCTAssertEqual(try decks.database.suwar.readPages(on: Day.today), [])
    }

    /// Every session's day fails to load at midnight, then the clock goes back to the day on screen. The rollover ends
    /// the pending adhkar load, so Settings and the decks change the day on screen instead of loading the later one.
    @MainActor
    func testReturningToTheShownDayEndsAPendingAdhkarLoad() throws {
        let decks = try Decks()
        let tables = ["adhkar_item_progress", "ruqyah_segment_progress", "suwar_page_reads"]
        for table in tables { try decks.hide(table) }
        decks.today = Day.tomorrow
        XCTAssertEqual(decks.rollover.roll(to: Day.tomorrow), Set(DeckID.allCases))
        XCTAssertEqual(decks.adhkar.state.date, Day.today)
        XCTAssertEqual(decks.ruqyah.progress.date, Day.today)
        XCTAssertEqual(decks.suwar.date, Day.today)
        XCTAssertEqual(decks.reports.messages.count, tables.count)
        for table in tables { try decks.restore(table) }

        decks.today = Day.today
        XCTAssertEqual(decks.rollover.roll(to: Day.today), [])
        // Settings' manual completion is saved for the day on screen, as is the next tap.
        XCTAssertTrue(decks.adhkar.setManualCompletion(.evening, completed: true))
        let repeated = try decks.position(of: "morning-02", .morning)
        XCTAssertEqual(decks.tap(.morning, at: repeated), DeckChange())
        XCTAssertEqual(decks.adhkar.state.date, Day.today)
        XCTAssertEqual(try decks.database.adhkar.session(on: Day.today, period: .evening).completion?.completionOrigin,
                       .manual)
        XCTAssertEqual(try decks.database.adhkar.session(on: Day.today, period: .morning).progress,
                       ["morning-02": 1])
        XCTAssertNil(try decks.database.adhkar.session(on: Day.tomorrow, period: .evening).completion)
        XCTAssertEqual(decks.reports.messages.count, tables.count)
    }
}

/// The dates around `PortableTestSupport.today`.
private enum Day {
    static let today = "2026-10-14"
    static let tomorrow = "2026-10-15"
}

/// The errors the sessions reported, in order.
private final class Reports {
    private(set) var messages: [String] = []

    func record(_ error: any Error) {
        messages.append(String(describing: error))
    }
}

/// The app's decks on one production database, a clock that shows `today`, and `DeckView`'s gestures: each
/// runs its deck's gate (`ensureCurrentDay` for that deck) first and is dropped when the gate reports a changed day.
@MainActor
private final class Decks {
    let support: PortableTestSupport
    let reports: Reports
    let adhkar: AdhkarSessionModel
    let morning: AdhkarDeckModel
    let evening: AdhkarDeckModel
    let ruqyah: RuqyahDeckModel
    let suwar: SuwarDeckModel
    /// The local date the clock shows.
    var today: String

    init() throws {
        let support = try PortableTestSupport()
        XCTAssertEqual(support.today, Day.today)
        let reports = Reports()
        let adhkar = try AdhkarSessionModel(database: support.database, content: support.content,
                                            longAdhkarLast: false, today: support.today, report: reports.record)
        self.support = support
        self.reports = reports
        self.adhkar = adhkar
        morning = AdhkarDeckModel(period: .morning, session: adhkar)
        evening = AdhkarDeckModel(period: .evening, session: adhkar)
        ruqyah = try RuqyahDeckModel(database: support.database, content: support.content, today: support.today,
                                     report: reports.record)
        suwar = try SuwarDeckModel(database: support.database, content: support.content, today: support.today,
                                   report: reports.record)
        today = support.today
    }

    var database: AppDatabase { support.database }
    var rollover: DayRollover { DayRollover(adhkar: adhkar, ruqyah: ruqyah, suwar: suwar) }

    func deck(_ id: DeckID) -> any DeckModel {
        switch id {
        case .morning: morning
        case .evening: evening
        case .ruqyah: ruqyah
        case .suwar: suwar
        }
    }

    func position(of id: String, _ period: Period) throws -> Int {
        try XCTUnwrap(adhkar.cards[period].firstIndex { $0.id == id }, "\(id) in the \(period) deck")
    }

    /// `true` when `deck`'s day changed or still cannot be read, so the gesture belongs to the day before.
    func gate(_ deck: DeckID) -> Bool { rollover.roll(to: today).contains(deck) }

    func tap(_ id: DeckID, at index: Int) -> DeckChange? {
        gate(id) ? nil : deck(id).tap(cardAt: index)
    }

    func setTarget(_ target: Int, _ id: DeckID, at index: Int) -> DeckChange? {
        gate(id) ? nil : deck(id).setTarget(target, forCardAt: index)
    }

    func resetCard(_ id: DeckID, at index: Int) {
        guard !gate(id) else { return }
        deck(id).resetCard(at: index)
    }

    /// A row chosen in the quick index, once the sheet has closed: the index the deck moves to, or `nil` to stay.
    func choose(_ cardID: String, on id: DeckID) -> Int? {
        let model = deck(id)
        let choice = model.indexChoice(of: cardID)
        guard !gate(id), let target = model.destination(of: choice) else { return nil }
        model.show(target)
        return target
    }

    /// Until ``restore(_:)``, every statement that reads or writes `table` fails: no such table.
    func hide(_ table: String) throws {
        try database.writer.write { try $0.execute(sql: "ALTER TABLE \(table) RENAME TO hidden_\(table)") }
    }

    func restore(_ table: String) throws {
        try database.writer.write { try $0.execute(sql: "ALTER TABLE hidden_\(table) RENAME TO \(table)") }
    }
}
