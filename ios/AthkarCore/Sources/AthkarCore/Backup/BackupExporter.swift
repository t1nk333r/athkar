import Foundation
import GRDB

/// Builds the envelope a PWA would export from what the database holds, so that exporting right after importing
/// a PWA file reproduces it (NATIVE_APP_PLAN.md §6.4 round trip; exceptions in spec/schema.md "Export").
public struct BackupExporter: Sendable {
    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// - Parameters:
    ///   - app: which PWA's sections to write: athkar → `adhkar`, `reminders`, `preferences`;
    ///     ruqyah → `ruqyah`, `preferences`.
    ///   - today: the local date of the export (`YYYY-MM-DD` in `timeZone`).
    ///   - includeLocation: the per-export opt-in for `reminders.location`.
    public func export(app: BackupApp, today: String, timeZone: String, exportedAt: Date = Date(),
                       includeLocation: Bool = false) throws -> BackupEnvelope {
        let envelope = try database.writer.read { db in
            var envelope = BackupEnvelope(meta: .init(app: app, exportedAt: exportedAt, timeZone: timeZone))
            switch app {
            case .athkarPWA:
                envelope.adhkar = try Self.adhkar(in: db, today: today)
                envelope.reminders = try Self.reminders(in: db, includeLocation: includeLocation)
                envelope.preferences = try Self.preferences(in: db, includeLongOrder: true)
            case .ruqyahPWA:
                envelope.ruqyah = try Self.ruqyah(in: db, today: today)
                envelope.preferences = try Self.preferences(in: db, includeLongOrder: false)
            }
            return envelope
        }
        try envelope.validate()
        return envelope
    }

    private static func adhkar(in db: Database, today date: String) throws -> BackupEnvelope.Adhkar {
        var today = BackupEnvelope.Adhkar.Today(
            date: date,
            progress: .init(morning: [:], evening: [:]),
            targets: .init(morning: [:], evening: [:]),
            completedAt: .init(morning: nil, evening: nil),
            manualCompletion: .init(morning: false, evening: false))
        for period in Period.allCases {
            let session = try AdhkarRepository.session(in: db, on: date, period: period)
            today.progress[period] = session.progress.mapValues(Double.init)
            today.targets[period] = session.targets.mapValues(Double.init)
            today.completedAt[period] = session.completion?.completedAt
            today.manualCompletion[period] = session.completion?.completionOrigin.isManualCompletion ?? false
        }

        // The PWA keeps one entry per day it rolled over, newest first, at most 7.
        let history = try AdhkarRepository.recordedDates(in: db, before: date, limit: 7).map { day in
            let rows = try AdhkarDay.filter(Column("local_date") == day).fetchAll(db)
            let morning = rows.first { $0.period == .morning }
            let evening = rows.first { $0.period == .evening }
            return BackupEnvelope.Adhkar.HistoryEntry(
                date: day, morning: morning != nil, evening: evening != nil,
                morningAt: morning?.completedAt, eveningAt: evening?.completedAt)
        }
        return BackupEnvelope.Adhkar(today: today, history: history)
    }

    private static func ruqyah(in db: Database, today date: String) throws -> BackupEnvelope.Ruqyah {
        let days = try RuqyahDay
            .filter(Column("local_date") <= date)
            .order(Column("local_date").desc)
            .limit(365)
            .fetchAll(db)
        return BackupEnvelope.Ruqyah(
            today: .init(date: date, counts: try RuqyahRepository.counts(in: db, on: date)),
            history: Dictionary(uniqueKeysWithValues: days.map { ($0.localDate, .init(completedAt: $0.completedAt)) }))
    }

    private static func reminders(in db: Database, includeLocation: Bool) throws -> BackupEnvelope.Reminders {
        func enabled(_ period: Period) throws -> BackupEnvelope.Reminders.Toggle {
            .init(enabled: try ReminderRule.fetchOne(db, key: ReminderRule.adhkarId(period))?.enabled ?? false)
        }
        func lastShown(_ period: Period) throws -> String? {
            try ReminderState.fetchOne(db, key: ReminderRule.adhkarId(period))?.lastShownLocalDate
        }
        let location = includeLocation ? try LocationProfile.fetchOne(db) : nil
        // A method the PWA does not offer exports as `mwl`, which is what the PWA's loader reads it as.
        let method = try setting(.calculationMethod, in: db)
        return BackupEnvelope.Reminders(
            morning: try enabled(.morning),
            evening: try enabled(.evening),
            calculationMethod: method.isPWAMethod ? method : .mwl,
            asrSchool: try setting(.asrSchool, in: db),
            lastShown: .init(morning: try lastShown(.morning), evening: try lastShown(.evening)),
            location: location.map {
                .init(latitude: $0.latitude, longitude: $0.longitude, updatedAt: $0.updatedAt)
            })
    }

    private static func preferences(in db: Database, includeLongOrder: Bool) throws -> BackupEnvelope.Preferences {
        BackupEnvelope.Preferences(
            theme: try setting(.theme, in: db),
            textSize: try setting(.textSize, in: db),
            lineSpacing: try setting(.lineSpacing, in: db),
            haptics: try setting(.haptics, in: db),
            longOrder: includeLongOrder ? try setting(.longOrder, in: db) : nil,
            longOrderPromptAnswered: includeLongOrder ? try setting(.longOrderPromptAnswered, in: db) : nil)
    }

    private static func setting<Value>(_ key: SettingKey<Value>, in db: Database) throws -> Value {
        try SettingsRepository.value(in: db, for: key) ?? key.defaultValue
    }
}
