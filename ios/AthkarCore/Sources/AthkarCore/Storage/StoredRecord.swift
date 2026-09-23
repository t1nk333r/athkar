import Foundation
import GRDB

/// Column conventions shared by every table in spec/schema.md: snake_case columns for camelCase properties,
/// and instants stored as `toISOString()` text (`2026-09-22T17:38:40.481Z`).
public protocol StoredRecord: Codable, FetchableRecord, PersistableRecord {}

extension StoredRecord {
    public static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
    public static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }

    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .custom { ISOInstant.format($0) }
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .custom { String.fromDatabaseValue($0).flatMap(ISOInstant.parse) }
    }
}

extension Period: DatabaseValueConvertible {}
