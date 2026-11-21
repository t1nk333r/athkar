import Foundation
import GRDB

/// A reading deck (spec/sessions/deck-definition.md §12): «أذكار النوم» (the PWA's `athkar-sleep-v1`) or «الصلاة على
/// النبي ﷺ» (`athkar-salawat-v1`). The raw value keys its rows in `reading_item_progress` and `reading_days`.
public enum ReadingDeck: String, CaseIterable, Codable, Sendable, DatabaseValueConvertible {
    case sleep, salawat

    /// The pack's items that are not counted: the four situational sleep items, said when their occasion comes during
    /// the night rather than at bedtime (§12 "Situational sleep items"). The pack has no field for them yet, so both
    /// platforms list them in code. Salawat's opening card is not a pack item, so the list for it is empty.
    public var uncountedItemIDs: Set<String> {
        switch self {
        case .sleep: ["sleep-14", "sleep-15", "sleep-16", "sleep-17"]
        case .salawat: []
        }
    }
}

/// One counted item of a reading deck on one local date (`athkar-sleep-v1.counts`, `athkar-salawat-v1.counts`). The
/// stored count is raw; readers clamp it to the item's target in the installed pack and ignore an item the pack does
/// not count.
public struct ReadingItemProgress: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "reading_item_progress"

    public var deck: ReadingDeck
    public var localDate: String
    /// The pack's item ID: `sleep-01`, `salawat-02`.
    public var itemId: String
    public var count: Int
    public var updatedAt: Date

    public init(deck: ReadingDeck, localDate: String, itemId: String, count: Int, updatedAt: Date) {
        self.deck = deck
        self.localDate = localDate
        self.itemId = itemId
        self.count = count
        self.updatedAt = updatedAt
    }
}

/// A reading deck recorded complete on one local date (`completedAt` for today, `history` for earlier days). The row
/// alone records the day complete: it is written with the count that completes the deck and deleted with any card
/// reset of that date, so completion follows the counters.
public struct ReadingDay: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "reading_days"

    public var deck: ReadingDeck
    public var localDate: String
    /// When every counted card first reached its target that day.
    public var completedAt: Date

    public init(deck: ReadingDeck, localDate: String, completedAt: Date) {
        self.deck = deck
        self.localDate = localDate
        self.completedAt = completedAt
    }
}

/// The reading decks' rows (spec/schema.md "Reading decks"), each deck apart from the other.
public struct ReadingRepository: Sendable {
    let writer: any DatabaseWriter

    /// Item ID → stored count of `deck` on `localDate` (`counts` for today).
    public func counts(_ deck: ReadingDeck, on localDate: String) throws -> [String: Int] {
        try writer.read { db in
            let rows = try ReadingItemProgress
                .filter(Column("deck") == deck && Column("local_date") == localDate)
                .fetchAll(db)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.itemId, $0.count) })
        }
    }

    /// The day record of `deck` on `localDate`, or `nil` when the day is not complete (`completedAt`).
    public func day(_ deck: ReadingDeck, on localDate: String) throws -> ReadingDay? {
        try writer.read { try ReadingDay.fetchOne($0, key: ["deck": deck, "local_date": localDate]) }
    }

    /// Stores one item's count, in one transaction with the day it completes: with
    /// `completingDayAt`, records `localDate` complete unless it already is, so the first completion time is kept.
    public func setCount(_ count: Int, for itemId: String, in deck: ReadingDeck, on localDate: String,
                         completingDayAt completedAt: Date? = nil, at now: Date = Date()) throws {
        try writer.write { db in
            try ReadingItemProgress(deck: deck, localDate: localDate, itemId: itemId, count: count, updatedAt: now)
                .upsert(db)
            if let completedAt,
               try ReadingDay.fetchOne(db, key: ["deck": deck, "local_date": localDate]) == nil {
                try ReadingDay(deck: deck, localDate: localDate, completedAt: completedAt).insert(db)
            }
        }
    }

    /// The card reset: the item's count back to 0 and the date no longer complete, in one
    /// transaction.
    public func resetItem(_ itemId: String, in deck: ReadingDeck, on localDate: String, at now: Date = Date()) throws {
        try writer.write { db in
            try ReadingItemProgress(deck: deck, localDate: localDate, itemId: itemId, count: 0, updatedAt: now)
                .upsert(db)
            _ = try ReadingDay.deleteOne(db, key: ["deck": deck, "local_date": localDate])
        }
    }

    /// The scoped reset in one transaction: the counts and the day record of `localDate` are deleted (تقدم اليوم),
    /// and with a removal also every row of the deck it covers (هذا الأسبوع, كل شيء). Without a removal, earlier days
    /// keep their rows. The other deck is never touched.
    public func reset(_ deck: ReadingDeck, on localDate: String, removing removal: HistoryRemoval? = nil) throws {
        try writer.write { db in
            let rows = Column("deck") == deck
            try ReadingItemProgress.filter(rows && Column("local_date") == localDate).deleteAll(db)
            try ReadingDay.filter(rows && Column("local_date") == localDate).deleteAll(db)
            if let removal {
                try ReadingItemProgress.filter(rows && removal.covers()).deleteAll(db)
                try ReadingDay.filter(rows && removal.covers()).deleteAll(db)
            }
        }
    }

    /// How many recorded days `removal` covers, as the reset confirmations count them: the dates before `today` with
    /// a day record of `deck`. Today's record is today's progress.
    public func recordedDayCount(_ deck: ReadingDeck, _ removal: HistoryRemoval, before today: String) throws -> Int {
        try writer.read { db in
            try ReadingDay
                .filter(Column("deck") == deck && removal.covers() && Column("local_date") < today)
                .fetchCount(db)
        }
    }
}
