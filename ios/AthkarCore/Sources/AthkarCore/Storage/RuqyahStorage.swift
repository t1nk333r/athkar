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

public struct RuqyahRepository: Sendable {
    let writer: any DatabaseWriter

    /// Segment ID → count for one local date (the PWA's `ruqyah-daily-v1.counts`).
    public func counts(on localDate: String) throws -> [String: Int] {
        try writer.read { try Self.counts(in: $0, on: localDate) }
    }

    /// Stores one segment's count. With `completingDayAt`, also records `localDate` as complete unless it already
    /// is (the ruqyah PWA's `recordToday` keeps the first completion time), in the same transaction.
    public func setCount(_ count: Int, for segmentId: String, on localDate: String,
                         completingDayAt completedAt: Date? = nil, at now: Date = Date()) throws {
        try writer.write { db in
            try RuqyahSegmentProgress(localDate: localDate, segmentId: segmentId, count: count, updatedAt: now)
                .upsert(db)
            if let completedAt, try RuqyahDay.fetchOne(db, key: localDate) == nil {
                try RuqyahDay(localDate: localDate, completedAt: completedAt, completionOrigin: .counters).insert(db)
            }
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

    /// The ruqyah PWA's scoped reset in one transaction: every stored segment count of `localDate` becomes 0
    /// (`resetDayProgress`), and the completed days `removal` covers are deleted (`resetWeek`,
    /// `resetEverything`). Without a removal, a completed `localDate` stays complete: resetting the day keeps
    /// its history, as in the PWA.
    public func resetCounts(on localDate: String, removing removal: HistoryRemoval? = nil,
                            at now: Date = Date()) throws {
        try writer.write { db in
            try db.execute(sql: """
                UPDATE ruqyah_segment_progress SET count = 0, updated_at = ? WHERE local_date = ? AND count <> 0
                """, arguments: [ISOInstant.format(now), localDate])
            if let removal {
                try RuqyahDay.filter(removal.covers()).deleteAll(db)
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
