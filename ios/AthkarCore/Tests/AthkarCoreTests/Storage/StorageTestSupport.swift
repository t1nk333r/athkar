import AthkarCore
import Foundation
import GRDB

/// Files in the repository, read in place (fixtures are not copied into the package).
enum RepoFile {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Storage
        .deletingLastPathComponent() // AthkarCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // AthkarCore
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent()

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relativePath))
    }

    /// The shipped content packs, read from `content/`.
    static var content: ContentPacks {
        get throws {
            try ContentPacks(adhkarPack: data("content/adhkar.v1.json"), ruqyahPack: data("content/ruqyah.v1.json"))
        }
    }
}

enum Instant {
    /// Parses a `toISOString()` instant; traps on bad test input.
    static func at(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)!
    }
}

/// Every row of every table, in a stable order, for whole-database comparisons.
func dump(_ database: AppDatabase) throws -> [String: [Row]] {
    try database.reader.read { db in
        let tables = try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
            """)
        var result: [String: [Row]] = [:]
        for table in tables {
            let columns = try db.columns(in: table).map { $0.name.quotedDatabaseIdentifier }
            result[table] = try Row.fetchAll(
                db, sql: "SELECT * FROM \(table.quotedDatabaseIdentifier) ORDER BY \(columns.joined(separator: ", "))")
        }
        return result
    }
}

/// A JSON document as a value, for comparing JSON regardless of key order and number spelling.
enum JSONValue: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    subscript(key: String) -> JSONValue? {
        get {
            guard case let .object(members) = self else { return nil }
            return members[key]
        }
        set {
            guard case var .object(members) = self else { return }
            members[key] = newValue
            self = .object(members)
        }
    }
}
