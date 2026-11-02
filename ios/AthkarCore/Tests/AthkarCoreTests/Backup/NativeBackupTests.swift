import AthkarCore
import Foundation
import GRDB
import Testing

private let nativeFile = "spec/backup/examples/native.athkarbackup"
private let athkarFile = "spec/backup/examples/athkar-pwa.athkarbackup"
private let ruqyahFile = "spec/backup/examples/ruqyah-pwa.athkarbackup"

private func importer(_ database: AppDatabase) throws -> BackupImporter {
    BackupImporter(database: database, content: try RepoFile.content)
}

/// A fresh database with each file imported in order, read by `BackupFile` as the app reads them.
private func imported(_ paths: String...) throws -> AppDatabase {
    let database = try AppDatabase.inMemory()
    for path in paths {
        try importer(database).importFile(try BackupFile.decode(RepoFile.data(path)))
    }
    return database
}

private func exportNative(_ database: AppDatabase, like file: NativeBackup,
                          includeLocation: Bool = false) throws -> NativeBackup {
    try BackupExporter(database: database).exportNative(
        timeZone: file.meta.timeZone, exportedAt: file.meta.exportedAt, includeLocation: includeLocation)
}

/// spec/backup/envelope-v2.md.
struct NativeBackupRoundTripTests {
    @Test func exportAfterImportReproducesTheFile() throws {
        let data = try RepoFile.data(nativeFile)
        let file = try NativeBackup.decode(data)
        let database = try imported(nativeFile)
        let exported = try exportNative(database, like: file)
        #expect(exported == file)
        #expect(try JSONValue(data: exported.encoded()) == JSONValue(data: data))
    }

    /// Format 1 files imported on a fresh install come out in format 2 with their rows, and that file restores the
    /// same database on another fresh install (NATIVE_APP_PLAN.md §8.3).
    @Test func bothPWAFilesCarryOverIntoAFormat2Backup() throws {
        let original = try imported(athkarFile, ruqyahFile)
        let backup = try BackupExporter(database: original).exportNative(
            timeZone: "Asia/Riyadh", exportedAt: Instant.at("2026-09-24T08:00:00.000Z"), includeLocation: true)
        let restored = try AppDatabase.inMemory()
        try importer(restored).importFile(try BackupFile.decode(backup.encoded()))

        // Rows come back stamped with the export instant, and settings come back as native ones.
        let ignored: Set<String> = ["updated_at", "origin"]
        #expect(try columns(dump(restored), without: ignored) == columns(dump(original), without: ignored))
        #expect(try restored.settings.value(for: .theme) == .dark)
        #expect(try restored.ruqyah.counts(on: "2026-09-23")["qaf-23-29"] == 7)
        #expect(try restored.location.profile()?.latitude == 21.42)
    }

    @Test func encodedFileDecodesToItself() throws {
        let file = try NativeBackup.decode(RepoFile.data(nativeFile))
        #expect(try NativeBackup.decode(file.encoded()) == file)
        // Nullable keys are written, as null.
        let text = String(decoding: try file.encoded(), as: UTF8.self)
        #expect(text.contains(#""noonPrayer" : null"#))
        #expect(!text.contains(#""location""#))
    }

    @Test func locationIsExportedOnlyWhenIncludedRoundedAsStored() throws {
        let database = try imported(nativeFile)
        try database.location.save(LocationProfile(label: "مكة المكرمة", latitude: 21.42251, longitude: 39.82617,
                                                   zoneId: "Asia/Riyadh", source: .device, updatedAt: nil))
        let file = try NativeBackup.decode(RepoFile.data(nativeFile))
        #expect(try exportNative(database, like: file).reminders.location == nil)
        let location = try #require(try exportNative(database, like: file, includeLocation: true).reminders.location)
        #expect(location == .init(latitude: 21.42, longitude: 39.83, label: "مكة المكرمة", zoneId: "Asia/Riyadh",
                                  updatedAt: nil))
    }

    @Test func emptyDatabaseExportsEmptySections() throws {
        let backup = try BackupExporter(database: AppDatabase.inMemory()).exportNative(
            timeZone: "UTC", exportedAt: Instant.at("2026-10-31T00:00:00.000Z"))
        #expect(backup == NativeBackup(meta: .init(exportedAt: Instant.at("2026-10-31T00:00:00.000Z"),
                                                   timeZone: "UTC")))
        #expect(try JSONValue(data: backup.encoded())["preferences"] == .object([:]))
    }
}

