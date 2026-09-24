import Foundation
import GRDB

/// Bridges the database and the session rules: builds the PWA-shaped `SessionState` for a local date from the
/// adhkar tables, and writes a state back (spec/schema.md "Session state bridge").
///
/// - `load(date:)`: that date's `adhkar_item_progress` rows as `progress`/`targets`; `completedAt` and
///   `manualCompletion` from its `adhkar_days` rows (manual iff origin `manual`); `history` = the newest
///   ``SessionState/historyLimit`` earlier dates that have an `adhkar_days` row.
/// - `save(_:)`: makes the rows for `state.date` match the state, in one transaction. History is not written:
///   it is a view of earlier days' rows, which were written when those days were live.
public struct AdhkarSessionStore: Sendable {
    let database: AppDatabase
    let collections: SessionCollections

    public init(database: AppDatabase, collections: SessionCollections) {
        self.database = database
        self.collections = collections
    }

    public func load(date: String) throws -> SessionState {
        try database.reader.read { db in
            var state = SessionState.empty(date: date)
            for period in Period.allCases {
                let session = try AdhkarRepository.session(in: db, on: date, period: period)
                state.progress[period] = .object(session.progress.mapValues { .number(Double($0)) })
                state.targets[period] = .object(session.targets.mapValues { .number(Double($0)) })
                state.completedAt[period] = session.completion?.completedAt.map(ISOInstant.format)
                state.manualCompletion[period] = session.completion?.completionOrigin == .manual
            }
            let dates = try String.fetchAll(db, sql: """
                SELECT DISTINCT local_date FROM adhkar_days WHERE local_date < ? ORDER BY local_date DESC LIMIT ?
                """, arguments: [date, SessionState.historyLimit])
            state.history = try dates.map { day in
                let rows = try AdhkarDay.filter(Column("local_date") == day).fetchAll(db)
                let morning = rows.first { $0.period == .morning }
                let evening = rows.first { $0.period == .evening }
                return SessionState.HistoryEntry(
                    date: day, morning: morning != nil, evening: evening != nil,
                    morningAt: morning?.completedAt.map(ISOInstant.format),
                    eveningAt: evening?.completedAt.map(ISOInstant.format))
            }
            return state
        }
    }

    /// Writes `state.date`'s counters, targets and completion. Rows whose values are unchanged keep their
    /// `updated_at`; changed rows get `now`.
    ///
    /// Stored values are reduced to what the rules read from them: a counter to `floor(Number(value))` (dropped
    /// when that is not a finite number ≥ 0), a target to `Number(value)` if it is an integer ≥ 0 (otherwise
    /// dropped: it can never match a target option). A period has an `adhkar_days` row iff
    /// `isComplete(period)`; origin `manual` when `manualCompletion`, else the existing non-manual origin or
    /// `counters`; `completed_at` is `completedAt` when it is an ISO-8601 UTC instant, else null.
    public func save(_ state: SessionState, at now: Date = Date()) throws {
        try database.writer.write { db in try write(state, in: db, now: now) }
    }

    /// The PWA's `resetWeek` / `resetEverything`: deletes every adhkar record (counts, targets, completions) that
    /// `removal` covers, then writes `state` (already reset by ``SessionState/resetWeek(now:timeZone:)`` or
    /// ``SessionState/resetEverything()``) as ``save(_:at:)`` does, in one transaction. A crash therefore never
    /// leaves history deleted while today's counters survive, or the reverse.
    public func save(_ state: SessionState, removing removal: HistoryRemoval, at now: Date = Date()) throws {
        try database.writer.write { db in
            try AdhkarItemProgress.filter(removal.covers()).deleteAll(db)
            try AdhkarDay.filter(removal.covers()).deleteAll(db)
            try write(state, in: db, now: now)
        }
    }

    private func write(_ state: SessionState, in db: Database, now: Date) throws {
        for period in Period.allCases {
            try saveItems(of: state, period: period, in: db, now: now)
            try saveCompletion(of: state, period: period, in: db)
        }
    }

    private func saveItems(of state: SessionState, period: Period, in db: Database, now: Date) throws {
        let progress = Self.entries(state.progress[period]).compactMapValues(Self.storedCount)
        let targets = Self.entries(state.targets[period]).compactMapValues(Self.storedTarget)
        let existing = try AdhkarItemProgress
            .filter(Column("local_date") == state.date && Column("period") == period)
            .fetchAll(db)
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.itemId, $0) })
        let wanted = Set(progress.keys).union(targets.keys)

        for row in existing where !wanted.contains(row.itemId) {
            _ = try row.delete(db)
        }
        for itemId in wanted.sorted() {
            let count = progress[itemId]
            let target = targets[itemId]
            if let row = existingById[itemId], row.count == count, row.target == target { continue }
            try AdhkarItemProgress(localDate: state.date, period: period, itemId: itemId, count: count,
                                   target: target, updatedAt: now).upsert(db)
        }
    }

    private func saveCompletion(of state: SessionState, period: Period, in db: Database) throws {
        let key: [String: (any DatabaseValueConvertible)?] = ["local_date": state.date, "period": period]
        let existing = try AdhkarDay.fetchOne(db, key: key)
        guard state.isComplete(period, in: collections) else {
            if existing != nil { _ = try AdhkarDay.deleteOne(db, key: key) }
            return
        }
        let origin: CompletionOrigin = state.isManuallyComplete(period)
            ? .manual
            : existing.map(\.completionOrigin).flatMap { $0 == .manual ? nil : $0 } ?? .counters
        let row = AdhkarDay(localDate: state.date, period: period,
                            completedAt: state.completedAt[period].flatMap(ISOInstant.parse), completionOrigin: origin)
        if row != existing { try row.upsert(db) }
    }

    /// Item ID → stored value. An array in place of the PWA's `{itemId: value}` object has only index keys, which
    /// no content item ID matches, so the rules read nothing from it; it is stored as no entries.
    private static func entries(_ values: SessionState.ItemValues) -> [String: SessionState.StoredValue] {
        switch values {
        case let .object(members): members
        case .array: [:]
        }
    }

    /// `countForState` before the clamp: `Number(value)` floored; `nil` when not a finite number ≥ 0.
    private static func storedCount(_ value: SessionState.StoredValue) -> Int? {
        let number = value.numberValue
        guard number.isFinite, number >= 0, number <= BackupEnvelope.maxSafeInteger else { return nil }
        return Int(number.rounded(.down))
    }

    /// `targetForState` compares `Number(value)` with integer options, so only an integer ≥ 0 can ever count.
    private static func storedTarget(_ value: SessionState.StoredValue) -> Int? {
        let number = value.numberValue
        guard number >= 0, number <= BackupEnvelope.maxSafeInteger else { return nil }
        return Int(exactly: number)
    }
}
