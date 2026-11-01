import AthkarCore
import Foundation
import Observation

/// «استيراد من تطبيق الويب»: the athkar PWA's «استلام التقدّم» on this device (NATIVE_APP_PLAN.md §6.4,
/// spec/transfer/transfer-v1.md §9). A code arrives pasted, as a file, or scanned frame by frame; it is decoded and
/// planned against the stores, previewed with the PWA's wording, and written only once confirmed. Nothing is written
/// before the confirmation, and the location is never imported.
@MainActor
@Observable
final class TransferImportModel: Identifiable {
    enum Screen: Equatable {
        /// «استلام التقدّم»: paste, file, camera.
        case receive
        /// «مسح رمز QR».
        case scan
        /// «المراجعة».
        case review
        /// «تمّ النقل» or «تعذّر النقل».
        case result
    }

    /// One line of the preview list: a title and its detail (with dated lines for «السجل»).
    struct Row: Equatable, Sendable {
        var title: String
        var detail: String
        var dates: [String] = []
        /// A unit the other device's newer reset replaces here.
        var isReset = false
        /// «يكتمل الورد ✓».
        var isComplete = false
    }

    /// The review screen (`transferPreviewMarkup`).
    struct Preview: Equatable, Sendable {
        /// «لا جديد»: the code has nothing this device lacks.
        var isEmpty: Bool
        var lead: String
        var created: String?
        var rows: [Row]
        /// The other device's newer resets replace some progress here.
        var hasResets: Bool
        /// The assurance (additions only), or the resets' explanation.
        var assurance: String
        var warnings: [String]
        var confirmTitle: String
    }

    struct Outcome: Equatable, Sendable {
        var succeeded: Bool
        var title: String
        var message: String
    }

    static let pasteHelp = "اضغط مطولًا داخل الحقل واختر «لصق»."
    static let undoNote = "لا يُنقل «التراجع»: إن تراجعت عن عدّة على أحد الجهازين، فلن ينقص العدّ على الجهاز الآخر بالنقل."
    static let refreshedNote = "تغيّر التقدّم على هذا الجهاز أثناء المراجعة، فحُدّثت القائمة. راجعها ثم أكّد."
    static let emptyTitle = "لا جديد"
    static let emptyMessage = "كل ما في الرمز موجود على هذا الجهاز بالفعل، فلا شيء لإضافته."
    static let scanNothingRead = "لم يُقرأ شيء بعد"
    static let scanForeign = "هذا رمز QR آخر. وجّه الكاميرا إلى رمز النقل في «إرسال التقدّم»."
    static let scanRestarted = "تغيّر الرمز على الجهاز الآخر، فبدأت القراءة من جديد."
    static let scanStalled = "لم تكتمل القراءة بعد. ارفع سطوع الشاشة الأخرى، وقرّب الجهاز أو أبعده قليلًا."

    private(set) var screen: Screen = .receive
    /// The paste field.
    var code = "" {
        didSet { if code != oldValue { pasteError = nil } }
    }
    private(set) var pasteError: String?
    private(set) var fileError: String?
    private(set) var preview: Preview?
    /// Storage changed during the review, so the list was planned again.
    private(set) var refreshed = false
    private(set) var outcome: Outcome?
    private(set) var isWriting = false
    /// The scan: frames read of how many, and a hint under the progress.
    private(set) var scanRead = 0
    private(set) var scanCount = 0
    private(set) var scanHint: String?
    /// Something was written: the screens behind show it once the sheet closes.
    private(set) var wrote = false

    var scanLabel: String {
        scanCount == 0 ? Self.scanNothingRead
            : "قُرئ \(ArabicFormat.number(scanRead)) من \(ArabicFormat.number(scanCount))"
    }

    var canContinue: Bool { !TransferImportModel.isBlank(code) && !isWriting }

    @ObservationIgnored private let importer: TransferImporter
    @ObservationIgnored private let today: () -> String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let applied: () -> Void
    @ObservationIgnored private var container: TransferContainer?
    @ObservationIgnored private var plan: TransferPlan?
    @ObservationIgnored private var scan = TransferScan()

    /// `today` is this device's local date when a code is planned (after the day rollover); `applied` runs after a
    /// confirmed write, to show the imported progress.
    init(importer: TransferImporter, today: @escaping () -> String, now: @escaping () -> Date = Date.init,
         applied: @escaping () -> Void) {
        self.importer = importer
        self.today = today
        self.now = now
        self.applied = applied
    }

