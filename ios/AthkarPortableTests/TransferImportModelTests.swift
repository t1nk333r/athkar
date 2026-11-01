import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

/// «استيراد من تطبيق الويب» (NATIVE_APP_PLAN.md §6.4): a code pasted, chosen as a file or scanned is previewed with
/// the athkar PWA's wording, written only once confirmed, and shown at once in the sections it touched.
final class TransferImportModelTests: XCTestCase {
    private static let exportedAt = "2026-10-14T05:00:00.000Z"
    private static let now = ISO8601DateFormatter().date(from: "2026-10-14T06:00:00Z")!
    private static let yesterday = "2026-10-13"

    /// The app's sections over the support database, and the import that reloads them as `AppModel` does.
    @MainActor
    private struct Sections {
        let support: PortableTestSupport
        let settings: SettingsModel
        let adhkar: AdhkarSessionModel
        let suwar: SuwarDeckModel
        let tasbih: TasbihModel
        let model: TransferImportModel

        init(_ support: PortableTestSupport) throws {
            self.support = support
            settings = try SettingsModel(repository: support.database.settings,
                                         report: { XCTFail("Production database write failed: \($0)") })
            adhkar = try support.makeAdhkar()
            suwar = try support.makeSuwar()
            tasbih = try support.makeTasbih()
            let collections = support.content.packs.adhkar
            let outline = support.content.suwar.suwar.map {
                SuwarOutline(id: $0.id, name: $0.surah, pageIDs: $0.pages.map(\.id))
            }
            let importer = TransferImporter(database: support.database, collections: collections, suwar: outline)
            let (settings, adhkar, suwar, tasbih) = (settings, adhkar, suwar, tasbih)
            model = TransferImportModel(importer: importer, today: { support.today }, now: { TransferImportModelTests.now },
                                        applied: {
                                            settings.reload()
                                            adhkar.reload(longAdhkarLast: settings.longOrder == .last)
                                            suwar.reload()
                                            tasbih.reload()
                                        })
        }
    }

    private func typical(today: String = "2026-10-14", yesterday: String = yesterday,
                         exportedAt: String = exportedAt) -> String {
        TransferTestCodes.typical(today: today, yesterday: yesterday, exportedAt: exportedAt)
    }

    private func morningTotal(_ support: PortableTestSupport) -> Int {
        support.content.packs.adhkar.morning.filter { !$0.review }.count
    }

    // MARK: Paste, review, import

    @MainActor
    func testAPastedCodeIsReviewedThenImportedAndShown() throws {
        let support = try PortableTestSupport()
        let sections = try Sections(support)
        let model = sections.model
        XCTAssertEqual(model.screen, .receive)
        XCTAssertFalse(model.canContinue)

        model.code = TransferTestCodes.text(typical())
        XCTAssertTrue(model.canContinue)
        model.continuePaste()
        XCTAssertEqual(model.screen, .review)
        let preview = try XCTUnwrap(model.preview)
        XCTAssertFalse(preview.isEmpty)
        XCTAssertFalse(preview.hasResets)
        XCTAssertEqual(preview.lead, "سيُضاف إلى هذا الجهاز:")
        XCTAssertTrue(preview.created?.hasPrefix("أُنشئ الرمز: ") == true)
        let total = ArabicFormat.number(morningTotal(support))
        XCTAssertEqual(preview.rows, [
            .init(title: "أذكار الصباح — اليوم", detail: "يصبح المكتمل ١ من \(total) بعد ٠، ويزيد عدّ ١ من الأذكار"),
            .init(title: "قراءة السور — اليوم", detail: "صفحتان مقروءتان جديدتان"),
            .init(title: "المسبحة — اليوم", detail: "يرتفع العدّ في ٢ من الأذكار، وتُضاف ١ من العبارات إلى «عباراتك»"),
            .init(title: "السجل", detail: "يوم واحد",
                  dates: ["\(ArabicFormat.shortDate(localDate: Self.yesterday)): الصباح، المساء، سورة الكهف، المسبحة"]),
            .init(title: "الإعدادات", detail: "تُطبَّق: المظهر"),
        ])
        XCTAssertEqual(preview.assurance,
                       "لن يُحذف شيء من هذا الجهاز ولن ينقص أي عدد. يُضاف ما ينقصه فقط، وتبقى إعداداتك الحالية كما هي.")
        XCTAssertEqual(preview.warnings, [])
        XCTAssertEqual(preview.confirmTitle, "إضافة التقدّم")
        // Nothing is written before the confirmation.
        XCTAssertTrue(try support.database.tasbih.counts(on: support.today).isEmpty)

        model.confirm()
        XCTAssertEqual(model.screen, .result)
        XCTAssertEqual(model.outcome?.succeeded, true)
        XCTAssertEqual(model.outcome?.title, "نُقل التقدّم إلى هذا الجهاز")
        XCTAssertTrue(model.wrote)
        XCTAssertEqual(model.code, "")
        // Each section shows what was written, without a relaunch.
        XCTAssertEqual(sections.adhkar.state.progress.morning["morning-01"], .number(1))
        XCTAssertEqual(sections.adhkar.state.progress.morning["morning-02"], .number(1))
        XCTAssertEqual(sections.suwar.readPages, ["mulk-1-4", "mulk-5-8"])
        XCTAssertTrue(sections.suwar.hasHistory)
        XCTAssertEqual(sections.tasbih.counts.map(\.count).sorted(), [7, 33])
        XCTAssertEqual(sections.tasbih.custom, ["يا حي يا قيوم"])
        XCTAssertTrue(sections.tasbih.hasHistory)
        XCTAssertEqual(sections.settings.theme, .dark)
    }

