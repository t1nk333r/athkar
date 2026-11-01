import Foundation
import GRDB

/// The prayer tracker's records (`prayer_records`, spec/schema.md v5). Every command runs ``PrayerTracker`` on the
/// stored record inside one write transaction, so a command sent twice stores one record.
public struct PrayerRecordRepository: Sendable {
    let writer: any DatabaseWriter

    /// The records of `date`, in prayer order.
    public func records(on date: String) throws -> [PrayerRecord] {
        try records(from: date, through: date)
    }

    /// Records with `from <= calculation_date <= through`, by date and then in prayer order.
    public func records(from: String, through: String) throws -> [PrayerRecord] {
        try writer.read { db in
            try PrayerRecord
                .filter(Column("calculation_date") >= from && Column("calculation_date") <= through)
                .fetchAll(db)
                .sorted(by: Self.order)
        }
    }

    /// Applies `command` to `occurrence`'s stored record and writes the result. Throws ``PrayerCommandRefusal`` for a
    /// refused command, which writes nothing.
    @discardableResult
    public func apply(_ command: PrayerCommand, to occurrence: PrayerOccurrence,
                      context: PrayerCommandContext) throws -> PrayerCommandOutcome {
        try writer.write { db in
            let existing = try PrayerRecord.fetchOne(db, key: Self.key(occurrence))
            let outcome = try PrayerTracker.apply(command, to: occurrence, existing: existing, context: context)
            if case let .changed(record) = outcome { try record.upsert(db) }
            return outcome
        }
    }

    /// `clearDay`: every record of `date` back to `unrecorded`, in one transaction. Returns whether any changed.
    @discardableResult
    public func clearDay(_ date: String, context: PrayerCommandContext) throws -> Bool {
        try writer.write { db in
            let records = try PrayerRecord.filter(Column("calculation_date") == date).fetchAll(db)
            let changed = try PrayerTracker.clearDay(date, records: records, context: context)
            for record in changed { try record.update(db) }
            return !changed.isEmpty
        }
    }

    /// The calendar summary of `month` (`YYYY-MM`): this table with `adhkar_days` and `ruqyah_days`, in one read.
    public func month(_ month: String, today: String) throws -> PrayerCalendarMonth? {
        guard let dates = LocalDate.days(inMonth: month), let first = dates.first, let last = dates.last else {
            return nil
        }
        return try writer.read { db in
            let marks = try PrayerRecord
                .filter(Column("calculation_date") >= first && Column("calculation_date") <= last)
                .fetchAll(db)
                .map { PrayerStateMark(date: $0.calculationDate, prayer: $0.prayerKey, state: $0.state) }
            let range = Column("local_date") >= first && Column("local_date") <= last
            let adhkar = try AdhkarDay.filter(range).fetchAll(db)
            let ruqyah = try RuqyahDay.filter(range).fetchAll(db)
            return PrayerCalendar.month(month, today: today, marks: marks,
                                        morning: Set(adhkar.filter { $0.period == .morning }.map(\.localDate)),
                                        evening: Set(adhkar.filter { $0.period == .evening }.map(\.localDate)),
                                        ruqyah: Set(ruqyah.map(\.localDate)))
        }
    }

    /// Deletes the records `removal` covers: the only way records are deleted (a future delete-all). No section's
    /// scoped reset calls it; each reset covers its own section, as the others do.
    public func delete(_ removal: HistoryRemoval) throws {
        try writer.write { db in
            _ = try PrayerRecord.filter(removal.covers(Column("calculation_date"))).deleteAll(db)
        }
    }

    static func key(_ occurrence: PrayerOccurrence) -> [String: (any DatabaseValueConvertible)?] {
        ["calculation_date": occurrence.date, "prayer_key": occurrence.prayer]
    }

    static func order(_ left: PrayerRecord, _ right: PrayerRecord) -> Bool {
        if left.calculationDate != right.calculationDate { return left.calculationDate < right.calculationDate }
        let prayers = ObligatoryPrayer.allCases
        return prayers.firstIndex(of: left.prayerKey)! < prayers.firstIndex(of: right.prayerKey)!
    }
}
