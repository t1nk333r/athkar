import AthkarCore
import Foundation
import GRDB
import Testing

private let athkarFile = "spec/backup/examples/athkar-pwa.athkarbackup"
private let ruqyahFile = "spec/backup/examples/ruqyah-pwa.athkarbackup"

private func imported(_ paths: String...) throws -> AppDatabase {
    let database = try AppDatabase.inMemory()
    for path in paths {
        try BackupImporter(database: database, content: try RepoFile.content).importBackup(try RepoFile.data(path))
    }
    return database
}

struct BackupRoundTripTests {
    @Test(arguments: [athkarFile, ruqyahFile])
    func exportAfterImportReproducesThePWAFile(path: String) throws {
        let data = try RepoFile.data(path)
        let database = try AppDatabase.inMemory()
        let envelope = try BackupImporter(database: database, content: try RepoFile.content).importBackup(data)

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
                expected["reminders"]?["location"]?[axis] = .number((value * 100 + 0.5).rounded(.down) / 100)
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

    @Test func nativeOnlyCalculationMethodExportsAsThePWADefault() throws {
        let database = try imported(athkarFile)
        try database.settings.set(.moonsightingCommittee, for: .calculationMethod)
        let envelope = try BackupExporter(database: database).export(
            app: .athkarPWA, today: "2026-09-23", timeZone: "Asia/Riyadh")
        #expect(envelope.reminders?.calculationMethod == .mwl)
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
        try BackupImporter(database: database, content: try RepoFile.content).importBackup(try RepoFile.data(path))
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

        let importer = BackupImporter(database: database, content: try RepoFile.content)
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

    /// Choosing the default in the app is still a choice: the import's `umm-al-qura` must not replace it. The Asr
    /// school the user never touched takes the file's `hanafi`.
    @Test func explicitNativeChoiceOfTheDefaultMethodOutranksAnImport() throws {
        let database = try AppDatabase.inMemory()
        try database.settings.set(.mwl, for: .calculationMethod)
        try BackupImporter(database: database, content: try RepoFile.content).importBackup(try RepoFile.data(athkarFile))
        let settings = try database.settings.calculationSettings()
        #expect(settings.method == .mwl)
        #expect(settings.asrSchool == .hanafi)
    }

    @Test(arguments: [athkarFile, ruqyahFile])
    func leadingByteOrderMarkIsIgnored(path: String) throws {
        let data = try RepoFile.data(path)
        let withBOM = try AppDatabase.inMemory()
        try BackupImporter(database: withBOM, content: try RepoFile.content).importBackup(Data([0xEF, 0xBB, 0xBF]) + data)
        #expect(try dump(withBOM) == dump(try imported(path)))
    }

    @Test func bothFalseHistoryEntryIsNotStoredAndNotReExported() throws {
        let original = String(decoding: try RepoFile.data(athkarFile), as: UTF8.self)
        let file = original.replacingOccurrences(
            of: "\"eveningAt\": null\n      }\n    ]",
            with: "\"eveningAt\": null\n      },\n      {\"date\": \"2026-09-21\", \"morning\": false, \"evening\": false, "
                + "\"morningAt\": null, \"eveningAt\": null}\n    ]")
        #expect(file != original)
        let database = try AppDatabase.inMemory()
        let envelope = try BackupImporter(database: database, content: try RepoFile.content).importBackup(Data(file.utf8))
        #expect(envelope.adhkar?.history.map(\.date) == ["2026-09-22", "2026-09-21"])

        #expect(try database.adhkar.days(from: "2026-09-21", through: "2026-09-21") == [])
        #expect(try dump(database) == dump(try imported(athkarFile)))
        let exported = try BackupExporter(database: database).export(
            app: .athkarPWA, today: "2026-09-23", timeZone: "Asia/Riyadh", exportedAt: envelope.meta.exportedAt)
        #expect(exported.adhkar?.history.map(\.date) == ["2026-09-22"])
    }

    enum Rejection: Sendable {
        case format(Int)
        case invalid(String)
        case malformed
    }

    /// Each case edits one example file so that tools/backup-validate.mjs rejects it.
    static let rejections: [(name: String, file: String, edits: [(String, String)], expected: Rejection)] = [
        ("future format", ruqyahFile, [(#""format": 1"#, #""format": 2"#)], .format(2)),
        ("not a calendar date", ruqyahFile, [(#""2026-09-21": {"#, #""2026-02-30": {"#)],
         .invalid("ruqyah.history.2026-02-30")),
        ("not a real instant", ruqyahFile, [("2026-09-21T05:10:00.000Z", "2026-09-21T24:10:00.000Z")], .malformed),
        ("unknown app", ruqyahFile, [(#""app": "ruqyah-pwa""#, #""app": "other""#)], .malformed),
        ("truncated JSON", ruqyahFile, [("}\n}", "}")], .malformed),
        ("non-finite count", athkarFile, [(#""morning-20": 250"#, #""morning-20": 1e400"#)], .malformed),
        // additionalProperties: false, at every depth.
        ("unknown top-level key", ruqyahFile, [(#""meta": {"#, #""extra": 1, "meta": {"#)], .invalid("extra")),
        ("unknown meta key", athkarFile, [(#""format": 1,"#, #""format": 1, "device": "x","#)],
         .invalid("meta.device")),
        ("unknown preferences key", athkarFile, [(#""haptics": false,"#, #""haptics": false, "font": "x","#)],
         .invalid("preferences.font")),
        ("unknown history entry key", athkarFile, [(#""eveningAt": null"#, #""eveningAt": null, "note": "x""#)],
         .invalid("adhkar.history[0].note")),
        ("unknown location key", athkarFile, [(#""longitude": 39.8262,"#, #""longitude": 39.8262, "accuracy": 5,"#)],
         .invalid("reminders.location.accuracy")),
        ("unknown ruqyah history key", ruqyahFile,
         [(#""completedAt": "2026-09-21T05:10:00.000Z""#, #""completedAt": "2026-09-21T05:10:00.000Z", "by": 1"#)],
         .invalid("ruqyah.history.2026-09-21.by")),
        // Sections per meta.app.
        ("ruqyah section in athkar file", athkarFile,
         [(#""reminders": {"#, #""ruqyah": {"today": {"date": "2026-09-23", "counts": {}}, "history": {}}, "reminders": {"#)],
         .invalid("ruqyah")),
        ("reminders in ruqyah file", ruqyahFile,
         [(#""preferences": {"#, #""reminders": {"morning": {"enabled": false}, "evening": {"enabled": false}, "#
           + #""calculationMethod": "mwl", "asrSchool": "standard", "lastShown": {"morning": null, "evening": null}}, "#
           + #""preferences": {"#)],
         .invalid("reminders")),
        ("adhkar in ruqyah file", athkarFile, [(#""app": "athkar-pwa""#, #""app": "ruqyah-pwa""#)], .invalid("adhkar")),
        ("athkar file without adhkar", ruqyahFile, [(#""app": "ruqyah-pwa""#, #""app": "athkar-pwa""#)],
         .invalid("adhkar")),
        ("longOrder in ruqyah file", ruqyahFile, [(#""haptics": true"#, #""haptics": true, "longOrder": "last""#)],
         .invalid("preferences.longOrder")),
        ("athkar file without longOrderPromptAnswered", athkarFile,
         [("\"longOrder\": \"last\",\n    \"longOrderPromptAnswered\": true", #""longOrder": "last""#)],
         .invalid("preferences.longOrderPromptAnswered")),
        // Envelope v1 carries only the PWA's five methods; the Adhan-only presets are native settings.
        ("native-only calculation method", athkarFile,
         [(#""calculationMethod": "umm-al-qura""#, #""calculationMethod": "dubai""#)],
         .invalid("reminders.calculationMethod")),
        // History relative to today.
        ("adhkar history on today", athkarFile, [(#""date": "2026-09-22""#, #""date": "2026-09-23""#)],
         .invalid("adhkar.history[0].date")),
        ("adhkar history after today", athkarFile, [(#""date": "2026-09-22""#, #""date": "2026-09-30""#)],
         .invalid("adhkar.history[0].date")),
        ("adhkar history not newest first", athkarFile,
         [(#""history": ["#, #""history": [{"date": "2026-09-20", "morning": true, "evening": true, "#
           + #""morningAt": null, "eveningAt": null},"#)],
         .invalid("adhkar.history[1].date")),
        ("ruqyah history after today", ruqyahFile, [(#""2026-09-22": {"#, #""2026-09-24": {"#)],
         .invalid("ruqyah.history.2026-09-24")),
        // Counts and targets beyond Number.MAX_SAFE_INTEGER.
        ("huge progress", athkarFile, [(#""morning-20": 250"#, #""morning-20": 9007199254740993"#)],
         .invalid("adhkar.today.progress.morning.morning-20")),
        ("huge target", athkarFile, [(#""morning-20": 10"#, #""morning-20": 1e300"#)],
         .invalid("adhkar.today.targets.morning.morning-20")),
        ("huge ruqyah count", ruqyahFile, [(#""nas-1-6": 3"#, #""nas-1-6": 9007199254740993"#)],
         .invalid("ruqyah.today.counts.nas-1-6")),
    ]

    @Test(arguments: rejections.indices)
    func rejectedFileChangesNothing(index: Int) throws {
        let (name, path, edits, expected) = Self.rejections[index]
        let original = String(decoding: try RepoFile.data(path), as: UTF8.self)
        let file = edits.reduce(original) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        #expect(file != original, "\(name): edit did not apply")

        // A database holding the other file's data and native rows must come out byte-identical.
        let database = try imported(path == athkarFile ? ruqyahFile : athkarFile)
        try database.adhkar.setCount(1, for: "evening-01", on: "2026-09-24", period: .evening)
        let before = try dump(database)
        let error = #expect(throws: BackupError.self, "\(name)") {
            try BackupImporter(database: database, content: try RepoFile.content).importBackup(Data(file.utf8))
        }
        switch (expected, error) {
        case let (.format(format), .unsupportedFormat(actual)?):
            #expect(actual == format, "\(name)")
        case let (.invalid(expectedPath), .invalid(actualPath, _)?):
            #expect(actualPath == expectedPath, "\(name)")
        case (.malformed, .malformed?):
            break
        default:
            Issue.record("\(name): expected \(expected), got \(String(describing: error))")
        }
        #expect(try dump(database) == before, "\(name)")
    }
}
