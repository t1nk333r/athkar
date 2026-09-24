import Foundation
import GRDB

/// How a day's completion came about (`adhkar_days.completion_origin`, `ruqyah_days.completion_origin`).
public enum CompletionOrigin: String, Codable, Sendable, DatabaseValueConvertible {
    /// Every counted item reached its target in this app.
    case counters
    /// Marked complete by the user (the PWA's `manualCompletion`). Adhkar only.
    case manual
    /// Came from a backup file; the file does not say how.
    case imported = "import"
}

/// One row per (local date, period) whose adhkar session is complete; no row means not complete.
public struct AdhkarDay: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "adhkar_days"

    public var localDate: String
    public var period: Period
    /// `nil` when the completion time is unknown (a PWA history entry or manual completion without one).
    public var completedAt: Date?
    public var completionOrigin: CompletionOrigin

    public init(localDate: String, period: Period, completedAt: Date?, completionOrigin: CompletionOrigin) {
        self.localDate = localDate
        self.period = period
        self.completedAt = completedAt
        self.completionOrigin = completionOrigin
    }
}

/// Tap count and chosen target for one item on one (local date, period). Raw values: counts are neither
/// floored nor clamped here; readers clamp to the effective target as the PWA's `countForState` does.
public struct AdhkarItemProgress: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "adhkar_item_progress"

    public var localDate: String
    public var period: Period
    public var itemId: String
    /// `nil` when only a target was chosen (the item has no entry in the PWA's `progress`); reads as 0.
    public var count: Int?
    /// `nil` means the item's default target.
    public var target: Int?
    public var updatedAt: Date

    public init(localDate: String, period: Period, itemId: String, count: Int?, target: Int?, updatedAt: Date) {
        self.localDate = localDate
        self.period = period
        self.itemId = itemId
        self.count = count
        self.target = target
        self.updatedAt = updatedAt
    }
}

/// Everything stored for one (local date, period): the shape of the PWA's per-period state.
public struct AdhkarSession: Equatable, Sendable {
    public var localDate: String
    public var period: Period
    /// Item ID → raw tap count (the PWA's `progress[period]`).
    public var progress: [String: Int]
    /// Item ID → chosen target (the PWA's `targets[period]`).
    public var targets: [String: Int]
    public var completion: AdhkarDay?

    public init(localDate: String, period: Period, progress: [String: Int] = [:], targets: [String: Int] = [:],
                completion: AdhkarDay? = nil) {
        self.localDate = localDate
        self.period = period
        self.progress = progress
        self.targets = targets
        self.completion = completion
    }

    /// Nothing done: no completion and no positive count. Chosen targets alone do not count (spec/schema.md).
    public var isEmpty: Bool { completion == nil && !progress.values.contains { $0 > 0 } }

    func itemRows(updatedAt: Date) -> [AdhkarItemProgress] {
        Set(progress.keys).union(targets.keys).sorted().map { itemId in
            AdhkarItemProgress(localDate: localDate, period: period, itemId: itemId,
                               count: progress[itemId], target: targets[itemId], updatedAt: updatedAt)
        }
    }
}

public struct AdhkarRepository: Sendable {
    let writer: any DatabaseWriter

    public func session(on localDate: String, period: Period) throws -> AdhkarSession {
        try writer.read { try Self.session(in: $0, on: localDate, period: period) }
    }

    /// Completed (date, period) rows with `from <= local_date <= through`, oldest date first, morning before evening.
    public func days(from: String, through: String) throws -> [AdhkarDay] {
        try writer.read { db in
            try AdhkarDay
                .filter(Column("local_date") >= from && Column("local_date") <= through)
                .order(Column("local_date"), SQL("CASE period WHEN 'morning' THEN 0 ELSE 1 END").sqlExpression)
                .fetchAll(db)
        }
    }