    @MainActor
    func testTheSameCodeAgainHasNothingNew() throws {
        let support = try PortableTestSupport()
        let model = try Sections(support).model
        model.code = TransferTestCodes.text(typical())
        model.continuePaste()
        model.confirm()
        model.back()
        model.code = TransferTestCodes.text(typical())
        model.continuePaste()
        let preview = try XCTUnwrap(model.preview)
        XCTAssertTrue(preview.isEmpty)
        XCTAssertEqual(preview.lead, "لا جديد")
        XCTAssertEqual(preview.assurance, "كل ما في الرمز موجود على هذا الجهاز بالفعل، فلا شيء لإضافته.")
        XCTAssertEqual(preview.rows, [])
        XCTAssertEqual(preview.confirmTitle, "تم")
    }

    /// A later reset on the other device replaces the unit here, and the review says so first.
    @MainActor
    func testANewerResetThereIsReviewedAsAChange() throws {
        let support = try PortableTestSupport()
        let sections = try Sections(support)
        // Counted here at 03:00, before the code's 04:00 morning reset.
        try support.database.adhkar.setCount(3, for: "morning-03", on: support.today, period: .morning,
                                             at: ISO8601DateFormatter().date(from: "2026-10-14T03:00:00Z")!)
        sections.model.code = TransferTestCodes.text(typical())
        sections.model.continuePaste()
        let preview = try XCTUnwrap(sections.model.preview)
        XCTAssertTrue(preview.hasResets)
        XCTAssertEqual(preview.lead, "سيتغيّر على هذا الجهاز:")
        XCTAssertEqual(preview.rows.first, .init(
            title: "أذكار الصباح — اليوم",
            detail: "سيُعاد ضبط تقدّم أذكار الصباح اليوم لأن إعادة الضبط على الجهاز الآخر أحدث. يصبح المكتمل ١ من \(ArabicFormat.number(morningTotal(support))) بدل ١.",
            isReset: true))
        XCTAssertTrue(preview.assurance.hasPrefix("أُعيد ضبط بعض التقدّم على الجهاز الآخر"))
        XCTAssertEqual(preview.confirmTitle, "تطبيق التغييرات")
        sections.model.confirm()
        XCTAssertEqual(sections.model.outcome?.succeeded, true)
        XCTAssertNil(sections.adhkar.state.progress.morning["morning-03"])
    }

    /// `confirmTransfer`: storage changed during the review, so the list is planned again and shown before anything
    /// is written.
    @MainActor
    func testSomethingRecordedDuringTheReviewRefreshesIt() throws {
        let support = try PortableTestSupport()
        let sections = try Sections(support)
        let model = sections.model
        model.code = TransferTestCodes.text(typical())
        model.continuePaste()
        try support.database.tasbih.setCount(40, for: "subhan", on: support.today, at: Self.now)
        model.confirm()
        XCTAssertEqual(model.screen, .review)
        XCTAssertTrue(model.refreshed)
        XCTAssertNil(model.outcome)
        XCTAssertEqual(try support.database.tasbih.counts(on: support.today).map(\.count), [40])
        XCTAssertTrue(model.preview?.rows.contains(.init(
            title: "المسبحة — اليوم", detail: "يرتفع العدّ في ١ من الأذكار، وتُضاف ١ من العبارات إلى «عباراتك»")) == true)
        model.confirm()
        XCTAssertEqual(model.outcome?.succeeded, true)
        XCTAssertEqual(try support.database.tasbih.counts(on: support.today).map(\.count).sorted(), [7, 40])
    }