    // MARK: Carriers

    /// «متابعة»: the pasted text. A code that cannot be read is explained under the field.
    func continuePaste() {
        guard canContinue else { return }
        switch TransferCodec.decode(text: code) {
        case let .success(container): review(container)
        case let .failure(error): pasteError = Self.errorText(error, surface: .paste)
        }
    }

    /// «لصق» found nothing to paste.
    func pasteUnavailable() {
        pasteError = Self.pasteHelp
    }

    /// «اختيار ملف»: the chosen file's bytes, or `nil` when it could not be read. A file that is no code is explained
    /// under the button.
    func importFile(_ data: Data?) {
        fileError = nil
        switch Self.decode(file: data) {
        case let .success(container): review(container)
        case let .failure(error): fileError = Self.errorText(error, surface: .file)
        }
    }

    /// A file shared to the app or opened in it: the sheet starts afresh on its review, or on its error.
    func open(fileData data: Data?) {
        reset()
        switch Self.decode(file: data) {
        case let .success(container): review(container)
        case let .failure(error): fail(error)
        }
    }

    /// A chosen file's bytes, refused unread past ``TransferCodec/maxFileBytes`` (read as one byte more, which
    /// `decode` then refuses as too long). `nil` when it cannot be read.
    nonisolated static func read(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            return try handle.read(upToCount: TransferCodec.maxFileBytes + 1) ?? Data()
        } catch {
            return nil
        }
    }

    private static func decode(file data: Data?) -> Result<TransferContainer, TransferError> {
        data.map(TransferCodec.decode(fileData:)) ?? .failure(TransferError(.fileRead))
    }

    // MARK: Scan

    func startScan() {
        scan = TransferScan()
        scanRead = 0
        scanCount = 0
        scanHint = nil
        screen = .scan
    }

    /// One QR text the camera read. `true` when scanning ends (every frame read, or a code that can never be read
    /// here): the camera stops.
    @discardableResult
    func scanned(_ text: String) -> Bool {
        guard screen == .scan else { return true }
        switch scan.scan(text) {
        case let .ignored(foreign):
            if foreign { scanHint = Self.scanForeign }
            return false
        case let .progress(read, count, restarted):
            scanRead = read
            scanCount = count
            scanHint = restarted ? Self.scanRestarted : (scanHint == Self.scanStalled ? nil : scanHint)
            return false
        case let .finished(.success(container)):
            scanRead = scan.count
            scanCount = scan.count
            review(container)
            return true
        case let .finished(.failure(error)):
            fail(error, surface: .scan)
            return true
        }
    }

    /// Nothing new was read for a while.
    func scanStalled() {
        guard screen == .scan else { return }
        scanHint = Self.scanStalled
    }

    /// «إيقاف المسح» or the fallback: back to paste and file.
    func stopScan() {
        screen = .receive
    }

    // MARK: Review

    /// «إضافة التقدّم» / «تطبيق التغييرات»: exactly the previewed plan is written. When the stores changed meanwhile,
    /// the code is planned again: a preview that reads the same is written, any other is shown for review.
    func confirm() {
        guard let container, let plan, !isWriting, preview?.isEmpty == false else { return }
        isWriting = true
        defer { isWriting = false }
        do {
            try importer.apply(plan, of: container, today: today())
        } catch let error as TransferError where error.kind == .changed {
            let shown = preview
            let replanned: TransferPlan
            do {
                replanned = try importer.plan(container, today: today(), now: now())
            } catch {
                fail(error)
                return
            }
            self.plan = replanned
            let fresh = Self.preview(replanned)
            if fresh == shown {
                do {
                    try importer.apply(replanned, of: container, today: today())
                } catch let error as TransferError where error.kind == .changed {
                    showRefreshed(fresh)
                    return
                } catch {
                    fail(error)
                    return
                }
            } else {
                showRefreshed(fresh)
                return
            }
        } catch {
            fail(error)
            return
        }
        wrote = true
        self.container = nil
        self.plan = nil
        code = ""
        applied()
        outcome = Outcome(succeeded: true, title: "نُقل التقدّم إلى هذا الجهاز",
                          message: "يظهر التقدّم المنقول الآن في أقسامه.")
        screen = .result
    }

    /// «إلغاء» on the review, or «المحاولة مرة أخرى» on an error: back to paste, file and camera.
    func back() {
        container = nil
        plan = nil
        preview = nil
        refreshed = false
        outcome = nil
        screen = .receive
    }

    // MARK: Steps

    private func reset() {
        back()
        code = ""
        pasteError = nil
        fileError = nil
    }

    private func review(_ container: TransferContainer) {
        let plan: TransferPlan
        do {
            plan = try importer.plan(container, today: today(), now: now())
        } catch {
            fail(error)
            return
        }
        self.container = container
        self.plan = plan
        preview = Self.preview(plan)
        refreshed = false
        screen = .review
    }

    private func showRefreshed(_ fresh: Preview) {
        preview = fresh
        refreshed = true
        screen = .review
    }

    private func fail(_ error: any Error, surface: Surface = .result) {
        let failure = (error as? TransferError) ?? TransferError(.write)
        outcome = Outcome(succeeded: false, title: Self.errorTitle(failure),
                          message: Self.errorText(failure, surface: surface))
        container = nil
        plan = nil
        screen = .result
    }

    private static func isBlank(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
    }

    // MARK: Errors (spec §7, the PWA's `transferErrorCopy`)

    enum Surface {
        case paste, file, scan, result
    }

    static func errorTitle(_ error: TransferError) -> String {
        copy(error).title
    }

    static func errorText(_ error: TransferError, surface: Surface) -> String {
        if surface == .scan, kind(error) == .corrupt { return "الرمز تالف أو ناقص. أعد المسح من البداية." }
        return copy(error).message
    }

    /// `incomplete` and `mixed` read as a damaged code; `changed` never reaches the screen.
    private static func kind(_ error: TransferError) -> TransferError.Kind {
        switch error.kind {
        case .incomplete, .mixed: .corrupt
        default: error.kind
        }
    }

    private static func copy(_ error: TransferError) -> (title: String, message: String) {
        switch kind(error) {
        case .notCode, .changed, .incomplete, .mixed:
            ("ليس رمز نقل", "هذا ليس رمز نقل من «أذكار المسلم». تأكد أنك نسخت الرمز من «إرسال التقدّم».")
        case .tooLong:
            ("ليس رمز نقل", "النص أطول من أي رمز نقل. تأكد أنك لصقت الرمز وحده.")
        case .oneFrame:
            ("رمز ناقص", "هذا جزء واحد من رمز QR متعدد الأجزاء. انسخ الرمز كاملًا من «نسخ الرمز».")
        case .wrongApp:
            ("رمز تطبيق آخر", "هذا رمز من تطبيق «رقية القرين»، وهذا التطبيق يستلم تقدّم «أذكار المسلم» فقط.")
        case .newer:
            ("إصدار أحدث", "أُنشئ هذا الرمز بإصدار أحدث من تطبيق الويب. حدّث هذا التطبيق ثم أعد المحاولة.")
        case .corrupt:
            ("رمز تالف", "الرمز تالف أو ناقص. انسخه كاملًا من الجهاز الآخر وأعد المحاولة؛ بعض تطبيقات المراسلة تغيّر المسافات داخل الرمز، فالمشاركة كملف أضمن.")
        case .clock:
            ("رمز غير صالح", "رمز غير صالح أو ساعة الجهاز غير مضبوطة: في الرمز أوقات لاحقة لساعة هذا الجهاز. تأكد من ضبط التاريخ والوقت على الجهازين، ثم أنشئ رمزًا جديدًا على الجهاز الآخر.")
        case .tooBig:
            ("يتجاوز ما يتسع له التطبيق", "لا يتسع التطبيق لكل ما في الرمز من عبارات المسبحة وسجلها مع ما على هذا الجهاز، فلم يُنقل شيء ولم يتغيّر تقدّمك.")
        case .fileRead:
            ("تعذّرت قراءة الملف", "تعذّرت قراءة الملف. اختر ملف رمز النقل أو ملف نسخة احتياطية من «أذكار المسلم».")
        case .write:
            ("تعذّر الحفظ", "لم يُحفظ شيء ولم يتغيّر تقدّمك. تأكد من وجود مساحة كافية على الجهاز، ثم أعد المحاولة.")
        }
    }

    // MARK: Preview (`transferPreviewMarkup`)

    static let periodNames = ["morning": "الصباح", "evening": "المساء"]
    static let settingNames: [TransferPlan.SettingChange: String] = [
        .theme: "المظهر", .textSize: "حجم نص الأذكار", .lineSpacing: "تباعد السطور", .haptics: "الاهتزاز",
        .longOrder: "ترتيب الأذكار الطويلة", .calculation: "طريقة حساب المواقيت",
    ]
    private static let because = "لأن إعادة الضبط على الجهاز الآخر أحدث."

    static func preview(_ plan: TransferPlan) -> Preview {
        let warnings = plan.warnings.map { warningText($0, today: plan.today) }
        let created = "أُنشئ الرمز: \(ArabicFormat.shortDate(plan.createdAt))، \(ArabicFormat.time(plan.createdAt))"
        if plan.isEmpty {
            return Preview(isEmpty: true, lead: emptyTitle, created: nil, rows: [], hasResets: false,
                           assurance: emptyMessage,
                           warnings: warnings, confirmTitle: "تم")
        }
        var rows = resetRows(plan)
        if plan.targetsAdded {
            rows.append(Row(title: "عدد التكرار",
                            detail: "تُضاف اختيارات عدد التكرار من الجهاز الآخر للأذكار التي لم يُختر لها عدد هنا؛ لا تغيير ظاهر في التقدّم."))
        }
        rows += additionRows(plan)
        let resets = plan.hasResets
        return Preview(
            isEmpty: false, lead: resets ? "سيتغيّر على هذا الجهاز:" : "سيُضاف إلى هذا الجهاز:", created: created,
            rows: rows, hasResets: resets,
            assurance: resets
                ? "أُعيد ضبط بعض التقدّم على الجهاز الآخر بعد آخر ما سُجّل هنا، فسيُطبَّق هنا كما هو موضّح أعلاه. لا شيء غير ذلك يُحذف أو ينقص، وتبقى إعداداتك الحالية كما هي."
                : "لن يُحذف شيء من هذا الجهاز ولن ينقص أي عدد. يُضاف ما ينقصه فقط، وتبقى إعداداتك الحالية كما هي.",
            warnings: warnings, confirmTitle: resets ? "تطبيق التغييرات" : "إضافة التقدّم")
    }

    private static func dayLabel(_ date: String, today: String) -> String {
        date == today ? "اليوم" : ArabicFormat.shortDate(localDate: date)
    }

    private static func tag(_ change: TransferPlan.Change) -> String {
        switch change.store {
        case .adhkar: periodNames[change.unit] ?? change.unit
        case .suwar: change.name
        case .tasbih: "المسبحة"
        }
    }

    /// `transferTagsByDate`: dates newest first, each with its tags once, adhkar (الصباح before المساء), then suwar,
    /// then «المسبحة».
    private static func tagsByDate(_ changes: [TransferPlan.Change]) -> [(date: String, tags: [String])] {
        func rank(_ change: TransferPlan.Change) -> Int {
            switch change.store {
            case .adhkar: change.unit == "morning" ? 0 : 1
            case .suwar: 2
            case .tasbih: 3
            }
        }
        let byDate = Dictionary(grouping: changes, by: \.date)
        return byDate.keys.sorted(by: >).map { date in
            var tags: [String] = []
            let ordered = byDate[date]!.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            for (_, change) in ordered where !tags.contains(tag(change)) { tags.append(tag(change)) }
            return (date, tags)
        }
    }

    private static func adhkar(_ summary: TransferPlan.Summary) -> TransferPlan.AdhkarSummary? {
        if case let .adhkar(value) = summary { return value }
        return nil
    }

    private static func pages(_ summary: TransferPlan.Summary) -> (pages: [String], complete: Bool) {
        if case let .suwar(pages, complete) = summary { return (pages, complete) }
        return ([], false)
    }

    private static func count(_ summary: TransferPlan.Summary) -> Int {
        if case let .tasbih(value) = summary { return value }
        return 0
    }

    private static func resetRows(_ plan: TransferPlan) -> [Row] {
        let resets = plan.changes.filter { $0.kind == .reset }
        var rows: [Row] = []
        for change in resets where change.date == plan.today {
            switch change.store {
            case .adhkar:
                guard let before = adhkar(change.before), let after = adhkar(change.after) else { continue }
                let name = periodNames[change.unit] ?? change.unit
                rows.append(Row(title: "أذكار \(name) — اليوم",
                                detail: "سيُعاد ضبط تقدّم أذكار \(name) اليوم \(because) يصبح المكتمل \(ArabicFormat.number(after.done)) من \(ArabicFormat.number(after.total)) بدل \(ArabicFormat.number(before.done)).",
                                isReset: true))
            case .suwar:
                let after = pages(change.after).pages
                let lost = pages(change.before).pages.filter { !after.contains($0) }.count
                rows.append(Row(title: "\(change.name) — اليوم",
                                detail: "سيُعاد ضبط علامات قراءة \(change.name) اليوم \(because) تُزال العلامة عن \(lostPages(lost)).",
                                isReset: true))
            case .tasbih:
                break
            }
        }
        let tasbih = Dictionary(grouping: resets.filter { $0.store == .tasbih }, by: \.date)
        for date in tasbih.keys.sorted(by: >) {
            let label = dayLabel(date, today: plan.today)
            let before = tasbih[date]!.reduce(0) { $0 + count($1.before) }
            let after = tasbih[date]!.reduce(0) { $0 + count($1.after) }
            rows.append(Row(title: "المسبحة — \(label)",
                            detail: "سيُعاد ضبط عدّ المسبحة \(label) \(because) ينقص المجموع من \(ArabicFormat.number(before)) إلى \(ArabicFormat.number(after)).",
                            isReset: true))
        }
        for (date, tags) in tagsByDate(resets.filter { $0.store != .tasbih && $0.date < plan.today }) {
            let label = dayLabel(date, today: plan.today)
            rows.append(Row(title: "السجل — \(label)",
                            detail: "سيُحذف \(label) من سجل الإكمال \(because) يُزال: \(tags.joined(separator: "، ")).",
                            isReset: true))
        }
        return rows
    }

    private static func additionRows(_ plan: TransferPlan) -> [Row] {
        let additions = plan.changes.filter { $0.kind == .addition }
        let today = additions.filter { $0.date == plan.today }
        var rows: [Row] = []
        for period in ["morning", "evening"] {
            guard let change = today.first(where: { $0.store == .adhkar && $0.unit == period }),
                  let was = adhkar(change.before), let now = adhkar(change.after)
            else { continue }
            let title = "أذكار \(periodNames[period]!) — اليوم"
            if !was.complete, now.complete {
                rows.append(now.countersComplete
                    ? Row(title: title, detail: "يكتمل الورد ✓", isComplete: true)
                    : Row(title: title, detail: "يُسجَّل الورد مكتملًا"))
                continue
            }
            var parts: [String] = []
            if now.done > was.done {
                parts.append("يصبح المكتمل \(ArabicFormat.number(now.done)) من \(ArabicFormat.number(now.total)) بعد \(ArabicFormat.number(was.done))")
            }
            if change.risen > 0 { parts.append("يزيد عدّ \(ArabicFormat.number(change.risen)) من الأذكار") }
            if !parts.isEmpty { rows.append(Row(title: title, detail: parts.joined(separator: "، و"))) }
        }
        let suwar = today.filter { $0.store == .suwar }
        if !suwar.isEmpty {
            let newPages = suwar.reduce(0) { sum, change in
                let before = pages(change.before).pages
                return sum + pages(change.after).pages.filter { !before.contains($0) }.count
            }
            let completed = suwar.filter { pages($0.after).complete && !pages($0.before).complete }.map(\.name)
            var parts: [String] = []
            if newPages > 0 { parts.append(self.newPages(newPages)) }
            if !completed.isEmpty { parts.append("\(newPages > 0 ? "وتكتمل" : "تكتمل") \(list(completed))") }
            if !parts.isEmpty { rows.append(Row(title: "قراءة السور — اليوم", detail: parts.joined(separator: "، "))) }
        }
        let raised = today.filter { $0.store == .tasbih && count($0.after) > count($0.before) }.count
        let phrases = plan.addedPhrases.count
        if raised > 0 || phrases > 0 {
            let added = "تُضاف \(ArabicFormat.number(phrases)) من العبارات إلى «عباراتك»"
            let text = raised > 0
                ? "يرتفع العدّ في \(ArabicFormat.number(raised)) من الأذكار" + (phrases > 0 ? "، و\(added)" : "")
                : added
            rows.append(Row(title: "المسبحة — اليوم", detail: text))
        }
        let history = tagsByDate(additions.filter { $0.date < plan.today })
        if !history.isEmpty {
            rows.append(Row(title: "السجل", detail: days(history.count),
                            dates: history.map { "\(ArabicFormat.shortDate(localDate: $0.date)): \($0.tags.joined(separator: "، "))" }))
        }
        let settings = plan.settings.compactMap { settingNames[$0] }
        if !settings.isEmpty { rows.append(Row(title: "الإعدادات", detail: "تُطبَّق: \(settings.joined(separator: "، "))")) }
        return rows
    }

    static func warningText(_ warning: TransferPlan.Warning, today: String) -> String {
        switch warning {
        case .backup:
            "هذا ملف نسخة احتياطية، فيه أذكار الصباح والمساء وسجلها فقط، وليس فيه المسبحة ولا قراءة السور."
        case .future:
            "تاريخ «اليوم» في الرمز لاحق لتاريخ هذا الجهاز، فلن يُنقل تقدّم ذلك اليوم. تحقّق من التاريخ والمنطقة الزمنية على الجهازين."
        case .trimmed:
            "يحفظ التطبيق سجل آخر ٣١ يومًا فقط، فلن تُضاف الأيام الأقدم من ذلك."
        case let .tasbihCap(phrases):
            "لا تتسع «عباراتك» لأكثر من ٨ عبارات، فلن تُضاف هذه العبارات ولا عدّها: \(phrases.map { "«\($0)»" }.joined(separator: "، "))."
        case let .stale(date):
            "أُنشئ هذا الرمز \(daysAgo(dayDistance(from: date, to: today)))، فلا يحمل ما سُجّل على الجهاز الآخر بعد ذلك."
        }
    }

    /// `transferDayDistance`: whole days from one local date to another.
    static func dayDistance(from: String, to: String) -> Int {
        func day(_ date: String) -> Int? {
            let parts = date.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            guard let instant = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            else { return nil }
            return Int((instant.timeIntervalSince1970 / 86_400).rounded())
        }
        guard let start = day(from), let end = day(to) else { return 0 }
        return end - start
    }

    // MARK: Arabic counts (`Intl.PluralRules("ar")`)

    private enum Plural {
        case zero, one, two, few, many, other
    }

    private static func plural(_ count: Int) -> Plural {
        switch count {
        case 0: .zero
        case 1: .one
        case 2: .two
        default:
            switch count % 100 {
            case 3...10: .few
            case 11...99: .many
            default: .other
            }
        }
    }

    /// `transferDays`.
    static func days(_ count: Int) -> String {
        let number = ArabicFormat.number(count)
        return switch plural(count) {
        case .one: "يوم واحد"
        case .two: "يومان"
        case .few: "\(number) أيام"
        case .many: "\(number) يومًا"
        case .zero, .other: "\(number) يوم"
        }
    }

    /// `transferNewPages`.
    static func newPages(_ count: Int) -> String {
        let number = ArabicFormat.number(count)
        return switch plural(count) {
        case .one: "صفحة واحدة مقروءة جديدة"
        case .two: "صفحتان مقروءتان جديدتان"
        case .few: "\(number) صفحات مقروءة جديدة"
        case .many: "\(number) صفحةً مقروءةً جديدةً"
        case .zero, .other: "\(number) صفحة مقروءة جديدة"
        }
    }

    /// `transferLostPages`.
    static func lostPages(_ count: Int) -> String {
        let number = ArabicFormat.number(count)
        return switch plural(count) {
        case .one: "صفحة واحدة"
        case .two: "صفحتين"
        case .few: "\(number) صفحات"
        case .many: "\(number) صفحةً"
        case .zero, .other: "\(number) صفحة"
        }
    }

    /// `Intl.RelativeTimeFormat("ar-EG", { numeric: "auto" }).format(-days, "day")`.
    static func daysAgo(_ days: Int) -> String {
        let number = ArabicFormat.number(days)
        return switch days {
        case 0: "اليوم"
        case 1: "أمس"
        case 2: "أول أمس"
        default:
            switch plural(days) {
            case .few: "قبل \(number) أيام"
            case .many: "قبل \(number) يومًا"
            default: "قبل \(number) يوم"
            }
        }
    }

    /// `Intl.ListFormat("ar", { type: "conjunction" })`: «أ وب وج».
    static func list(_ parts: [String]) -> String {
        guard let first = parts.first else { return "" }
        return parts.dropFirst().reduce(first) { "\($0) و\($1)" }
    }
}