    public func setCount(_ count: Int, for itemId: String, on localDate: String, period: Period,
                         at now: Date = Date()) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO adhkar_item_progress (local_date, period, item_id, count, target, updated_at)
                VALUES (?, ?, ?, ?, NULL, ?)
                ON CONFLICT (local_date, period, item_id)
                DO UPDATE SET count = excluded.count, updated_at = excluded.updated_at
                """, arguments: [localDate, period, itemId, count, ISOInstant.format(now)])
        }
    }

    /// Chooses a target for the item, or clears it (`nil`: back to the item's default).
    public func setTarget(_ target: Int?, for itemId: String, on localDate: String, period: Period,
                          at now: Date = Date()) throws {
        try writer.write { db in
            guard let target else {
                try db.execute(sql: """
                    DELETE FROM adhkar_item_progress
                    WHERE local_date = ? AND period = ? AND item_id = ? AND count IS NULL
                    """, arguments: [localDate, period, itemId])
                try db.execute(sql: """
                    UPDATE adhkar_item_progress SET target = NULL, updated_at = ?
                    WHERE local_date = ? AND period = ? AND item_id = ?
                    """, arguments: [ISOInstant.format(now), localDate, period, itemId])
                return
            }
            try db.execute(sql: """
                INSERT INTO adhkar_item_progress (local_date, period, item_id, count, target, updated_at)
                VALUES (?, ?, ?, NULL, ?, ?)
                ON CONFLICT (local_date, period, item_id)
                DO UPDATE SET target = excluded.target, updated_at = excluded.updated_at
                """, arguments: [localDate, period, itemId, target, ISOInstant.format(now)])
        }
    }

    public func markComplete(on localDate: String, period: Period, origin: CompletionOrigin,
                             completedAt: Date?) throws {
        try writer.write { db in
            try AdhkarDay(localDate: localDate, period: period, completedAt: completedAt, completionOrigin: origin)
                .upsert(db)
        }
    }

    public func clearCompletion(on localDate: String, period: Period) throws {
        try writer.write { db in
            _ = try AdhkarDay.deleteOne(db, key: ["local_date": localDate, "period": period])
        }
    }

    /// The PWA's `resetDayProgress` for one date: counts and completions go, chosen targets stay.
    public func resetProgress(on localDate: String, at now: Date = Date()) throws {
        try writer.write { db in
            try db.execute(sql: """
                DELETE FROM adhkar_item_progress WHERE local_date = ? AND target IS NULL;
                UPDATE adhkar_item_progress SET count = NULL, updated_at = ? WHERE local_date = ? AND count IS NOT NULL;
                DELETE FROM adhkar_days WHERE local_date = ?;
                """, arguments: [localDate, ISOInstant.format(now), localDate, localDate])
        }
    }

    /// Deletes every adhkar record (counts, targets, completions) with `from <= local_date <= through`.
    public func deleteRecords(from: String, through: String) throws {
        try writer.write { db in
            let range = Column("local_date") >= from && Column("local_date") <= through
            try AdhkarItemProgress.filter(range).deleteAll(db)
            try AdhkarDay.filter(range).deleteAll(db)
        }
    }

    /// Local dates before `date` that `removal` covers and on which at least one period is complete: the number of
    /// history days the PWA's `resetWeek` / `resetEverything` confirmation names.
    public func completedDayCount(_ removal: HistoryRemoval, before date: String) throws -> Int {
        try writer.read { db in
            try AdhkarDay
                .filter(removal.covers() && Column("local_date") < date)
                .select(Column("local_date"))
                .distinct()
                .fetchCount(db)
        }
    }

    static func session(in db: Database, on localDate: String, period: Period) throws -> AdhkarSession {
        var session = AdhkarSession(localDate: localDate, period: period)
        let rows = try AdhkarItemProgress
            .filter(Column("local_date") == localDate && Column("period") == period)
            .fetchAll(db)
        for row in rows {
            session.progress[row.itemId] = row.count
            session.targets[row.itemId] = row.target
        }
        session.completion = try AdhkarDay.fetchOne(db, key: ["local_date": localDate, "period": period])
        return session
    }

    /// Replaces everything stored for the session's (date, period) with `session`, stamping item rows.
    static func replace(in db: Database, with session: AdhkarSession, updatedAt: Date) throws {
        let key = Column("local_date") == session.localDate && Column("period") == session.period
        try AdhkarItemProgress.filter(key).deleteAll(db)
        try AdhkarDay.filter(key).deleteAll(db)
        for row in session.itemRows(updatedAt: updatedAt) {
            try row.insert(db)
        }
        try session.completion?.insert(db)
    }

    /// Local dates before `date` that have any adhkar row, newest first.
    static func recordedDates(in db: Database, before date: String, limit: Int) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT local_date FROM adhkar_days WHERE local_date < ?
            UNION
            SELECT local_date FROM adhkar_item_progress WHERE local_date < ?
            ORDER BY local_date DESC LIMIT ?
            """, arguments: [date, date, limit])
    }
}