    @MainActor
    func testACodeFromAnEarlierDayIsReviewedWithAWarning() throws {
        let support = try PortableTestSupport()
        let model = try Sections(support).model
        model.code = TransferTestCodes.text(typical(today: "2026-10-12", yesterday: "2026-10-11",
                                                     exportedAt: "2026-10-12T05:00:00.000Z"))
        model.continuePaste()
        XCTAssertEqual(model.preview?.warnings,
                       ["أُنشئ هذا الرمز أول أمس، فلا يحمل ما سُجّل على الجهاز الآخر بعد ذلك."])
        // Its days are history here; the saved phrase is added now.
        XCTAssertEqual(model.preview?.rows.map(\.title), ["المسبحة — اليوم", "السجل", "الإعدادات"])
        XCTAssertEqual(model.preview?.rows.first?.detail, "تُضاف ١ من العبارات إلى «عباراتك»")
        XCTAssertEqual(model.preview?.rows[1].detail, "يومان")
    }

    // MARK: Errors

    @MainActor
    func testCodesThatCannotBeReadAreExplained() throws {
        let support = try PortableTestSupport()
        let model = try Sections(support).model
        model.code = "hello"
        model.continuePaste()
        XCTAssertEqual(model.screen, .receive)
        XCTAssertEqual(model.pasteError, "هذا ليس رمز نقل من «أذكار المسلم». تأكد أنك نسخت الرمز من «إرسال التقدّم».")
        model.code = "hello!"
        XCTAssertNil(model.pasteError, "editing the field clears its error")

        model.code = String(repeating: "A", count: 65_537)
        model.continuePaste()
        XCTAssertEqual(model.pasteError, "النص أطول من أي رمز نقل. تأكد أنك لصقت الرمز وحده.")

        var damaged = TransferTestCodes.text(typical())
        damaged.replaceSubrange(damaged.index(damaged.startIndex, offsetBy: 40)...damaged.index(damaged.startIndex, offsetBy: 40),
                                with: damaged.dropFirst(40).first == "0" ? "1" : "0")
        model.code = damaged
        model.continuePaste()
        XCTAssertEqual(model.pasteError, "الرمز تالف أو ناقص. انسخه كاملًا من الجهاز الآخر وأعد المحاولة؛ بعض تطبيقات المراسلة تغيّر المسافات داخل الرمز، فالمشاركة كملف أضمن.")

        model.pasteUnavailable()
        XCTAssertEqual(model.pasteError, "اضغط مطولًا داخل الحقل واختر «لصق».")

        model.importFile(nil)
        XCTAssertEqual(model.fileError, "تعذّرت قراءة الملف. اختر ملف رمز النقل أو ملف نسخة احتياطية من «أذكار المسلم».")
        model.importFile(Data("{}".utf8))
        XCTAssertEqual(model.screen, .receive)
        XCTAssertNotNil(model.fileError)
    }

    /// A file opened in the app starts the sheet on its review, or on its error as a result.
    @MainActor
    func testAnOpenedFileStartsOnItsReviewOrError() throws {
        let support = try PortableTestSupport()
        let model = try Sections(support).model
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let ruqyah = try Data(contentsOf: repo.appendingPathComponent("spec/backup/examples/ruqyah-pwa.athkarbackup"))
        model.open(fileData: ruqyah)
        XCTAssertEqual(model.screen, .result)
        XCTAssertEqual(model.outcome, .init(succeeded: false, title: "رمز تطبيق آخر",
                                            message: "هذا رمز من تطبيق «رقية القرين»، وهذا التطبيق يستلم تقدّم «أذكار المسلم» فقط."))
        model.back()
        XCTAssertEqual(model.screen, .receive)

        model.open(fileData: Data(("\u{FEFF}" + TransferTestCodes.text(typical()) + "\n").utf8))
        XCTAssertEqual(model.screen, .review)
        XCTAssertEqual(model.preview?.lead, "سيُضاف إلى هذا الجهاز:")
    }

    @MainActor
    func testAnAthkarBackupFileIsReviewedWithItsWarning() throws {
        let support = try PortableTestSupport()
        let model = try Sections(support).model
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        model.importFile(try Data(contentsOf: repo.appendingPathComponent("spec/backup/examples/athkar-pwa.athkarbackup")))
        XCTAssertEqual(model.screen, .review)
        XCTAssertTrue(model.preview?.warnings.contains(
            "هذا ملف نسخة احتياطية، فيه أذكار الصباح والمساء وسجلها فقط، وليس فيه المسبحة ولا قراءة السور.") == true)
    }

    // MARK: Scan

