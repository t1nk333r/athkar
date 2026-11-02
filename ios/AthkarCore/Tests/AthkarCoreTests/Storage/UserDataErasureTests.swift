import AthkarCore
import Foundation
import Testing

/// Every example file imported into one database.
private func importedExamples() throws -> AppDatabase {
    let database = try AppDatabase.inMemory()
    let importer = BackupImporter(database: database, content: try RepoFile.content)
    for name in ["athkar-pwa", "ruqyah-pwa", "native"] {
        try importer.importFile(try BackupFile.decode(RepoFile.data("spec/backup/examples/\(name).athkarbackup")))
    }
    return database
}

/// spec/schema.md "Delete all data".
struct DeleteAllDataTests {
    @Test func everyUserTableIsEmptiedAndContentInstallsStay() throws {
        let database = try importedExamples()
        try database.location.save(LocationProfile(latitude: 21.42, longitude: 39.83, source: .device, updatedAt: nil))
        let install = ContentInstall(packId: "adhkar", version: "1.0.0", checksum: String(repeating: "a", count: 64),
                                     installedAt: Instant.at("2026-10-01T00:00:00.000Z"))
        try database.contentInstalls.record(install)
        #expect(try database.hasUserData())

        try database.deleteAllUserData()

        #expect(try !database.hasUserData())
        for (table, rows) in try dump(database) where table != "content_installs" {
            #expect(rows.isEmpty, "\(table)")
        }
        #expect(try database.contentInstalls.installs() == [install])
        // Afterwards the database reads as a fresh install's.
        #expect(try database.settings.value(for: .theme) == .system)
        #expect(try database.reminders.rules().isEmpty)
    }

    /// A table a later migration adds must be listed as user data or kept on purpose (spec/schema.md).
    @Test func everyTableIsAccountedFor() throws {
        let tables = try dump(try AppDatabase.inMemory()).keys
        #expect(Set(tables) == Set(AppDatabase.userTables + ["content_installs"]))
    }

    @Test func freshDatabaseHasNoUserData() throws {
        let database = try AppDatabase.inMemory()
        #expect(try !database.hasUserData())
        try database.settings.set(.dark, for: .theme)
        #expect(try database.hasUserData())
    }
}
