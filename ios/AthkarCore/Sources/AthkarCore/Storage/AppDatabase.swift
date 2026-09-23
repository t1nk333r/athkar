import Foundation
import GRDB

/// The app's SQLite database: GRDB, forward-only numbered migrations, schema in `spec/schema.md`.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    /// Opens `writer` and applies every pending migration.
    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// On-disk database in WAL mode (`DatabasePool` always uses WAL).
    public static func onDisk(at url: URL) throws -> AppDatabase {
        try AppDatabase(DatabasePool(path: url.path, configuration: configuration))
    }

    /// Private in-memory database, for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: configuration))
    }

    public var reader: any DatabaseReader { writer }

    public var adhkar: AdhkarRepository { AdhkarRepository(writer: writer) }
    public var ruqyah: RuqyahRepository { RuqyahRepository(writer: writer) }
    public var reminders: ReminderRepository { ReminderRepository(writer: writer) }
    public var settings: SettingsRepository { SettingsRepository(writer: writer) }
    public var location: LocationRepository { LocationRepository(writer: writer) }
    public var contentInstalls: ContentInstallRepository { ContentInstallRepository(writer: writer) }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return configuration
    }

    /// Migration identifiers are `v<N>`, applied in order, never edited once shipped (spec/schema.md).
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in try db.execute(sql: Schema.v1) }
        return migrator
    }
}

private enum Schema {
    static let localDate = "GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'"
    static let instant = "GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'"
    static let period = "IN ('morning', 'evening')"

    static let v1 = """
        CREATE TABLE settings (
            key TEXT NOT NULL PRIMARY KEY,
            value_json TEXT NOT NULL,
            origin TEXT NOT NULL CHECK (origin IN ('native', 'athkar-pwa', 'ruqyah-pwa')),
            updated_at TEXT NOT NULL CHECK (updated_at \(instant))
        );

        CREATE TABLE content_installs (
            pack_id TEXT NOT NULL PRIMARY KEY,
            version TEXT NOT NULL,
            checksum TEXT NOT NULL,
            installed_at TEXT NOT NULL CHECK (installed_at \(instant))
        );

        CREATE TABLE adhkar_days (
            local_date TEXT NOT NULL CHECK (local_date \(localDate)),
            period TEXT NOT NULL CHECK (period \(period)),
            completed_at TEXT CHECK (completed_at \(instant)),
            completion_origin TEXT NOT NULL CHECK (completion_origin IN ('counters', 'manual', 'import')),
            PRIMARY KEY (local_date, period)
        );

        CREATE TABLE adhkar_item_progress (
            local_date TEXT NOT NULL CHECK (local_date \(localDate)),
            period TEXT NOT NULL CHECK (period \(period)),
            item_id TEXT NOT NULL,
            count INTEGER CHECK (count >= 0),
            target INTEGER CHECK (target >= 0),
            updated_at TEXT NOT NULL CHECK (updated_at \(instant)),
            PRIMARY KEY (local_date, period, item_id),
            CHECK (count IS NOT NULL OR target IS NOT NULL)
        );

        CREATE TABLE ruqyah_days (
            local_date TEXT NOT NULL PRIMARY KEY CHECK (local_date \(localDate)),
            completed_at TEXT NOT NULL CHECK (completed_at \(instant)),
            completion_origin TEXT NOT NULL CHECK (completion_origin IN ('counters', 'import'))
        );

        CREATE TABLE ruqyah_segment_progress (
            local_date TEXT NOT NULL CHECK (local_date \(localDate)),
            segment_id TEXT NOT NULL,
            count INTEGER NOT NULL CHECK (count >= 0),
            updated_at TEXT NOT NULL CHECK (updated_at \(instant)),
            PRIMARY KEY (local_date, segment_id)
        );

        CREATE TABLE reminder_rules (
            id TEXT NOT NULL PRIMARY KEY,
            kind TEXT NOT NULL CHECK (kind IN ('adhkar_morning', 'adhkar_evening', 'prayer', 'personal')),
            prayer_key TEXT CHECK (prayer_key IN ('fajr', 'dhuhr', 'asr', 'maghrib', 'isha')),
            offset_minutes INTEGER,
            local_time TEXT CHECK (local_time GLOB '[01][0-9]:[0-5][0-9]' OR local_time GLOB '2[0-3]:[0-5][0-9]'),
            weekday_mask INTEGER NOT NULL CHECK (weekday_mask BETWEEN 0 AND 127),
            enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
            updated_at TEXT NOT NULL CHECK (updated_at \(instant)),
            CHECK (kind NOT IN ('adhkar_morning', 'adhkar_evening') OR id = kind),
            CHECK ((prayer_key IS NULL) = (offset_minutes IS NULL)),
            CHECK ((prayer_key IS NULL) <> (local_time IS NULL))
        );

        CREATE TABLE reminder_state (
            rule_id TEXT NOT NULL PRIMARY KEY REFERENCES reminder_rules(id) ON DELETE CASCADE,
            last_shown_local_date TEXT NOT NULL CHECK (last_shown_local_date \(localDate))
        );

        CREATE TABLE location_profiles (
            id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
            label TEXT,
            latitude REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
            longitude REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
            zone_id TEXT,
            source TEXT NOT NULL CHECK (source IN ('device', 'manual', 'import')),
            updated_at TEXT CHECK (updated_at \(instant))
        );
        """
}
