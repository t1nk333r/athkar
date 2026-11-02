import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

/// Slice 7, migration and privacy: the routes (spec/routes.md), «تصدير نسخة احتياطية», a backup restored from
/// «استيراد من تطبيق الويب», «حول التطبيق», and what the sections read back after «حذف كل البيانات».
final class MigrationPrivacyTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let nativeFile = "spec/backup/examples/native.athkarbackup"
    private static let athkarFile = "spec/backup/examples/athkar-pwa.athkarbackup"
    private static let ruqyahFile = "spec/backup/examples/ruqyah-pwa.athkarbackup"

    private static func data(_ path: String) throws -> Data {
        try Data(contentsOf: repo.appendingPathComponent(path))
    }

    // MARK: Routes

    func testURLsNameTheirRoutes() throws {
        for route in AppRoute.allCases {
            XCTAssertEqual(AppRoute(url: route.url), route)
            XCTAssertEqual(route.url.absoluteString, "athkar://\(route.rawValue)")
        }
        let read: [(String, AppRoute?)] = [
            ("athkar://morning", .morning), ("ATHKAR://Evening", .evening), ("athkar:///ruqyah", .ruqyah),
            ("athkar:prayers", .prayers), ("athkar://morning?x=1#y", .morning), ("athkar://morning/", .morning),
            ("athkar://suwar", nil), ("athkar://", nil), ("athkar://morning/evening", nil),
            ("athkar://morning/x", nil), ("https://morning", nil), ("file:///tmp/morning", nil),
        ]
        for (text, route) in read {
            XCTAssertEqual(AppRoute(url: try XCTUnwrap(URL(string: text))), route, text)
        }
    }

    func testQuickActionsAndAdhkarRemindersNameTheirRoutes() {
        for route in AppRoute.allCases {
            XCTAssertEqual(AppRoute(shortcutType: route.shortcutType), route)
        }
        XCTAssertNil(AppRoute(shortcutType: "athkar.route.suwar"))
        XCTAssertNil(AppRoute(shortcutType: "morning"))
        XCTAssertEqual(AppRoute(reminder: ReminderPayload(ruleId: "adhkar_morning",
                                                          requestId: "adhkar.morning.2026-10-14")), .morning)
        XCTAssertEqual(AppRoute(reminder: ReminderPayload(ruleId: "adhkar_evening",
                                                          requestId: "adhkar.evening.2026-10-14")), .evening)
        XCTAssertNil(AppRoute(reminder: ReminderPayload(ruleId: "prayer_isha", requestId: "prayer.isha.2026-10-14")),
                     "a prayer reminder opens أوقات الصلاة, not a route")
        XCTAssertNil(AppRoute(reminder: ReminderPayload(ruleId: nil, requestId: nil)))
        XCTAssertEqual(AppRoute.allCases.map(\.deck), [.morning, .evening, .ruqyah, nil])
    }

    /// spec/routes.md's table, `AppRoute` and the Info.plist entries in ios/project.yml list the same routes, in the
    /// same order, with the same URLs, quick-action types and titles.
    func testTheRouteTableMatchesTheCodeAndInfoPlist() throws {
        let table = try String(decoding: Self.data("spec/routes.md"), as: UTF8.self)
        let rows = table.split(separator: "\n").filter { $0.hasPrefix("| `") }.map { line in
            line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        XCTAssertEqual(rows.map { $0[0] }, AppRoute.allCases.map { "`\($0.rawValue)`" })
        XCTAssertEqual(rows.map { $0[1] }, AppRoute.allCases.map { "`\($0.url.absoluteString)`" })
        XCTAssertEqual(rows.map { $0[2] }, AppRoute.allCases.map { "`\($0.shortcutType)`" })
        let titles = rows.map { $0[3] }
        XCTAssertEqual(titles, ["أذكار الصباح", "أذكار المساء", "رقية القرين", "سجّل الصلاة"])

        let project = try String(decoding: Self.data("ios/project.yml"), as: UTF8.self)
        let lines = project.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        func values(_ key: String) -> [String] {
            lines.filter { $0.hasPrefix(key) }.map { String($0.dropFirst(key.count)) }
        }
        XCTAssertEqual(values("- UIApplicationShortcutItemType: "), AppRoute.allCases.map(\.shortcutType))
        XCTAssertEqual(values("UIApplicationShortcutItemTitle: "), titles)
        XCTAssertEqual(values("CFBundleURLSchemes: "), ["[\(AppRoute.scheme)]"])
    }

    // MARK: Export

    /// The exported file is the format 2 file of what is stored, named after the local date; the location only when
    /// «تضمين الموقع» is on, which it is not when the screen opens. Clearing removes the temporary file.
    @MainActor
    func testExportWritesTheFormat2FileOfWhatIsStored() throws {
        let support = try PortableTestSupport()
        let example = try NativeBackup.decode(Self.data(Self.nativeFile))
        try BackupImporter(database: support.database, content: support.content.packs).importNative(example)
        try support.database.location.save(LocationProfile(latitude: 24.71, longitude: 46.68, zoneId: "Asia/Riyadh",
                                                           source: .manual, updatedAt: nil))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let riyadh = try XCTUnwrap(TimeZone(identifier: example.meta.timeZone))
        let model = BackupExportModel(exporter: BackupExporter(database: support.database),
                                      now: { example.meta.exportedAt }, timeZone: riyadh, directory: directory)
        XCTAssertFalse(model.includesLocation)

        XCTAssertTrue(model.export())
        let url = try XCTUnwrap(model.file?.url)
        XCTAssertEqual(url.lastPathComponent, "athkar-backup-2026-10-31.athkarbackup")
        XCTAssertEqual(try NativeBackup.decode(Data(contentsOf: url)), example, "no location without the switch")

        model.includesLocation = true
        XCTAssertTrue(model.export())
        let withLocation = try NativeBackup.decode(Data(contentsOf: XCTUnwrap(model.file?.url)))
        XCTAssertEqual(withLocation.reminders.location?.latitude, 24.71)
        XCTAssertEqual(withLocation.reminders.location?.longitude, 46.68)
        XCTAssertNil(model.error)

        model.clear()
        XCTAssertNil(model.file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(BackupExportModel.fileName(at: example.meta.exportedAt, in: TimeZone(identifier: "UTC")!),
                       "athkar-backup-2026-10-31.athkarbackup")
    }

    // MARK: Restore

    /// The app's sections over the support database, and the import that reloads them as `AppModel` does.
    @MainActor
    private struct Sections {
        let support: PortableTestSupport
        let settings: SettingsModel
        let ruqyah: RuqyahDeckModel
        let suwar: SuwarDeckModel
        let tasbih: TasbihModel
        let model: TransferImportModel

        init(_ support: PortableTestSupport) throws {
            self.support = support
            settings = try SettingsModel(repository: support.database.settings,
                                         report: { XCTFail("Production database write failed: \($0)") })
            ruqyah = try support.makeRuqyah()
            suwar = try support.makeSuwar()
            tasbih = try support.makeTasbih()
            let outline = support.content.suwar.suwar.map {
                SuwarOutline(id: $0.id, name: $0.surah, pageIDs: $0.pages.map(\.id))
            }
            let importer = TransferImporter(database: support.database, collections: support.content.packs.adhkar,
                                            suwar: outline)
            let backups = BackupImporter(database: support.database, content: support.content.packs)
            let (settings, ruqyah, suwar, tasbih) = (settings, ruqyah, suwar, tasbih)
            model = TransferImportModel(importer: importer, backupImporter: backups, today: { support.today },
                                        applied: {
                                            settings.reload()
                                            ruqyah.reload()
                                            suwar.reload()
                                            tasbih.reload()
                                        })
        }
    }

    /// A format 2 file is reviewed from a dry run, restored on confirmation, and reads as nothing new the second time.
    @MainActor
    func testANativeBackupIsReviewedRestoredAndThenHasNothingNew() throws {
        let support = try PortableTestSupport()
        let sections = try Sections(support)
        let model = sections.model
        let file = try Self.data(Self.nativeFile)

        model.open(fileData: file)
        XCTAssertEqual(model.screen, .review)
        let preview = try XCTUnwrap(model.preview)
        XCTAssertTrue(preview.isBackup)
        XCTAssertFalse(preview.isEmpty)
        XCTAssertEqual(preview.confirmTitle, "استعادة النسخة")
        XCTAssertEqual(preview.rows.map(\.title), ["أذكار الصباح والمساء", "رقية القرين", "قراءة السور", "المسبحة",
                                                   "سجل الصلوات", "التذكيرات", "الإعدادات"])
        XCTAssertEqual(preview.rows.map(\.detail), ["٥ أوراد", "يومان", "يومان", "يومان", "٦ صلوات", "تذكيران",
                                                    "١٤ إعدادًا"])
        XCTAssertFalse(try support.database.hasUserData(), "the review wrote nothing")

        model.confirm()
        XCTAssertEqual(model.screen, .result)
        XCTAssertEqual(model.outcome, .init(succeeded: true, title: "استُعيدت النسخة الاحتياطية",
                                            message: "يظهر ما استُعيد الآن في أقسامه.", isBackup: true))
        XCTAssertTrue(model.wrote)
        let restored = try BackupExporter(database: support.database).exportNative(
            timeZone: "Asia/Riyadh", exportedAt: NativeBackup.decode(file).meta.exportedAt, includeLocation: true)
        XCTAssertEqual(restored, try NativeBackup.decode(file))
        let example = try NativeBackup.decode(file)
        XCTAssertEqual(sections.tasbih.target, example.tasbih.target ?? 33)

        model.open(fileData: file)
        XCTAssertEqual(model.screen, .review)
        XCTAssertEqual(model.preview?.isEmpty, true)
        XCTAssertEqual(model.preview?.lead, "لا جديد")
    }

    /// The ruqyah PWA's backup is restored whole here (the transfer path refuses it); the athkar PWA's keeps the
    /// transfer review, with its warning.
    @MainActor
    func testBothPWABackupsImport() throws {
        let support = try PortableTestSupport()
        let model = try Sections(support).model

        model.importFile(try Self.data(Self.ruqyahFile))
        XCTAssertEqual(model.screen, .review)
        XCTAssertEqual(model.preview?.isBackup, true)
        XCTAssertEqual(model.preview?.rows.first?.title, "رقية القرين")
        model.confirm()
        XCTAssertEqual(model.outcome?.succeeded, true)
        XCTAssertGreaterThan(try support.database.ruqyah.counts(on: "2026-09-23")["qaf-23-29"] ?? 0, 0)

        model.back()
        model.importFile(try Self.data(Self.athkarFile))
        XCTAssertEqual(model.screen, .review)
        XCTAssertEqual(model.preview?.isBackup, false)
        XCTAssertTrue(model.preview?.warnings.contains(
            "هذا ملف نسخة احتياطية، فيه أذكار الصباح والمساء وسجلها فقط، وليس فيه المسبحة ولا قراءة السور.") == true)
        model.confirm()
        XCTAssertEqual(model.outcome?.succeeded, true)
    }

    /// A damaged format 2 file and a later format are reported as backups, and nothing is written.
    @MainActor
    func testADamagedOrLaterBackupIsExplained() throws {
        let support = try PortableTestSupport()
        let model = try Sections(support).model
        let text = try String(decoding: Self.data(Self.nativeFile), as: UTF8.self)

        model.open(fileData: Data(text.replacingOccurrences(of: "\"athkar-native\"", with: "\"other\"").utf8))
        XCTAssertEqual(model.screen, .result)
        XCTAssertEqual(model.outcome?.title, "نسخة احتياطية تالفة")
        XCTAssertEqual(model.outcome?.isBackup, true)

        let later = Data(text.replacingOccurrences(of: "\"format\": 2", with: "\"format\": 3").utf8)
        model.open(fileData: later)
        XCTAssertEqual(model.screen, .result)
        XCTAssertEqual(model.outcome?.title, "إصدار أحدث")
        // Chosen on the receive screen, the same file is explained under the button.
        model.back()
        model.importFile(later)
        XCTAssertEqual(model.screen, .receive)
        XCTAssertEqual(model.fileError, "أُنشئت هذه النسخة بإصدار أحدث من التطبيق. حدّث هذا التطبيق ثم أعد المحاولة.")
        XCTAssertFalse(try support.database.hasUserData())
    }

    // MARK: «حذف كل البيانات»

    /// After the tables are emptied, the sections read the defaults back: «مسبحة»'s target and phrase, the selected
    /// sura and the day's progress.
    @MainActor
    func testSectionsReadTheDefaultsBackAfterDeleteAll() throws {
        let support = try PortableTestSupport()
        let sections = try Sections(support)
        sections.model.open(fileData: try Self.data(Self.nativeFile))
        sections.model.confirm()
        try support.database.settings.set(99, for: .tasbihTarget)
        sections.tasbih.reload()
        XCTAssertEqual(sections.tasbih.target, 99)

        try support.database.deleteAllUserData()
        sections.settings.reload()
        sections.ruqyah.reload()
        sections.suwar.reload()
        sections.tasbih.reload()
        XCTAssertEqual(sections.tasbih.target, 33)
        XCTAssertEqual(sections.tasbih.selected, TasbihText.presets[0].id)
        XCTAssertTrue(sections.tasbih.custom.isEmpty)
        XCTAssertEqual(sections.suwar.selectedSuraID, support.content.suwar.suwar.first?.id)
        XCTAssertEqual(sections.settings.theme, .system)
        XCTAssertFalse(try support.database.hasUserData())
    }

    // MARK: «حول التطبيق»

    func testAboutListsTheVersionAndEachInstalledPack() throws {
        let support = try PortableTestSupport()
        let report = AboutReport(installs: try support.database.contentInstalls.installs(),
                                 info: ["CFBundleShortVersionString": "1.3", "CFBundleVersion": "4"])
        XCTAssertEqual(report.versions.map(\.id), ["appVersion", "content.adhkar", "content.ruqyah", "content.suwar"])
        XCTAssertEqual(report.versions.first?.value, "1.3 (4)")
        XCTAssertEqual(report.versions.dropFirst().map(\.value),
                       support.content.manifest.packs.keys.sorted().map { support.content.manifest.packs[$0]!.version })
        XCTAssertEqual(report.sources.map(\.id), ["adhkar", "quran", "fonts", "prayerTimes", "prohibitedTimes"])
        XCTAssertTrue(report.sources.first { $0.id == "prohibitedTimes" }?.value.contains("١٠٦٩٣") == true)
        // The edition named is the packs' own.
        for pack in ["content/ruqyah.v1.json", "content/suwar.v1.json"] {
            let json = try JSONSerialization.jsonObject(with: Self.data(pack)) as? [String: Any]
            XCTAssertEqual(json?["edition"] as? String, AboutReport.quranEdition, pack)
        }
    }
}
