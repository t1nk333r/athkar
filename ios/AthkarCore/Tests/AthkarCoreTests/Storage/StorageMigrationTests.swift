@testable import AthkarCore
import Foundation
import GRDB
import Testing

/// Each migration keeps the data of the version before it (spec/schema.md, "Migrations"): a database seeded at the
/// earlier version with a row in every table opens with those rows unchanged and the new tables empty.
struct StorageMigrationTests {
    /// One row per `v1` table.
    static let v1Rows = [
        """
        INSERT INTO settings VALUES ('theme', '"dark"', 'native', '2026-09-23T05:00:00.000Z')
        """,
        """
        INSERT INTO content_installs VALUES ('ruqyah', '1.0.1', 'abc', '2026-09-23T05:00:00.000Z')
        """,
        """
        INSERT INTO adhkar_days VALUES ('2026-09-23', 'morning', '2026-09-23T05:00:00.000Z', 'counters')
        """,
        """
        INSERT INTO adhkar_item_progress VALUES ('2026-09-23', 'morning', 'morning-02', 3, 3,
            '2026-09-23T05:00:00.000Z')
        """,
        """
        INSERT INTO ruqyah_days VALUES ('2026-09-22', '2026-09-22T04:55:00.000Z', 'import')
        """,
        """
        INSERT INTO ruqyah_segment_progress VALUES ('2026-09-23', 'qaf-23-29', 7, '2026-09-23T05:00:00.000Z')
        """,
        """
        INSERT INTO reminder_rules VALUES ('adhkar_morning', 'adhkar_morning', 'fajr', 60, NULL, 127, 1,
            '2026-09-23T05:00:00.000Z')
        """,
        """
        INSERT INTO reminder_state VALUES ('adhkar_morning', '2026-09-22')
        """,
        """
        INSERT INTO location_profiles VALUES (1, NULL, 21.42, 39.83, NULL, 'manual', NULL)
        """,
    ]

    @Test func v2KeepsEveryV1RowAndAddsAnEmptySuraTable() throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: configuration)
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        let v1Tables = try queue.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%' ORDER BY name
                """)
        }
        #expect(v1Tables.count == Self.v1Rows.count)
        #expect(!v1Tables.contains("ruqyah_sura_days"))
        try queue.write { db in
            for sql in Self.v1Rows { try db.execute(sql: sql) }
        }
        let before = try Self.rows(of: v1Tables, in: queue)
        #expect(before.values.allSatisfy { $0.count == 1 })

        let database = try AppDatabase(queue)
        #expect(try Self.rows(of: v1Tables, in: queue) == before)
        #expect(try database.ruqyah.suraDays(on: "2026-09-23") == [:])
        #expect(try database.ruqyah.recordedDayCount(.all, before: "2026-09-23") == 1)
        let migrations = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
        #expect(migrations == ["v1", "v2"])
    }

    /// Every row of each table, in rowid order.
    static func rows(of tables: [String], in queue: DatabaseQueue) throws -> [String: [Row]] {
        try queue.read { db in
            try Dictionary(uniqueKeysWithValues: tables.map { table in
                (table, try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY rowid"))
            })
        }
    }
}