    @MainActor
    func testScannedFramesAssembleInAnyOrder() throws {
        let support = try PortableTestSupport()
        let model = try Sections(support).model
        let frames = TransferTestCodes.frames(typical())
        XCTAssertGreaterThan(frames.count, 1)
        model.startScan()
        XCTAssertEqual(model.screen, .scan)
        XCTAssertEqual(model.scanLabel, "لم يُقرأ شيء بعد")

        XCTAssertFalse(model.scanned("https://example.com"))
        XCTAssertEqual(model.scanHint, "هذا رمز QR آخر. وجّه الكاميرا إلى رمز النقل في «إرسال التقدّم».")
        XCTAssertFalse(model.scanned(frames[1]))
        XCTAssertEqual(model.scanLabel, "قُرئ ١ من \(ArabicFormat.number(frames.count))")
        XCTAssertFalse(model.scanned(frames[1]), "a frame read twice counts once")
        XCTAssertEqual(model.scanRead, 1)
        model.scanStalled()
        XCTAssertEqual(model.scanHint, "لم تكتمل القراءة بعد. ارفع سطوع الشاشة الأخرى، وقرّب الجهاز أو أبعده قليلًا.")

        // Another code on the other screen: reading starts again.
        let other = TransferTestCodes.frames(typical(), msg: "OTHR")
        XCTAssertFalse(model.scanned(other[0]))
        XCTAssertEqual(model.scanHint, "تغيّر الرمز على الجهاز الآخر، فبدأت القراءة من جديد.")
        XCTAssertEqual(model.scanRead, 1)
        var finished = false
        for frame in other.dropFirst().reversed() { finished = model.scanned(frame) }
        XCTAssertTrue(finished)
        XCTAssertEqual(model.screen, .review)
    }

    @MainActor
    func testADamagedFrameEndsTheScan() throws {
        let support = try PortableTestSupport()
        let model = try Sections(support).model
        var frame = TransferTestCodes.frames(typical())[0]
        let index = frame.index(frame.startIndex, offsetBy: 20)
        frame.replaceSubrange(index...index, with: frame[index] == "0" ? "1" : "0")
        model.startScan()
        XCTAssertTrue(model.scanned(frame))
        XCTAssertEqual(model.screen, .result)
        XCTAssertEqual(model.outcome?.title, "رمز تالف")
        XCTAssertEqual(model.outcome?.message, "الرمز تالف أو ناقص. أعد المسح من البداية.")
    }

    // MARK: Wording

    @MainActor
    func testCountsFollowArabicPluralRules() {
        XCTAssertEqual([1, 2, 3, 10, 11, 99, 100, 103].map(TransferImportModel.days),
                       ["يوم واحد", "يومان", "٣ أيام", "١٠ أيام", "١١ يومًا", "٩٩ يومًا", "١٠٠ يوم", "١٠٣ أيام"])
        XCTAssertEqual([1, 2, 5, 12].map(TransferImportModel.newPages),
                       ["صفحة واحدة مقروءة جديدة", "صفحتان مقروءتان جديدتان", "٥ صفحات مقروءة جديدة",
                        "١٢ صفحةً مقروءةً جديدةً"])
        XCTAssertEqual([1, 2, 4, 20].map(TransferImportModel.lostPages), ["صفحة واحدة", "صفحتين", "٤ صفحات", "٢٠ صفحةً"])
        XCTAssertEqual([1, 2, 3, 11, 100].map(TransferImportModel.daysAgo),
                       ["أمس", "أول أمس", "قبل ٣ أيام", "قبل ١١ يومًا", "قبل ١٠٠ يوم"])
        XCTAssertEqual(TransferImportModel.list(["سورة الكهف", "سورة يس", "سورة الملك"]), "سورة الكهف وسورة يس وسورة الملك")
        XCTAssertEqual(TransferImportModel.dayDistance(from: "2026-02-27", to: "2026-03-02"), 3)
    }

    @MainActor
    func testEveryRefusalHasThePWAsWording() {
        let titles = [TransferError.Kind.notCode, .tooLong, .oneFrame, .wrongApp, .newer, .corrupt, .incomplete, .mixed,
                      .clock, .tooBig, .fileRead, .write].map { TransferImportModel.errorTitle(TransferError($0)) }
        XCTAssertEqual(titles, ["ليس رمز نقل", "ليس رمز نقل", "رمز ناقص", "رمز تطبيق آخر", "إصدار أحدث", "رمز تالف",
                                "رمز تالف", "رمز تالف", "رمز غير صالح", "يتجاوز ما يتسع له التطبيق", "تعذّرت قراءة الملف",
                                "تعذّر الحفظ"])
        XCTAssertEqual(TransferImportModel.errorText(TransferError(.tooBig), surface: .result),
                       "لا يتسع التطبيق لكل ما في الرمز من عبارات المسبحة وسجلها مع ما على هذا الجهاز، فلم يُنقل شيء ولم يتغيّر تقدّمك.")
        XCTAssertEqual(TransferImportModel.errorText(TransferError(.corrupt), surface: .scan),
                       "الرمز تالف أو ناقص. أعد المسح من البداية.")
    }
}
