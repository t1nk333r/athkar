import Foundation
import GRDB

/// One row per local date on which every ruqyah segment was completed.
public struct RuqyahDay: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "ruqyah_days"

    public var localDate: String
    public var completedAt: Date
    /// `.counters` or `.imported`; ruqyah has no manual completion.
    public var completionOrigin: CompletionOrigin

    public init(localDate: String, completedAt: Date, completionOrigin: CompletionOrigin) {
        self.localDate = localDate
        self.completedAt = completedAt
        self.completionOrigin = completionOrigin
    }
}

/// Repetitions read of one segment on one local date, bounded by the segment's `repeat` in the pack.
public struct RuqyahSegmentProgress: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "ruqyah_segment_progress"

    public var localDate: String
    public var segmentId: String
    public var count: Int
    public var updatedAt: Date

    public init(localDate: String, segmentId: String, count: Int, updatedAt: Date) {
        self.localDate = localDate
        self.segmentId = segmentId
        self.count = count
        self.updatedAt = updatedAt
    }
}

/// One sura of the ruqyah completed on one local date (the ruqyah PWA's `ruqyah-suwar-v1`: `completedAt` for today,
/// `history` for earlier days). The row keeps when the sura's segments first all reached their repeats that day; a
/// segment reset or a scoped reset removes it, as the PWA's `applyOp` clears `completedAt`.
public struct RuqyahSuraDay: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "ruqyah_sura_days"

    public var localDate: String
    /// The segment-ID prefix: `qaf`, `jinn`, `takwir`, `kafirun`, `nas`.
    public var suraId: String
    public var completedAt: Date

    public init(localDate: String, suraId: String, completedAt: Date) {
        self.localDate = localDate
        self.suraId = suraId
        self.completedAt = completedAt
    }
}

public struct RuqyahRepository: Sendable {
    let writer: any DatabaseWriter

    /// Segment ID → count for one local date (the PWA's `ruqyah-daily-v1.counts`).
    public func counts(on localDate: String) throws -> [String: Int] {
        try writer.read { try Self.counts(in: $0, on: localDate) }
    }

    /// Stores one segment's count, in one transaction with what it completes (the ruqyah PWA's `applyOp`). With
    /// `completingSura`, also records that sura complete at `now`; with `completingDayAt`, records `localDate` as
    /// complete. Each is recorded only when it is not already: the first completion time is kept.
    public func setCount(_ count: Int, for segmentId: String, on localDate: String,
                         completingSura suraId: String? = nil, completingDayAt completedAt: Date? = nil,
                         at now: Date = Date()) throws {
        try writer.write { db in
            try RuqyahSegmentProgress(localDate: localDate, segmentId: segmentId, count: count, updatedAt: now)
                .upsert(db)
            if let suraId, try RuqyahSuraDay.fetchOne(db, key: ["local_date": localDate, "sura_id": suraId]) == nil {
                try RuqyahSuraDay(localDate: localDate, suraId: suraId, completedAt: now).insert(db)
            }
            if let completedAt, try RuqyahDay.fetchOne(db, key: localDate) == nil {
                try RuqyahDay(localDate: localDate, completedAt: completedAt, completionOrigin: .counters).insert(db)
            }
        }
    }

    /// `resetSegment`: one segment's count back to 0 and its sura no longer complete on `localDate`, in one
    /// transaction. The day's record stays, as every reset keeps it.
    public func resetSegment(_ segmentId: String, of suraId: String, on localDate: String,
                             at now: Date = Date()) throws {
        try writer.write { db in
            try RuqyahSegmentProgress(localDate: localDate, segmentId: segmentId, count: 0, updatedAt: now).upsert(db)
            _ = try RuqyahSuraDay.deleteOne(db, key: ["local_date": localDate, "sura_id": suraId])
        }
    }

    /// Sura ID → when it was completed on `localDate` (`ruqyah-suwar-v1.completedAt`).
    public func suraDays(on localDate: String) throws -> [String: Date] {
        try writer.read { db in
            let rows = try RuqyahSuraDay.filter(Column("local_date") == localDate).fetchAll(db)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.suraId, $0.completedAt) })
        }
    }

    /// The completed day `localDate`, or `nil` when it is not complete.
    public func day(on localDate: String) throws -> RuqyahDay? {
        try writer.read { try RuqyahDay.fetchOne($0, key: localDate) }
    }

    /// How many completed days `removal` covers.
    public func dayCount(_ removal: HistoryRemoval) throws -> Int {
        try writer.read { try RuqyahDay.filter(removal.covers()).fetchCount($0) }
    }

    /// How many recorded days `removal` covers, as the ruqyah PWA's reset confirmations count them
    /// (`historyDates`): completed days, and days before `today` with a completed sura.
    public func recordedDayCount(_ removal: HistoryRemoval, before today: String) throws -> Int {
        try writer.read { db in
            let days = try RuqyahDay.select(Column("local_date"), as: String.self)
                .filter(removal.covers())
                .fetchSet(db)
            let suras = try RuqyahSuraDay.select(Column("local_date"), as: String.self)
                .filter(removal.covers() && Column("local_date") < today)
                .fetchSet(db)
            return days.union(suras).count
        }
    }

    /// The ruqyah PWA's scoped reset in one transaction: every stored segment count of `localDate` becomes 0 and
    /// none of its suras is complete any more (`resetDayProgress`, `clearDay`), and the completed days and suras
    /// `removal` covers are deleted (`resetWeek`, `resetEverything`). Without a removal, a completed `localDate`
    /// stays complete: resetting the day keeps its history, as in the PWA.
    public func resetCounts(on localDate: String, removing removal: HistoryRemoval? = nil,
                            at now: Date = Date()) throws {
        try writer.write { db in
            try db.execute(sql: """
                UPDATE ruqyah_segment_progress SET count = 0, updated_at = ? WHERE local_date = ? AND count <> 0
                """, arguments: [ISOInstant.format(now), localDate])
            try RuqyahSuraDay.filter(Column("local_date") == localDate).deleteAll(db)
            if let removal {
                try RuqyahDay.filter(removal.covers()).deleteAll(db)
                try RuqyahSuraDay.filter(removal.covers()).deleteAll(db)
            }
        }
    }

    /// Completed days with `from <= local_date <= through`, oldest first.
    public func days(from: String, through: String) throws -> [RuqyahDay] {
        try writer.read { db in
            try RuqyahDay
                .filter(Column("local_date") >= from && Column("local_date") <= through)
                .order(Column("local_date"))
                .fetchAll(db)
        }
    }

    public func markComplete(on localDate: String, completedAt: Date, origin: CompletionOrigin = .counters) throws {
        try writer.write { db in
            try RuqyahDay(localDate: localDate, completedAt: completedAt, completionOrigin: origin).upsert(db)
        }
    }

    public func clearCompletion(on localDate: String) throws {
        try writer.write { db in _ = try RuqyahDay.deleteOne(db, key: localDate) }
    }

    static func counts(in db: Database, on localDate: String) throws -> [String: Int] {
        let rows = try RuqyahSegmentProgress.filter(Column("local_date") == localDate).fetchAll(db)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.segmentId, $0.count) })
    }
}
