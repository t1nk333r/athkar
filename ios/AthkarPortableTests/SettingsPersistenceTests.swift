import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

/// The production `SettingsModel` over a private, real SQLite database. A failed save is SQLite itself refusing the
/// write (a test-only trigger), never a stand-in repository.
final class SettingsPersistenceTests: XCTestCase {
    @MainActor
    func testDefaultsAndInitializationDoNotWriteRows() throws {
        let database = try AppDatabase.inMemory()
        let reports = Reports()
        let defaults = try SettingsModel(repository: database.settings, report: reports.record)
        XCTAssertEqual(defaults.theme, .system)
        XCTAssertEqual(defaults.textSize, .medium)
        XCTAssertEqual(defaults.lineSpacing, .comfortable)
        XCTAssertTrue(defaults.haptics)
        XCTAssertTrue(defaults.homePrayerRow)
        XCTAssertEqual(defaults.longOrder, .original)
        XCTAssertFalse(defaults.longOrderPromptAnswered)
        XCTAssertEqual(try settingsRows(database), [:])

        // Stored choices load as they are, and loading them writes nothing back.
        let repository = database.settings
        try repository.set(.dark, for: .theme, at: storedAt)
        try repository.set(.large, for: .textSize, at: storedAt)
        try repository.set(.wide, for: .lineSpacing, at: storedAt)
        try repository.set(false, for: .haptics, at: storedAt)
        try repository.set(false, for: .homePrayerRow, at: storedAt)
        try repository.set(.last, for: .longOrder, at: storedAt)
        try repository.set(true, for: .longOrderPromptAnswered, at: storedAt)
        let rows = try settingsRows(database)
        XCTAssertEqual(rows.count, 7)
        let stored = try SettingsModel(repository: repository, report: reports.record)
        XCTAssertEqual(stored.theme, .dark)
        XCTAssertEqual(stored.textSize, .large)
        XCTAssertEqual(stored.lineSpacing, .wide)
        XCTAssertFalse(stored.haptics)
        XCTAssertFalse(stored.homePrayerRow)
        XCTAssertEqual(stored.longOrder, .last)
        XCTAssertTrue(stored.longOrderPromptAnswered)
        XCTAssertEqual(try settingsRows(database), rows)
        XCTAssertTrue(reports.errors.isEmpty)
    }

    @MainActor
    func testThemeFailureRollsBackAndCanRetry() throws {
        try assertRollbackAndRetry(\.theme, .theme, stored: nil, change: .dark)
        try assertRollbackAndRetry(\.theme, .theme, stored: .light, change: .system)
    }

    @MainActor
    func testTextSizeFailureRollsBackAndCanRetry() throws {
        try assertRollbackAndRetry(\.textSize, .textSize, stored: nil, change: .large)
        try assertRollbackAndRetry(\.textSize, .textSize, stored: .small, change: .medium)
    }

    @MainActor
    func testLineSpacingFailureRollsBackAndCanRetry() throws {
        try assertRollbackAndRetry(\.lineSpacing, .lineSpacing, stored: nil, change: .wide)
        try assertRollbackAndRetry(\.lineSpacing, .lineSpacing, stored: .compact, change: .comfortable)
    }

    @MainActor
    func testHapticsFailureRollsBackAndCanRetry() throws {
        try assertRollbackAndRetry(\.haptics, .haptics, stored: nil, change: false)
        try assertRollbackAndRetry(\.haptics, .haptics, stored: false, change: true)
    }

    @MainActor
    func testHomePrayerRowFailureRollsBackAndCanRetry() throws {
        try assertRollbackAndRetry(\.homePrayerRow, .homePrayerRow, stored: nil, change: false)
        try assertRollbackAndRetry(\.homePrayerRow, .homePrayerRow, stored: false, change: true)
    }

