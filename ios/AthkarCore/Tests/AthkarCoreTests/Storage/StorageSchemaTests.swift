import AthkarCore
import Foundation
import GRDB
import Testing

struct StorageSchemaTests {
    struct Column: Equatable, CustomStringConvertible {
        var name: String
        var type: String
        var notNull: Bool
        var primaryKeyIndex: Int

        var description: String { "\(name) \(type)\(notNull ? " NOT NULL" : "") pk=\(primaryKeyIndex)" }
    }

    /// The column tables under "## Tables (migration v1)" in spec/schema.md.
    static func documentedTables() throws -> [String: [Column]] {
        let text = String(decoding: try RepoFile.data("spec/schema.md"), as: UTF8.self)
        var tables: [String: [Column]] = [:]
        var inV1 = false
        var table: String?
        var inColumnTable = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("## ") {
                inV1 = line == "## Tables (migration v1)"
                table = nil
            } else if inV1, line.hasPrefix("### `"), line.hasSuffix("`") {
                table = String(line.dropFirst(5).dropLast())
                tables[table!] = []
            } else if line == "| Column | Type | Null | Key | Notes |" {
                inColumnTable = table != nil
            } else if line.isEmpty {
                inColumnTable = false
            } else if inColumnTable, let table, line.hasPrefix("| `") {
                let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let key = cells[4]
                tables[table]!.append(Column(
                    name: cells[1].trimmingCharacters(in: CharacterSet(charactersIn: "`")),
                    type: cells[2],
                    notNull: cells[3] == "no",
                    primaryKeyIndex: key.isEmpty ? 0 : key == "PK" ? 1 : Int(key.dropFirst(3))!))
            }
        }
        return tables
    }

    @Test func migrationV1CreatesExactlyTheDocumentedSchema() throws {
        let documented = try Self.documentedTables()
        #expect(documented.count == 9)

        let database = try AppDatabase.inMemory()
        let actual = try database.reader.read { db in
            let names = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
                """)
            return try Dictionary(uniqueKeysWithValues: names.map { name in
                (name, try db.columns(in: name).map {
                    Column(name: $0.name, type: $0.type, notNull: $0.isNotNull, primaryKeyIndex: $0.primaryKeyIndex)
                })
            })
        }
        #expect(Set(actual.keys) == Set(documented.keys))
        for (table, columns) in documented {
            #expect(actual[table] == columns, "\(table)")
        }
    }

    @Test func onDiskDatabaseUsesWALAndMigratesOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("athkar.sqlite")

        let first = try AppDatabase.onDisk(at: url)
        try first.settings.set(.dark, for: .theme, at: Instant.at("2026-09-23T10:00:00.000Z"))
        let reopened = try AppDatabase.onDisk(at: url)

        let (journalMode, migrations) = try reopened.reader.read { db in
            (try String.fetchOne(db, sql: "PRAGMA journal_mode"),
             try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations"))
        }
        #expect(journalMode == "wal")
        #expect(migrations == ["v1"])
        #expect(try reopened.settings.value(for: .theme) == .dark)
    }

    @Test func checksRejectMalformedDatesAndInstants() throws {
        let database = try AppDatabase.inMemory()
        let rows: [(String, StatementArguments)] = [
            ("INSERT INTO adhkar_days VALUES (?, 'morning', NULL, 'manual')", ["23-09-2026"]),
            ("INSERT INTO adhkar_days VALUES ('2026-09-23', 'morning', ?, 'manual')", ["2026-09-23 10:00:00.000"]),
            ("INSERT INTO adhkar_days VALUES ('2026-09-23', 'noon', NULL, 'manual')", []),
            ("INSERT INTO adhkar_item_progress VALUES ('2026-09-23', 'morning', 'morning-01', NULL, NULL, ?)",
             ["2026-09-23T10:00:00.000Z"]),
            ("INSERT INTO ruqyah_days VALUES ('2026-09-23', ?, 'manual')", ["2026-09-23T10:00:00.000Z"]),
            ("INSERT INTO location_profiles VALUES (2, NULL, 21.42, 39.83, NULL, 'device', NULL)", []),
        ]
        for (sql, arguments) in rows {
            #expect(throws: DatabaseError.self, "\(sql)") {
                try database.writer.write { try $0.execute(sql: sql, arguments: arguments) }
            }
        }
    }

    @Test func localTimeMustBeAWallClockTime() throws {
        let database = try AppDatabase.inMemory()
        func insert(_ time: String) throws {
            try database.writer.write {
                try $0.execute(sql: """
                    INSERT INTO reminder_rules VALUES (?, 'personal', NULL, NULL, ?, 127, 1, '2026-09-23T10:00:00.000Z')
                    """, arguments: [time, time])
            }
        }
        for time in ["00:00", "09:30", "19:59", "23:59"] {
            #expect(throws: Never.self, "\(time)") { try insert(time) }
        }
        for time in ["24:00", "29:59", "23:60", "30:00", "9:30", "09:30:00"] {
            #expect(throws: DatabaseError.self, "\(time)") { try insert(time) }
        }
    }
}
