import AthkarCore
import Foundation
import GRDB
import Testing

private let athkarFile = "spec/backup/examples/athkar-pwa.athkarbackup"
private let ruqyahFile = "spec/backup/examples/ruqyah-pwa.athkarbackup"

private func imported(_ paths: String...) throws -> AppDatabase {
    let database = try AppDatabase.inMemory()
    for path in paths {
        try BackupImporter(database: database).importBackup(try RepoFile.data(path))
    }
    return database
}

struct BackupRoundTripTests {
    @Test(arguments: [athkarFile, ruqyahFile])
    func exportAfterImportReproducesThePWAFile(path: String) throws {
        let data = try RepoFile.data(path)
        let database = try AppDatabase.inMemory()
        let envelope = try BackupImporter(database: database).importBackup(data)

        let exported = try BackupExporter(database: database).export(
            app: envelope.meta.app,
            today: try #require(envelope.adhkar?.today.date ?? envelope.ruqyah?.today.date),
            timeZone: envelope.meta.timeZone,
            exportedAt: envelope.meta.exportedAt,
            includeLocation: envelope.reminders?.location != nil)

        var expected = try JSONValue(data: data)
        // spec/schema.md "Export" exception 1: stored coordinates are rounded to two decimals (§7.4).
        for axis in ["latitude", "longitude"] {
            if case let .number(value)? = expected["reminders"]?["location"]?[axis] {
                expected["reminders"]?["location"]?[axis] = .number((value * 100).rounded() / 100)
            }
        }
        #expect(try JSONValue(data: exported.encoded()) == expected)
    }

    @Test func laterExportRollsTheImportedDayIntoHistory() throws {
        let database = try imported(athkarFile)
        let envelope = try BackupExporter(database: database).export(
            app: .athkarPWA, today: "2026-09-25", timeZone: "Asia/Riyadh")
        let adhkar = try #require(envelope.adhkar)

        #expect(adhkar.today.progress == .init(morning: [:], evening: [:]))
        #expect(adhkar.today.manualCompletion == .init(morning: false, evening: false))
        #expect(adhkar.history == [
            .init(date: "2026-09-23", morning: false, evening: true, morningAt: nil, eveningAt: nil),
            .init(date: "2026-09-22", morning: true, evening: false,
                  morningAt: Instant.at("2026-09-22T17:38:40.481Z"), eveningAt: nil),
        ])
        #expect(envelope.reminders?.location == nil)
        #expect(envelope.ruqyah == nil)
    }
}

