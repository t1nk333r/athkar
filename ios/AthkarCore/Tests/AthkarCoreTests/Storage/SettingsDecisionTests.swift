import AthkarCore
import Foundation
import GRDB
import Testing

/// `setLongOrderDecision`, the answer to the one-time long-order question: the order and the answered flag commit
/// together, or SQLite keeps both rows (or their absence) exactly as they were.
struct SettingsDecisionTests {
    /// The rows before the answer: none (every setting at its default), or an imported order and a stored «not
    /// answered» beside an unrelated setting, which the answer reaches through an update.
    enum Baseline: CaseIterable, Sendable {
        case absent, stored
    }

    let database: AppDatabase
    let t0 = Instant.at("2026-09-23T05:00:00.000Z")
    let t1 = Instant.at("2026-09-23T05:10:00.250Z")

    init() throws {
        database = try AppDatabase.inMemory()
    }

    @Test(arguments: LongOrder.allCases, Baseline.allCases)
    func decisionWritesBothNativeRowsAtOneTimestamp(choice: LongOrder, baseline: Baseline) throws {
        try seed(baseline)
        let unrelated = try rows().filter { $0[0] == "theme" }
        try database.settings.setLongOrderDecision(choice, at: t1)
        #expect(try rows() == [
            ["long_order", #""\#(choice.rawValue)""#, "native", "2026-09-23T05:10:00.250Z"],
            ["long_order_prompt_answered", "true", "native", "2026-09-23T05:10:00.250Z"],
        ] + unrelated)
        #expect(try database.settings.value(for: .longOrder) == choice)
        #expect(try database.settings.value(for: .longOrderPromptAnswered))
    }

    /// `long_order` is written first.
    @Test(arguments: LongOrder.allCases, Baseline.allCases)
    func decisionRollsBackWhenFirstRowFails(choice: LongOrder, baseline: Baseline) throws {
        try expectRollback(rejecting: "long_order", choice: choice, baseline: baseline)
    }

    /// The answered flag is written second; its rejection must also undo the order the transaction already wrote.
    @Test(arguments: LongOrder.allCases, Baseline.allCases)
    func decisionRollsBackWhenSecondRowFails(choice: LongOrder, baseline: Baseline) throws {
        try expectRollback(rejecting: "long_order_prompt_answered", choice: choice, baseline: baseline)
    }

    @Test(arguments: LongOrder.allCases)
    func decisionFailureDoesNotCreateDefaultRows(choice: LongOrder) throws {
        try rejectWrites(of: "long_order_prompt_answered")
        #expect(throws: DatabaseError.self) { try database.settings.setLongOrderDecision(choice, at: t1) }
        #expect(try database.reader.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM settings") } == 0)
        #expect(try database.settings.value(for: .longOrder) == .original)
        #expect(try !database.settings.value(for: .longOrderPromptAnswered))
    }

    @Test(arguments: LongOrder.allCases)
    func decisionFailurePreservesExistingOriginsAndTimestamps(choice: LongOrder) throws {
        try seed(.stored)
        try rejectWrites(of: "long_order_prompt_answered")
        #expect(throws: DatabaseError.self) { try database.settings.setLongOrderDecision(choice, at: t1) }
        #expect(try rows() == [
            ["long_order", #""last""#, "athkar-pwa", "2026-09-20T08:00:00.000Z"],
            ["long_order_prompt_answered", "false", "native", "2026-09-21T09:30:00.125Z"],
            ["theme", #""dark""#, "athkar-pwa", "2026-09-22T10:00:00.000Z"],
        ])
        #expect(try database.settings.value(for: .longOrder) == .last)
        #expect(try !database.settings.value(for: .longOrderPromptAnswered))
    }

    @Test(arguments: LongOrder.allCases, Baseline.allCases)
    func decisionRecoversAfterFailureIsRemoved(choice: LongOrder, baseline: Baseline) throws {
        try seed(baseline)
        try rejectWrites(of: "long_order_prompt_answered")
        #expect(throws: DatabaseError.self) { try database.settings.setLongOrderDecision(choice, at: t0) }

        try acceptWrites(of: "long_order_prompt_answered")
        try database.settings.setLongOrderDecision(choice, at: t1)
        #expect(try Array(rows().prefix(2)) == [
            ["long_order", #""\#(choice.rawValue)""#, "native", "2026-09-23T05:10:00.250Z"],
            ["long_order_prompt_answered", "true", "native", "2026-09-23T05:10:00.250Z"],
        ])
        #expect(try database.settings.value(for: .longOrder) == choice)
        #expect(try database.settings.value(for: .longOrderPromptAnswered))
    }

    // MARK: Support

    private let rejection = "task009 rejected settings write"

    private func expectRollback(rejecting key: String, choice: LongOrder, baseline: Baseline,
                                sourceLocation: SourceLocation = #_sourceLocation) throws {
        try seed(baseline)
        let before = try dump(database)
        try rejectWrites(of: key)
        let error = #expect(throws: DatabaseError.self, sourceLocation: sourceLocation) {
            try database.settings.setLongOrderDecision(choice, at: t1)
        }
        #expect(error?.extendedResultCode == .SQLITE_CONSTRAINT_TRIGGER, sourceLocation: sourceLocation)
        #expect(error?.message == rejection, sourceLocation: sourceLocation)
        #expect(try dump(database) == before, sourceLocation: sourceLocation)
    }

    private func seed(_ baseline: Baseline) throws {
        guard baseline == .stored else { return }
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO settings (key, value_json, origin, updated_at) VALUES
                    ('long_order', '"last"', 'athkar-pwa', '2026-09-20T08:00:00.000Z'),
                    ('long_order_prompt_answered', 'false', 'native', '2026-09-21T09:30:00.125Z'),
                    ('theme', '"dark"', 'athkar-pwa', '2026-09-22T10:00:00.000Z')
                """)
        }
    }

    /// Every `settings` row as `[key, value_json, origin, updated_at]`, by key.
    private func rows() throws -> [[String]] {
        try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT key, value_json, origin, updated_at FROM settings ORDER BY key").map {
                [$0["key"] as String, $0["value_json"] as String, $0["origin"] as String, $0["updated_at"] as String]
            }
        }
    }

    /// SQLite refuses every write of `key`, as a full or failing disk would: test-only triggers on this test's
    /// private database. An upsert can reach the row through INSERT or UPDATE, so both are refused.
    private func rejectWrites(of key: String) throws {
        try database.writer.write { db in
            for event in ["INSERT", "UPDATE"] {
                try db.execute(sql: """
                    CREATE TRIGGER reject_\(event.lowercased())_\(key) BEFORE \(event) ON settings
                    WHEN NEW.key = '\(key)' BEGIN SELECT RAISE(ABORT, '\(rejection)'); END
                    """)
            }
        }
    }

    private func acceptWrites(of key: String) throws {
        try database.writer.write { db in
            for event in ["insert", "update"] {
                try db.execute(sql: "DROP TRIGGER reject_\(event)_\(key)")
            }
        }
    }
}