    @MainActor
    func testLongOrderFailureRetainsCommittedValueAndCanRetry() throws {
        for stored in [nil, LongOrder.last] {
            let context = "stored \(stored.map(\.rawValue) ?? "nothing")"
            let database = try AppDatabase.inMemory()
            if let stored { try database.settings.set(stored, for: .longOrder, at: storedAt) }
            let committed = stored ?? .original
            let choice: LongOrder = committed == .last ? .original : .last
            let reports = Reports()
            let settings = try SettingsModel(repository: database.settings, report: reports.record)
            let rows = try settingsRows(database)

            try rejectWrites(of: "long_order", in: database)
            XCTAssertFalse(settings.setLongOrder(choice), context)
            XCTAssertEqual(settings.longOrder, committed, context)
            XCTAssertFalse(settings.longOrderPromptAnswered, context)
            XCTAssertEqual(try database.settings.value(for: .longOrder), committed, context)
            XCTAssertEqual(try settingsRows(database), rows, context)
            assertRejected(reports, count: 1, context)

            try acceptWrites(of: "long_order", in: database)
            XCTAssertTrue(settings.setLongOrder(choice), context)
            XCTAssertEqual(settings.longOrder, choice, context)
            XCTAssertFalse(settings.longOrderPromptAnswered, "the settings toggle answers no question; \(context)")
            let saved = try settingsRows(database)
            XCTAssertEqual(valueAndOrigin(saved["long_order"]), [#""\#(choice.rawValue)""#, "native"], context)
            XCTAssertNil(saved["long_order_prompt_answered"], context)
            assertRejected(reports, count: 1, context)

            let reloaded = try SettingsModel(repository: database.settings, report: reports.record)
            XCTAssertEqual(reloaded.longOrder, choice, context)
            XCTAssertFalse(reloaded.longOrderPromptAnswered, context)
        }
    }

    @MainActor
    func testPromptDecisionFailureLeavesBothValuesUnchangedAndCanRetry() throws {
        // `long_order` is written first, then the answered flag; either refusal must keep both.
        for rejected in ["long_order_prompt_answered", "long_order"] {
            for choice in LongOrder.allCases {
                for hasRows in [false, true] {
                    let context = "rejecting \(rejected), answering \(choice), \(hasRows ? "stored rows" : "no rows")"
                    let database = try AppDatabase.inMemory()
                    if hasRows {
                        try database.settings.set(.last, for: .longOrder, at: storedAt)
                        try database.settings.set(false, for: .longOrderPromptAnswered, at: storedAt)
                    }
                    let reports = Reports()
                    let settings = try SettingsModel(repository: database.settings, report: reports.record)
                    let committed = settings.longOrder
                    let rows = try settingsRows(database)

                    try rejectWrites(of: rejected, in: database)
                    XCTAssertFalse(settings.answerLongOrderPrompt(choice), context)
                    XCTAssertEqual(settings.longOrder, committed, context)
                    XCTAssertFalse(settings.longOrderPromptAnswered, context)
                    XCTAssertEqual(try database.settings.value(for: .longOrder), committed, context)
                    XCTAssertFalse(try database.settings.value(for: .longOrderPromptAnswered), context)
                    XCTAssertEqual(try settingsRows(database), rows, context)
                    assertRejected(reports, count: 1, context)

                    try acceptWrites(of: rejected, in: database)
                    XCTAssertTrue(settings.answerLongOrderPrompt(choice), context)
                    XCTAssertEqual(settings.longOrder, choice, context)
                    XCTAssertTrue(settings.longOrderPromptAnswered, context)
                    let saved = try settingsRows(database)
                    XCTAssertEqual(valueAndOrigin(saved["long_order"]), [#""\#(choice.rawValue)""#, "native"], context)
                    XCTAssertEqual(valueAndOrigin(saved["long_order_prompt_answered"]), ["true", "native"], context)
                    XCTAssertEqual(saved["long_order"]?.last, saved["long_order_prompt_answered"]?.last,
                                   "one transaction, one timestamp; \(context)")
                    assertRejected(reports, count: 1, context)

                    let reloaded = try SettingsModel(repository: database.settings, report: reports.record)
                    XCTAssertEqual(reloaded.longOrder, choice, context)
                    XCTAssertTrue(reloaded.longOrderPromptAnswered, context)
                }
            }
        }
    }

    @MainActor
    func testSuccessfulSettingsReloadAndRemainIsolated() throws {
        let database = try AppDatabase.inMemory()
        let other = try AppDatabase.inMemory()
        let reports = Reports()
        let settings = try SettingsModel(repository: database.settings, report: reports.record)
        _ = try SettingsModel(repository: other.settings, report: reports.record)
        settings.theme = .dark
        settings.textSize = .large
        // Choosing a default again still records the choice.
        settings.lineSpacing = .wide
        settings.lineSpacing = .comfortable
        settings.haptics = false
        settings.homePrayerRow = false
        XCTAssertTrue(settings.setLongOrder(.last))
        XCTAssertTrue(settings.answerLongOrderPrompt(.original))
        XCTAssertTrue(reports.errors.isEmpty)

        let rows = try settingsRows(database)
        XCTAssertEqual(Set(rows.keys), ["theme", "text_size", "line_spacing", "haptics", "home_prayer_row",
                                         "long_order", "long_order_prompt_answered"])
        XCTAssertEqual(Set(rows.values.map { $0[1] }), ["native"])
        XCTAssertEqual(rows["line_spacing"]?.first, #""comfortable""#)
        XCTAssertEqual(rows["long_order"]?.first, #""original""#)

        let reloaded = try SettingsModel(repository: database.settings, report: reports.record)
        XCTAssertEqual(reloaded.theme, .dark)
        XCTAssertEqual(reloaded.textSize, .large)
        XCTAssertEqual(reloaded.lineSpacing, .comfortable)
        XCTAssertFalse(reloaded.haptics)
        XCTAssertFalse(reloaded.homePrayerRow)
        XCTAssertEqual(reloaded.longOrder, .original)
        XCTAssertTrue(reloaded.longOrderPromptAnswered)

        XCTAssertEqual(try settingsRows(other), [:])
        let isolated = try SettingsModel(repository: other.settings, report: reports.record)
        XCTAssertEqual(isolated.theme, .system)
        XCTAssertEqual(isolated.lineSpacing, .comfortable)
        XCTAssertTrue(isolated.haptics)
        XCTAssertEqual(isolated.longOrder, .original)
        XCTAssertFalse(isolated.longOrderPromptAnswered)
        XCTAssertTrue(reports.errors.isEmpty)
    }

    /// A rejected change leaves the model and the database on `stored` (no row when `nil`) and is reported once; once
    /// SQLite accepts writes again, the same change saves and reloads.
    @MainActor
    private func assertRollbackAndRetry<Value: Codable & Equatable & Sendable>(
        _ property: ReferenceWritableKeyPath<SettingsModel, Value>, _ key: SettingKey<Value>,
        stored: Value?, change candidate: Value, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let context = "\(key.name), stored \(stored.map { "\($0)" } ?? "nothing")"
        let database = try AppDatabase.inMemory()
        if let stored { try database.settings.set(stored, for: key, at: storedAt) }
        let committed = stored ?? key.defaultValue
        XCTAssertNotEqual(candidate, committed, context, file: file, line: line)
        let reports = Reports()
        let settings = try SettingsModel(repository: database.settings, report: reports.record)
        XCTAssertEqual(settings[keyPath: property], committed, context, file: file, line: line)
        let rows = try settingsRows(database)

        try rejectWrites(of: key.name, in: database)
        settings[keyPath: property] = candidate
        XCTAssertEqual(settings[keyPath: property], committed, "the saved value stays; \(context)",
                       file: file, line: line)
        XCTAssertEqual(try database.settings.value(for: key), committed, context, file: file, line: line)
        XCTAssertEqual(try settingsRows(database), rows, "no row written back; \(context)", file: file, line: line)
        assertRejected(reports, count: 1, context, file: file, line: line)

        try acceptWrites(of: key.name, in: database)
        settings[keyPath: property] = candidate
        XCTAssertEqual(settings[keyPath: property], candidate, context, file: file, line: line)
        XCTAssertEqual(try database.settings.value(for: key), candidate, context, file: file, line: line)
        XCTAssertEqual(try settingsRows(database)[key.name]?[1], "native", context, file: file, line: line)
        assertRejected(reports, count: 1, context, file: file, line: line)
        let reloaded = try SettingsModel(repository: database.settings, report: reports.record)
        XCTAssertEqual(reloaded[keyPath: property], candidate, context, file: file, line: line)
    }
}

// MARK: Support

private let storedAt = Date(timeIntervalSince1970: 1_760_000_000)
private let rejection = "task009 rejected settings write"

/// The errors a model reported, in order.
private final class Reports {
    var errors: [any Error] = []

    func record(_ error: any Error) { errors.append(error) }
}

/// Exactly `count` reports, each the SQLite refusal from `rejectWrites`.
private func assertRejected(_ reports: Reports, count: Int, _ context: String,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(reports.errors.count, count, "reported errors; \(context)", file: file, line: line)
    for error in reports.errors {
        let sqlite = error as? any CustomNSError
        XCTAssertEqual(sqlite.map { type(of: $0).errorDomain }, "GRDB.DatabaseError", context, file: file, line: line)
        XCTAssertEqual(sqlite?.errorCode, 1811, "SQLITE_CONSTRAINT_TRIGGER; \(context)", file: file, line: line)
        XCTAssertEqual(sqlite?.errorUserInfo[NSLocalizedFailureReasonErrorKey] as? String, rejection, context,
                       file: file, line: line)
    }
}

/// Every `settings` row as `key: [value_json, origin, updated_at]`, to compare a refused change down to its metadata.
private func settingsRows(_ database: AppDatabase) throws -> [String: [String]] {
    try database.reader.read { db in
        let rows = try String.fetchAll(db, sql: """
            SELECT key || ' ' || value_json || ' ' || origin || ' ' || updated_at FROM settings
            """)
        return Dictionary(uniqueKeysWithValues: rows.map { row in
            let fields = row.components(separatedBy: " ")
            return (fields[0], Array(fields.dropFirst()))
        })
    }
}

private func valueAndOrigin(_ row: [String]?) -> [String]? { row.map { Array($0.prefix(2)) } }

/// SQLite refuses every write of `key`, as a full or failing disk would: test-only triggers on the test's private
/// database. An upsert can reach the row through INSERT or UPDATE, so both are refused.
private func rejectWrites(of key: String, in database: AppDatabase) throws {
    try database.writer.write { db in
        for event in ["INSERT", "UPDATE"] {
            try db.execute(sql: """
                CREATE TRIGGER reject_\(event.lowercased())_\(key) BEFORE \(event) ON settings
                WHEN NEW.key = '\(key)' BEGIN SELECT RAISE(ABORT, '\(rejection)'); END
                """)
        }
    }
}

private func acceptWrites(of key: String, in database: AppDatabase) throws {
    try database.writer.write { db in
        for event in ["insert", "update"] {
            try db.execute(sql: "DROP TRIGGER reject_\(event)_\(key)")
        }
    }
}
