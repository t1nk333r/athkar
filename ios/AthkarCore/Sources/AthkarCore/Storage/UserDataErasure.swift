import Foundation
import GRDB

extension AppDatabase {
    /// Every table that holds what the user did or chose (spec/schema.md "Delete all data"). `content_installs` is
    /// not among them: it records which bundled pack versions are installed, nothing the user wrote, and launch
    /// records it again anyway.
    public static let userTables = [
        "settings", "adhkar_days", "adhkar_item_progress", "ruqyah_days", "ruqyah_segment_progress",
        "ruqyah_sura_days", "suwar_page_reads", "suwar_sura_days", "tasbih_counts", "prayer_records",
        "reminder_state", "reminder_rules", "location_profiles",
    ]

    /// «حذف كل البيانات»: deletes every row of every user table in one transaction, so the database reads as a fresh
    /// install's. The app then clears what lives outside the database: notifications and its `UserDefaults` keys.
    public func deleteAllUserData() throws {
        try writer.write { db in
            for table in Self.userTables {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    /// `true` when no user table has a row: nothing to export, and the first-run offer to import may show.
    public func hasUserData() throws -> Bool {
        try writer.read { db in
            for table in Self.userTables where try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM \(table))") == true {
                return true
            }
            return false
        }
    }
}