struct BackupImportTests {
    @Test func athkarFileLandsInTheDocumentedTables() throws {
        let database = try imported(athkarFile)

        let morning = try database.adhkar.session(on: "2026-09-23", period: .morning)
        #expect(morning.progress == ["morning-01": 1, "morning-02": 3, "morning-20": 250])
        #expect(morning.targets == ["morning-20": 10])
        #expect(morning.completion == nil)
        let evening = try database.adhkar.session(on: "2026-09-23", period: .evening)
        #expect(evening.completion?.completionOrigin == .manual)
        #expect(evening.completion?.completedAt == nil)
        #expect(try database.adhkar.days(from: "2026-09-22", through: "2026-09-22") == [
            AdhkarDay(localDate: "2026-09-22", period: .morning, completedAt: Instant.at("2026-09-22T17:38:40.481Z"),
                      completionOrigin: .imported),
        ])

        #expect(try database.reminders.rule(id: "adhkar_morning")?.enabled == true)
        #expect(try database.reminders.rule(id: "adhkar_evening")?.prayerKey == .asr)
        #expect(try database.reminders.lastShown(ruleId: "adhkar_morning") == "2026-09-22")
        #expect(try database.reminders.lastShown(ruleId: "adhkar_evening") == nil)
        #expect(try database.settings.value(for: .calculationMethod) == .ummAlQura)
        #expect(try database.settings.value(for: .asrSchool) == .hanafi)
        #expect(try database.settings.value(for: .longOrder) == .last)

        let location = try #require(try database.location.profile())
        #expect(location.latitude == 21.42 && location.longitude == 39.83)
        #expect(location.source == .imported && location.zoneId == nil)
        #expect(location.updatedAt == Instant.at("2026-09-23T17:38:40.481Z"))
    }

    @Test(arguments: [athkarFile, ruqyahFile])
    func reimportIsANoOp(path: String) throws {
        let database = try imported(path)
        let once = try dump(database)
        try BackupImporter(database: database).importBackup(try RepoFile.data(path))
        #expect(try dump(database) == once)
    }

    @Test func eitherOrderGivesTheSameDatabaseWithAthkarPreferences() throws {
        let athkarFirst = try imported(athkarFile, ruqyahFile)
        let ruqyahFirst = try imported(ruqyahFile, athkarFile)
        #expect(try dump(athkarFirst) == dump(ruqyahFirst))

        // The ruqyah file says light / large / haptics on; the athkar file wins.
        #expect(try athkarFirst.settings.value(for: .theme) == .dark)
        #expect(try athkarFirst.settings.value(for: .textSize) == .medium)
        #expect(try athkarFirst.settings.value(for: .haptics) == false)
        #expect(try athkarFirst.ruqyah.counts(on: "2026-09-23")["qaf-23-29"] == 7)
    }

    @Test func existingNativeDataWinsUnlessEmpty() throws {
        let database = try AppDatabase.inMemory()
        let native = Instant.at("2026-09-23T04:00:00.000Z")
        // Non-empty native units.
        try database.adhkar.setCount(5, for: "morning-01", on: "2026-09-23", period: .morning, at: native)
        try database.adhkar.markComplete(on: "2026-09-22", period: .morning, origin: .counters, completedAt: native)
        try database.ruqyah.markComplete(on: "2026-09-21", completedAt: native)
        try database.ruqyah.setCount(2, for: "qaf-1-8", on: "2026-09-23", at: native)
        try database.settings.set(.system, for: .theme, at: native)
        try database.reminders.save(ReminderRule.adhkar(.morning, enabled: false, updatedAt: native))
        try database.reminders.setLastShown("2026-09-23", ruleId: "adhkar_morning")
        try database.location.save(LocationProfile(latitude: 24.71, longitude: 46.68, source: .device,
                                                   updatedAt: native))
        // Empty native units: a chosen target alone, a zero count.
        try database.adhkar.setTarget(3, for: "evening-05", on: "2026-09-23", period: .evening, at: native)
        try database.ruqyah.setCount(0, for: "nas-1-6", on: "2026-09-23", at: native)

        let importer = BackupImporter(database: database)
        try importer.importBackup(try RepoFile.data(athkarFile))
        try importer.importBackup(try RepoFile.data(ruqyahFile))

        let morning = try database.adhkar.session(on: "2026-09-23", period: .morning)
        #expect(morning.progress == ["morning-01": 5])
        #expect(morning.targets == [:])
        #expect(try database.adhkar.days(from: "2026-09-22", through: "2026-09-22").map(\.completionOrigin)
                == [.counters])
        let evening = try database.adhkar.session(on: "2026-09-23", period: .evening)
        #expect(evening.targets == [:])
        #expect(evening.completion?.completionOrigin == .manual)

        #expect(try database.ruqyah.days(from: "2026-09-21", through: "2026-09-22") == [
            RuqyahDay(localDate: "2026-09-21", completedAt: native, completionOrigin: .counters),
            RuqyahDay(localDate: "2026-09-22", completedAt: Instant.at("2026-09-22T04:55:00.000Z"),
                      completionOrigin: .imported),
        ])
        let counts = try database.ruqyah.counts(on: "2026-09-23")
        #expect(counts["qaf-1-8"] == 2)
        #expect(counts["nas-1-6"] == 3)
        #expect(counts["qaf-23-29"] == 7)

        #expect(try database.settings.value(for: .theme) == .system)
        #expect(try database.settings.value(for: .textSize) == .medium)
        #expect(try database.reminders.rule(id: "adhkar_morning")?.enabled == false)
        #expect(try database.reminders.rule(id: "adhkar_evening") != nil)
        #expect(try database.reminders.lastShown(ruleId: "adhkar_morning") == "2026-09-23")
        #expect(try database.location.profile()?.source == .device)
    }

    @Test(arguments: [athkarFile, ruqyahFile])
    func leadingByteOrderMarkIsIgnored(path: String) throws {
        let data = try RepoFile.data(path)
        let withBOM = try AppDatabase.inMemory()
        try BackupImporter(database: withBOM).importBackup(Data([0xEF, 0xBB, 0xBF]) + data)
        #expect(try dump(withBOM) == dump(try imported(path)))
    }

    @Test func rejectedFilesChangeNothing() throws {
        let text = String(decoding: try RepoFile.data(ruqyahFile), as: UTF8.self)
        let cases: [(String, BackupError?)] = [
            (text.replacingOccurrences(of: #""format": 1"#, with: #""format": 2"#), .unsupportedFormat(2)),
            (text.replacingOccurrences(of: #""2026-09-21": {"#, with: #""2026-02-30": {"#),
             .invalid(path: "ruqyah.history.2026-02-30", reason: "2026-02-30 is not a YYYY-MM-DD calendar date")),
            (text.replacingOccurrences(of: "2026-09-21T05:10:00.000Z", with: "2026-09-21T24:10:00.000Z"), nil),
            (text.replacingOccurrences(of: #""app": "ruqyah-pwa""#, with: #""app": "other""#), nil),
            (String(text.dropLast(4)), nil),
        ]
        for (index, (file, expected)) in cases.enumerated() {
            #expect(file != text, "case \(index) did not change the file")
            let database = try AppDatabase.inMemory()
            let empty = try dump(database)
            let error = #expect(throws: BackupError.self, "case \(index)") {
                try BackupImporter(database: database).importBackup(Data(file.utf8))
            }
            if let expected {
                #expect(error == expected)
            } else if let error, case .malformed = error {
            } else {
                Issue.record("case \(index): expected .malformed, got \(String(describing: error))")
            }
            #expect(try dump(database) == empty)
        }
    }
}