/// Each table's rows as column → value, without the `ignored` columns.
private func columns(_ dump: [String: [Row]], without ignored: Set<String>) -> [String: [[String: DatabaseValue]]] {
    dump.mapValues { rows in
        rows.map { row in
            Dictionary(row.filter { !ignored.contains($0.0) }.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        }
    }
}

struct NativeBackupImportTests {
    @Test func reimportIsANoOp() throws {
        let database = try imported(nativeFile)
        let once = try dump(database)
        let summary = try importer(database).importFile(try BackupFile.decode(RepoFile.data(nativeFile)))
        #expect(summary.isEmpty)
        #expect(try dump(database) == once)
    }

    @Test func dryRunWritesNothingAndCountsWhatConfirmingWrites() throws {
        let database = try AppDatabase.inMemory()
        let file = try BackupFile.decode(RepoFile.data(nativeFile))
        let planned = try importer(database).importFile(file, dryRun: true)
        #expect(try dump(database) == dump(try AppDatabase.inMemory()))
        var expected = BackupImportSummary()
        expected.adhkar = 5
        expected.ruqyah = 2
        expected.suwar = 2
        expected.tasbih = 2
        expected.prayers = 6
        expected.reminders = 2
        expected.settings = 13
        #expect(planned == expected)
        #expect(try importer(database).importFile(file) == planned)
    }

    @Test func formatOneFilesStillImport() throws {
        for path in [athkarFile, ruqyahFile] {
            guard case let .pwa(envelope) = try BackupFile.decode(RepoFile.data(path)) else {
                Issue.record("\(path) did not read as format 1")
                continue
            }
            let viaFile = try AppDatabase.inMemory()
            let summary = try importer(viaFile).importFile(.pwa(envelope))
            #expect(!summary.isEmpty)
            let viaBackup = try AppDatabase.inMemory()
            try importer(viaBackup).importBackup(RepoFile.data(path))
            #expect(try dump(viaFile) == dump(viaBackup))
        }
    }

    @Test func deviceDataWins() throws {
        let database = try AppDatabase.inMemory()
        let native = Instant.at("2026-10-31T05:00:00.000Z")
        try database.adhkar.setCount(9, for: "morning-01", on: "2026-10-31", period: .morning, at: native)
        try database.suwar.markRead("kahf-9-12", of: "kahf", on: "2026-10-31", at: native)
        try database.tasbih.setCount(5, for: "hamd", on: "2026-10-31", at: native)
        try database.settings.set(.light, for: .theme, at: native)
        try database.reminders.save(ReminderRule.adhkar(.morning, enabled: false, updatedAt: native))
        let context = PrayerCommandContext(now: native, zone: TimeZone(identifier: "Asia/Riyadh")!,
                                           scheduledAt: nil, profileVersion: "mwl/standard/twilight-angle/0,0,0,0,0,0")
        // The device recorded Isha on 10-30, which the file leaves unrecorded; Fajr on 10-31 is the device's too.
        for occurrence in [PrayerOccurrence(date: "2026-10-30", prayer: .isha),
                           PrayerOccurrence(date: "2026-10-31", prayer: .fajr)] {
            try database.prayerRecords.apply(.record(), to: occurrence, context: context)
            try database.prayerRecords.apply(.setTiming(.onTime), to: occurrence, context: context)
        }

        try importer(database).importFile(try BackupFile.decode(RepoFile.data(nativeFile)))

        #expect(try database.adhkar.session(on: "2026-10-31", period: .morning).progress == ["morning-01": 9])
        #expect(try database.adhkar.session(on: "2026-10-31", period: .evening).progress.count == 2)
        #expect(try database.suwar.readPages(on: "2026-10-31") == ["kahf-9-12"])
        #expect(try database.suwar.readPages(on: "2026-10-30") == ["mulk-1-4", "mulk-5-8"])
        #expect(try database.tasbih.counts(on: "2026-10-31").map(\.phraseKey) == ["hamd"])
        #expect(try database.tasbih.counts(on: "2026-10-30").count == 3)
        #expect(try database.settings.value(for: .theme) == .light)
        #expect(try database.settings.value(for: .textSize) == .large)
        #expect(try database.reminders.rule(id: "adhkar_morning")?.enabled == false)
        #expect(try database.reminders.rule(id: "adhkar_evening")?.enabled == true)
        let records = try database.prayerRecords.records(from: "2026-10-30", through: "2026-10-31")
        #expect(records.first { $0.prayerKey == .isha }?.profileVersion == "mwl/standard/twilight-angle/0,0,0,0,0,0")
        #expect(records.first { $0.calculationDate == "2026-10-31" }?.timing == .onTime)
        #expect(records.first { $0.prayerKey == .dhuhr }?.noonPrayer == .jumuah)
    }

    /// A recorded prayer in the file fills a record the device holds as unrecorded.
    @Test func recordedPrayerReplacesAnUnrecordedOne() throws {
        let database = try AppDatabase.inMemory()
        let native = Instant.at("2026-10-30T02:00:00.000Z")
        let context = PrayerCommandContext(now: native, zone: TimeZone(identifier: "Asia/Riyadh")!,
                                           scheduledAt: nil, profileVersion: "mwl/standard/twilight-angle/0,0,0,0,0,0")
        let fajr = PrayerOccurrence(date: "2026-10-30", prayer: .fajr)
        try database.prayerRecords.apply(.record(), to: fajr, context: context)
        try database.prayerRecords.apply(.unrecord, to: fajr, context: context)
        #expect(try database.prayerRecords.records(on: "2026-10-30").first?.state == .unrecorded)

        try importer(database).importFile(try BackupFile.decode(RepoFile.data(nativeFile)))
        let record = try #require(try database.prayerRecords.records(on: "2026-10-30").first { $0.prayerKey == .fajr })
        #expect(record.state == .prayed)
        #expect(record.profileVersion == "umm-al-qura/standard/twilight-angle/0,0,0,0,0,0")
    }

    @Test func laterFormatIsReportedAsSuch() throws {
        let text = String(decoding: try RepoFile.data(nativeFile), as: UTF8.self)
            .replacingOccurrences(of: #""format": 2"#, with: #""format": 3"#)
        #expect(throws: BackupError.unsupportedFormat(3)) { try BackupFile.decode(Data(text.utf8)) }
    }

    /// Each case edits the example so that tools/backup-validate.mjs rejects it.
    static let rejections: [(name: String, edits: [(String, String)], path: String?)] = [
        ("unknown top-level key", [(#""meta": {"#, #""extra": 1, "meta": {"#)], "extra"),
        ("unknown row key", [(#""firstUse": 1"#, #""firstUse": 1, "note": "x""#)], "tasbih.counts[0].note"),
        ("null where not allowed", [(#""selected": "kahf""#, #""selected": null"#)], "suwar.selected"),
        ("missing section", [(#""prayers": {"#, #""prayerz": {"#)], nil),
        ("missing nullable key", [(#""timing": null,\#n        "noonPrayer": null,"#, #""timing": null,"#)], nil),
        ("wrong app", [(#""app": "athkar-native""#, #""app": "athkar-pwa""#)], "meta.app"),
        ("not a calendar date", [(#""date": "2026-10-29""#, #""date": "2026-02-30""#)], "adhkar.days[0].date"),
        ("repeated key", [(#""firstUse": 2"#, #""firstUse": 1"#)], "tasbih.counts[1]"),
        ("timing on an unrecorded record", [(#""state": "unrecorded",\#n        "timing": null"#,
                                             #""state": "unrecorded",\#n        "timing": "late""#)],
         "prayers.records[4].timing"),
        ("noon prayer on a Thursday", [(#""date": "2026-10-30",\#n        "prayer": "dhuhr""#,
                                        #""date": "2026-10-29",\#n        "prayer": "dhuhr""#)],
         "prayers.records[1].noonPrayer"),
        ("adjustment out of range", [(#""maghrib": 3"#, #""maghrib": 31"#)], "prayerSettings.adjustments.maghrib"),
        ("lastShown without a rule", [(#""adhkar_morning": "2026-10-31""#, #""adhkar_noon": "2026-10-31""#)],
         "reminders.lastShown.adhkar_noon"),
        ("U+0000 in an ID", [(#""pageId": "kahf-1-4""#, #""pageId": "kahf\u0000""#)], "suwar.pages[2].pageId"),
        ("count above the cap", [(#""count": 57"#, #""count": 100000"#)], "tasbih.counts[3].count"),
    ]

    @Test(arguments: rejections.indices)
    func rejectedFileChangesNothing(index: Int) throws {
        let (name, edits, path) = Self.rejections[index]
        let original = String(decoding: try RepoFile.data(nativeFile), as: UTF8.self)
        let file = edits.reduce(original) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        #expect(file != original, "\(name): edit did not apply")
        let database = try imported(athkarFile)
        let before = try dump(database)
        let error = #expect(throws: BackupError.self, "\(name)") {
            try importer(database).importFile(try BackupFile.decode(Data(file.utf8)))
        }
        switch error {
        case let .invalid(actualPath, _)? where path != nil:
            #expect(actualPath == path, "\(name)")
        case .malformed? where path == nil:
            break
        default:
            Issue.record("\(name): got \(String(describing: error))")
        }
        #expect(try dump(database) == before, "\(name)")
    }
}
