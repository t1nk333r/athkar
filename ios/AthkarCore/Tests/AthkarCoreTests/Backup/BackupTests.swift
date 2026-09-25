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

/// `count` consecutive dates, newest first, starting at `newest`.
private func consecutiveDates(from newest: String, count: Int) -> [String] {
    let start = Instant.at("\(newest)T00:00:00.000Z")
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return (0..<count).map { formatter.string(from: start.addingTimeInterval(-86_400 * Double($0))) }
}

/// An edit of the athkar example that appends `count` complete days after its one history entry (2026-09-22).
private func adhkarHistory(adding count: Int) -> (String, String) {
    let entries = consecutiveDates(from: "2026-09-21", count: count).map {
        #"{"date": "\#($0)", "morning": true, "evening": false, "morningAt": null, "eveningAt": null}"#
    }
    return ("\"eveningAt\": null\n      }\n    ]", "\"eveningAt\": null\n      }, \(entries.joined(separator: ", "))]")
}

/// An edit of the ruqyah example that adds `count` completed days before its two (2026-09-21, 2026-09-22).
private func ruqyahHistory(adding count: Int) -> (String, String) {
    let entries = consecutiveDates(from: "2026-09-20", count: count).map {
        #""\#($0)": {"completedAt": "\#($0)T05:00:00.000Z"}"#
    }
    return (#""history": {"#, #""history": {"# + entries.joined(separator: ", ") + ", ")
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

    /// spec/schema.md merge rules: on an origin tie the existing settings row stays, so a second file from the
    /// same PWA does not replace the first one's preferences or calculation profile.
    @Test(arguments: [
        (athkarFile, [(#""calculationMethod": "umm-al-qura""#, #""calculationMethod": "karachi""#),
                      (#""theme": "dark""#, #""theme": "light""#)]),
        (ruqyahFile, [(#""theme": "light""#, #""theme": "system""#), (#""haptics": true"#, #""haptics": false"#)]),
    ])
    func sameOriginImportKeepsTheExistingSettings(path: String, edits: [(String, String)]) throws {
        let database = try imported(path)
        let before = try dump(database)
        let original = String(decoding: try RepoFile.data(path), as: UTF8.self)
        let file = edits.reduce(original) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        #expect(file != original)
        try BackupImporter(database: database, content: try RepoFile.content).importBackup(Data(file.utf8))
        #expect(try dump(database) == before)
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
        // List sizes: adhkar history holds at most 7 days, ruqyah history at most 365.
        ("8 adhkar history entries", athkarFile, [adhkarHistory(adding: 7)], .invalid("adhkar.history")),
        ("366 ruqyah history entries", ruqyahFile, [ruqyahHistory(adding: 364)], .invalid("ruqyah.history")),
        // No optional section or key allows null (Codable alone reads null as absent).
        ("null ruqyah section in athkar file", athkarFile, [(#""reminders": {"#, #""ruqyah": null, "reminders": {"#)],
         .invalid("ruqyah")),
        ("null adhkar section in ruqyah file", ruqyahFile,
         [(#""preferences": {"#, #""adhkar": null, "reminders": null, "preferences": {"#)], .invalid("adhkar")),
        ("null location", athkarFile,
         [("\"location\": {\n      \"latitude\": 21.4225,\n      \"longitude\": 39.8262,\n"
            + "      \"updatedAt\": \"2026-09-23T17:38:40.481Z\"\n    }", #""location": null"#)],
         .invalid("reminders.location")),
        ("null longOrder in ruqyah file", ruqyahFile, [(#""haptics": true"#, #""haptics": true, "longOrder": null"#)],
         .invalid("preferences.longOrder")),
        // JSON.parse keeps the last of duplicate keys.
        ("duplicate key, last invalid", ruqyahFile, [(#""theme": "light""#, #""theme": "light", "theme": "bogus""#)],
         .malformed),
        // SQLite would store an ID truncated at U+0000.
        ("U+0000 in an item ID", athkarFile, [(#""morning-01": 1"#, #""morning-01": 1, "a\u0000b": 1"#)],
         .invalid("adhkar.today.progress.morning.a\u{0}b")),
        ("U+0000 as a segment ID", ruqyahFile, [(#""nas-1-6": 3"#, #""nas-1-6": 3, "\u0000": 0"#)],
         .invalid("ruqyah.today.counts.\u{0}")),
        // Proleptic Gregorian: 100 is not a leap year.
        ("0100-02-29", athkarFile, [(#""morning": "2026-09-22""#, #""morning": "0100-02-29""#)],
         .invalid("reminders.lastShown.morning")),
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

    /// Shapes tools/backup-validate.mjs accepts that `JSONDecoder` alone would reject or read differently.
    static let acceptances: [(name: String, file: String, edits: [(String, String)])] = [
        ("duplicate key, last valid", ruqyahFile, [(#""format": 1"#, #""format": 2, "format": 1"#)]),
        ("duplicate app, last valid", athkarFile, [(#""app": "athkar-pwa""#, #""app": "other", "app": "athkar-pwa""#)]),
        ("number below the Double range", athkarFile, [(#""morning-01": 1"#, #""morning-01": 1e-400"#)]),
        ("lone surrogate escape", ruqyahFile, [(#""timeZone": "Asia/Riyadh""#, #""timeZone": "\ud800""#)]),
        ("years 0000-0099", athkarFile,
         [(#""morning": "2026-09-22""#, #""morning": "0000-02-29""#), (#""date": "2026-09-22""#, #""date": "0099-12-31""#),
          ("2026-09-22T17:38:40.481Z", "0001-01-01T00:00:00.000Z")]),
        ("date-shaped strings outside date fields", athkarFile,
         [(#""timeZone": "Asia/Riyadh""#, #""timeZone": "2026-02-30""#), (#""morning-01": 1"#, #""2026-02-30": 1"#)]),
        ("7 adhkar history entries", athkarFile, [adhkarHistory(adding: 6)]),
        ("365 ruqyah history entries", ruqyahFile, [ruqyahHistory(adding: 363)]),
    ]

    @Test(arguments: acceptances.indices)
    func acceptedFileImports(index: Int) throws {
        let (name, path, edits) = Self.acceptances[index]
        let original = String(decoding: try RepoFile.data(path), as: UTF8.self)
        let file = edits.reduce(original) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        #expect(file != original, "\(name): edit did not apply")
        let database = try AppDatabase.inMemory()
        #expect(throws: Never.self, "\(name)") {
            try BackupImporter(database: database, content: try RepoFile.content).importBackup(Data(file.utf8))
        }
    }

    @Test func duplicateKeysKeepTheLastValue() throws {
        let file = String(decoding: try RepoFile.data(athkarFile), as: UTF8.self)
            .replacingOccurrences(of: #""morning-01": 1"#, with: #""morning-01": 7, "morning-01": 1e-400"#)
        let envelope = try BackupEnvelope.decode(Data(file.utf8))
        #expect(envelope.adhkar?.today.progress.morning["morning-01"] == 0)
    }

    /// envelope-v1.md: one UTF-8 JSON document. Foundation would sniff and accept UTF-16.
    @Test func nonUTF8FileIsRejected() throws {
        let text = String(decoding: try RepoFile.data(ruqyahFile), as: UTF8.self)
        let parts = text.components(separatedBy: "Asia/Riyadh")
        let invalidByte = Data(parts[0].utf8) + Data("Asia/Riyadh".utf8) + Data([0xFF]) + Data(parts[1].utf8)
        #expect(throws: BackupError.malformed("not UTF-8")) { try BackupEnvelope.decode(invalidByte) }
        // ASCII in UTF-16 is valid UTF-8 with NUL bytes between the characters: not JSON.
        for data in [text.data(using: .utf16LittleEndian)!, text.data(using: .utf16)!] {
            let error = #expect(throws: BackupError.self) { try BackupEnvelope.decode(data) }
            guard case .malformed? = error else { Issue.record("\(String(describing: error))"); continue }
        }
    }
}

struct BackupExportLimitTests {
    /// The ruqyah PWA keeps a year of history; envelope v1 allows at most 365 days.
    @Test func ruqyahHistoryExportsTheNewest365Days() throws {
        let database = try AppDatabase.inMemory()
        let days = consecutiveDates(from: "2026-09-23", count: 367)
        for day in days {
            try database.ruqyah.markComplete(on: day, completedAt: Instant.at("\(day)T05:00:00.000Z"))
        }
        let envelope = try BackupExporter(database: database).export(
            app: .ruqyahPWA, today: "2026-09-22", timeZone: "Asia/Riyadh")
        #expect(try #require(envelope.ruqyah).history.keys.sorted() == Array(days[1...365].reversed()))
    }
}
