import Foundation
import GRDB

/// One «مسبحة» phrase counted on one local date (the athkar PWA's `athkar-tasbih-v1`: `counts` for today, `history`
/// for earlier days). `firstUse` orders a day's phrases by their first count that day (`firstUse`); a phrase brought
/// back to zero has no row, so its next count puts it last.
public struct TasbihCount: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "tasbih_counts"
    /// `tasbihMaxCount`: a count stops here.
    public static let maxCount = 99_999

    public var localDate: String
    /// A preset ID (`subhan` … `salawat`), or `c:` and a saved phrase.
    public var phraseKey: String
    public var count: Int
    public var firstUse: Int
    public var updatedAt: Date

    public init(localDate: String, phraseKey: String, count: Int, firstUse: Int, updatedAt: Date) {
        self.localDate = localDate
        self.phraseKey = phraseKey
        self.count = count
        self.firstUse = firstUse
        self.updatedAt = updatedAt
    }
}

public struct TasbihRepository: Sendable {
    let writer: any DatabaseWriter

    /// The phrases counted on `localDate`, in first-use order (`tasbihDayCounts`).
    public func counts(on localDate: String) throws -> [TasbihCount] {
        try writer.read { db in
            try TasbihCount.filter(Column("local_date") == localDate).order(Column("first_use")).fetchAll(db)
        }
    }

    /// `setTasbihCount`: the phrase's count on `localDate`. A phrase counted for the first time that day goes last in
    /// the day's order; a count of zero deletes its row.
    public func setCount(_ count: Int, for phraseKey: String, on localDate: String, at now: Date = Date()) throws {
        try writer.write { db in
            let key: [String: any DatabaseValueConvertible] = ["local_date": localDate, "phrase_key": phraseKey]
            guard count > 0 else {
                _ = try TasbihCount.deleteOne(db, key: key)
                return
            }
            if var row = try TasbihCount.fetchOne(db, key: key) {
                row.count = count
                row.updatedAt = now
                try row.update(db)
            } else {
                let last = try Int.fetchOne(db, sql: "SELECT MAX(first_use) FROM tasbih_counts WHERE local_date = ?",
                                            arguments: [localDate]) ?? 0
                try TasbihCount(localDate: localDate, phraseKey: phraseKey, count: count, firstUse: last + 1,
                                updatedAt: now).insert(db)
            }
        }
    }

    /// Every phrase key with a count on any date, in code-unit order. An array, not a set: Swift equates canonically
    /// equivalent strings, and two keys that differ only in the order of their tashkeel are two rows.
    public func phraseKeys() throws -> [String] {
        try writer.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT phrase_key FROM tasbih_counts ORDER BY phrase_key")
        }
    }

    /// The saved phrases (`custom`) and the phrase counted (`selected`), in one transaction, as the PWA stores them in
    /// one value. The counts of `adopting` move to `selected` on every date: a phrase saved again in another spelling
    /// takes the counts its earlier spelling kept (`canonicalTasbihDays`). A date that already counts `selected`
    /// sums the two, up to ``TasbihCount/maxCount``, and keeps the earlier first use. Keys compare as code units, as
    /// the table's primary key does.
    public func savePhrases(_ custom: [String], selected: String, adopting keys: [String] = [],
                            at now: Date = Date()) throws {
        let customJSON = try SettingsRepository.json(custom)
        let selectedJSON = try SettingsRepository.json(selected)
        try writer.write { db in
            try Setting(key: SettingKey<[String]>.tasbihCustomPhrases.name, valueJson: customJSON, origin: .native,
                        updatedAt: now).upsert(db)
            try Setting(key: SettingKey<String>.tasbihSelected.name, valueJson: selectedJSON, origin: .native,
                        updatedAt: now).upsert(db)
            for key in keys where !key.utf8.elementsEqual(selected.utf8) {
                for row in try TasbihCount.filter(Column("phrase_key") == key).fetchAll(db) {
                    try row.delete(db)
                    let target: [String: any DatabaseValueConvertible] = ["local_date": row.localDate,
                                                                          "phrase_key": selected]
                    if var existing = try TasbihCount.fetchOne(db, key: target) {
                        existing.count = min(existing.count + row.count, TasbihCount.maxCount)
                        existing.firstUse = min(existing.firstUse, row.firstUse)
                        existing.updatedAt = max(existing.updatedAt, row.updatedAt)
                        try existing.update(db)
                    } else {
                        var moved = row
                        moved.phraseKey = selected
                        try moved.insert(db)
                    }
                }
            }
        }
    }

    /// How many recorded days `removal` covers, as the athkar PWA's reset confirmations count
    /// `tasbihState.history`: the distinct dates before `today` with a count. Today's counts are today's progress.
    public func recordedDayCount(_ removal: HistoryRemoval, before today: String) throws -> Int {
        try writer.read { db in
            try TasbihCount.select(Column("local_date"), as: String.self)
                .filter(removal.covers() && Column("local_date") < today)
                .fetchSet(db)
                .count
        }
    }

    /// The athkar PWA's scoped reset in one transaction: no phrase is counted on `localDate` any more
    /// (`resetTasbihProgress`), and the counts `removal` covers are deleted (`deleteTasbihHistory`). Without a removal,
    /// earlier days keep their counts. The saved phrases, the phrase counted and the target are preferences and stay.
    public func reset(on localDate: String, removing removal: HistoryRemoval? = nil) throws {
        try writer.write { db in
            try TasbihCount.filter(Column("local_date") == localDate).deleteAll(db)
            if let removal {
                try TasbihCount.filter(removal.covers()).deleteAll(db)
            }
        }
    }
}
