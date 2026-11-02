import AthkarCore
import Foundation
import Observation

/// The running app: database, bundled content, settings and the decks, plus the day they belong to.
@MainActor
@Observable
final class AppModel {
    let settings: SettingsModel
    let adhkar: AdhkarSessionModel
    let morning: AdhkarDeckModel
    let evening: AdhkarDeckModel
    let ruqyah: RuqyahDeckModel
    let suwar: SuwarDeckModel
    let tasbih: TasbihModel
    let prayer: PrayerTimesModel
    let reminders: ReminderModel
    let tracker: PrayerTrackerModel
    /// The bundled packs and their versions (`manifest.json`), for the diagnostics screen.
    let contentVersions: [(pack: String, version: String)]
    /// The tab on screen: الصباح, المساء or أخرى.
    var tab: HomeTab = .morning
    /// The section open in the أخرى tab, or `nil` for its list.
    var otherSection: OtherSection?
    /// The deck on screen, or the one the أخرى tab's colours follow while its list shows. Setting it opens the deck.
    var selection: DeckID {
        get {
            switch tab {
            case .morning: .morning
            case .evening: .evening
            case .other: otherSection?.deck ?? .ruqyah
            }
        }
        set {
            switch newValue {
            case .morning:
                tab = .morning
                lastPeriod = .morning
            case .evening:
                tab = .evening
                lastPeriod = .evening
            case .ruqyah:
                tab = .other
                otherSection = .ruqyah
            case .suwar:
                tab = .other
                otherSection = .suwar
            }
        }
    }
    /// The أخرى tab is showing its list of sections.
    var showsOtherList: Bool { tab == .other && otherSection == nil }
    /// A deck is on screen (not the أخرى list, nor a section without a deck such as أوقات الصلاة).
    var showsDeck: Bool { tab != .other || otherSection?.deck != nil }
    /// «مسبحة» is on screen.
    var showsTasbih: Bool { tab == .other && otherSection == .tasbih }
    /// What «⋯»'s «إعادة» resets: the deck or «مسبحة» on screen, or nothing elsewhere.
    var resettable: (any ResettableSection)? {
        if showsTasbih { return tasbih }
        return showsDeck ? deck(selection) : nil
    }
    /// The adhkar period last on screen (`activePeriod`): long-order keeps its current card.
    private(set) var lastPeriod: Period = .morning
    /// Set when a database write fails; the screen shows it once.
    var failure: String?
    /// A file shared to the app or opened in it, waiting for «استيراد من تطبيق الويب» to show it (`nil` data: the
    /// file could not be read).
    var pendingTransferFile: PendingTransferFile?

    @ObservationIgnored private let transferImporter: TransferImporter

    /// - Parameters:
    ///   - notifications: the reminders' notification centre; iOS's own unless a test supplies one.
    ///   - reminderClock: the reminders' clock, which a test may fix.
    ///   - diagnosticsStore: where the reminder diagnostics' times are kept; `UserDefaults` unless a test supplies one.
    init(database: AppDatabase, content: BundledContent, today: String,
         notifications: (any ReminderNotificationCenter)? = nil,
         reminderClock: @escaping () -> Date = { Date() },
         diagnosticsStore: (any ReminderDiagnosticsStore)? = nil) throws {
        var reportFailure: (any Error) -> Void = { _ in }
        let report: (any Error) -> Void = { reportFailure($0) }
        settings = try SettingsModel(repository: database.settings, report: report)
        adhkar = try AdhkarSessionModel(database: database, content: content,
                                        longAdhkarLast: settings.longOrder == .last, today: today, report: report)
        morning = AdhkarDeckModel(period: .morning, session: adhkar)
        evening = AdhkarDeckModel(period: .evening, session: adhkar)
        ruqyah = try RuqyahDeckModel(database: database, content: content, today: today, report: report)
        suwar = try SuwarDeckModel(database: database, content: content, today: today, report: report)
        tasbih = try TasbihModel(database: database, today: today, report: report)
        let prayer = try PrayerTimesModel(database: database, report: report)
        self.prayer = prayer
        // The tracker's dates are the prayer times' dates; a new record captures the time and profile shown.
        tracker = PrayerTrackerModel(
            repository: database.prayerRecords, report: report,
            clock: { (Self.now(), prayer.zone) },
            metadata: { occurrence in
                (prayer.schedule(on: occurrence.date)?.scheduledTime(of: occurrence.prayer),
                 prayer.settings.profileVersion)
            })
        reminders = try ReminderModel(repository: database.reminders, report: report,
                                      center: notifications ?? UserNotificationCenterAdapter(), clock: reminderClock,
                                      diagnosticsStore: diagnosticsStore ?? UserDefaultsDiagnosticsStore())
        contentVersions = content.manifest.packs.map { (pack: $0.key, version: $0.value.version) }
            .sorted { $0.pack < $1.pack }
        transferImporter = TransferImporter(
            database: database, collections: content.packs.adhkar,
            suwar: content.suwar.suwar.map { SuwarOutline(id: $0.id, name: $0.surah, pageIDs: $0.pages.map(\.id)) })
        reportFailure = { [weak self] error in
            self?.failure = "تعذّر حفظ التغيير على هذا الجهاز. (\(error.localizedDescription))"
        }
        reminders.inputs = { [weak self] now in
            guard let self else { return nil }
            ensureCurrentDay(now: now)
            let prayer = prayer
            let zone = prayer.zone
            // Completion counts only for the planner's own date, in its zone at the pass's instant; the tracker's
            // records for the horizon's dates.
            let today = SessionCalendar.localDate(of: now, in: zone)
            return ReminderModel.PlanInputs(
                zone: zone,
                schedule: { date in prayer.schedule(on: date) },
                completeToday: adhkar.completedPeriods(on: today),
                prayerStates: tracker.states(from: today, days: ReminderPlanner.horizonDays))
        }
        // Record, undo, timing, the Friday choice, a cleared day, a past day: a recorded prayer loses its reminder.
        tracker.didWrite = { [weak self] in self?.reminders.replan() }
    }

    /// «سجّل الصلاة» on a prayer reminder (NATIVE_APP_PLAN.md §7.5): the same idempotent «record» as «اليوم», for the
    /// occurrence the reminder names (its own date, not today's), then a replan this waits for, so the pending and
    /// delivered requests match the tracker before iOS suspends a background launch. Returns whether it recorded.
    @discardableResult
    func recordPrayer(_ payload: ReminderPayload, shownAt date: Date) async -> Bool {
        guard let occurrence = payload.occurrence else { return false }
        reminders.markShown(payload, localDate: SessionCalendar.localDate(of: date, in: prayer.zone))
        let recorded = tracker.logFromReminder(occurrence)
        await reminders.replanAndWait()
        return recorded
    }

    /// A tapped reminder: an adhkar reminder opens its deck, a prayer reminder أوقات الصلاة.
    func open(_ payload: ReminderPayload) {
        if let deck = payload.deck {
            selection = deck
        } else if payload.isPrayer {
            tab = .other
            otherSection = .prayerTimes
        }
    }

    /// Opens the on-disk database (Application Support), loads the bundled packs and records their versions.
    /// In Debug builds `--reset-data` starts from an empty database (UI tests); Release builds ignore it.
    static func launch(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> AppModel {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Athkar", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("athkar.sqlite")
        #if DEBUG
        if arguments.contains("--reset-data") {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        #endif
        let database = try AppDatabase.onDisk(at: url)
        let content = try BundledContent.load()
        try BundledContent.recordInstalls(manifest: content.manifest, in: database)
        return try AppModel(database: database, content: content, today: Self.today())
    }

    func deck(_ id: DeckID) -> any DeckModel {
        switch id {
        case .morning: morning
        case .evening: evening
        case .ruqyah: ruqyah
        case .suwar: suwar
        }
    }

    /// The day rollover (`ensureCurrentDay`): run on `NSCalendarDayChanged`, on returning to the foreground, and
    /// before counting a tap. Returns whether any deck's day changed or still cannot be read.
    @discardableResult
    func ensureCurrentDay() -> Bool {
        ensureCurrentDay(now: Date())
    }

    /// The day rollover at `now`: a reminder pass rolls at its own planning instant.
    @discardableResult
    func ensureCurrentDay(now: Date) -> Bool {
        !rollover.roll(to: Self.today(now: now)).isEmpty
    }

    /// `DeckView`'s gate: the same rollover, answering only for `deck`'s own session, so a day the other session
    /// cannot read leaves this deck working.
    @discardableResult
    func ensureCurrentDay(for deck: DeckID) -> Bool {
        rollover.roll(to: Self.today()).contains(deck)
    }

    /// «مسبحة»'s gate: the same rollover, answering whether the counter shows today. Unlike a deck's, a change made as
    /// the day turns applies to the new day (`addTasbihCount` counts after `ensureCurrentDay`); only a day that cannot
    /// be read drops it.
    func ensureTasbihDay() -> Bool {
        let today = Self.today()
        _ = rollover.roll(to: today)
        return tasbih.date == today
    }

    private var rollover: DayRollover { DayRollover(adhkar: adhkar, ruqyah: ruqyah, suwar: suwar, tasbih: tasbih) }

    /// The settings toggle «تأخير الأذكار الطويلة». The decks are reordered only once the choice is saved.
    func setLongOrder(_ enabled: Bool) {
        guard settings.setLongOrder(enabled ? .last : .original) else { return }
        adhkar.applyLongOrder(enabled, active: lastPeriod)
    }

    /// The one-time question «تأجيل الأذكار الطويلة؟». The answer and the order are saved together, then applied; a
    /// failed save leaves the decks as they are and the question unanswered.
    func answerLongOrderPrompt(moveLongLast: Bool) {
        guard settings.answerLongOrderPrompt(moveLongLast ? .last : .original) else { return }
        adhkar.applyLongOrder(moveLongLast, active: lastPeriod)
    }

    // MARK: Transfer import

    /// «استيراد من تطبيق الويب» (NATIVE_APP_PLAN.md §6.4): codes are planned for today after the day rollover, and a
    /// confirmed import is shown at once in every section it touched.
    func makeTransferImport() -> TransferImportModel {
        TransferImportModel(importer: transferImporter, today: { [weak self] in
            self?.ensureCurrentDay()
            return Self.today()
        }, applied: { [weak self] in self?.showImportedProgress() })
    }

    /// Reads back what an import wrote: settings (the long-adhkar order included), the sessions of the day on screen,
    /// and the prayer calculation.
    private func showImportedProgress() {
        settings.reload()
        adhkar.reload(longAdhkarLast: settings.longOrder == .last)
        suwar.reload()
        tasbih.reload()
        prayer.reloadSettings()
    }

    /// A file opened in the app (Files, the share sheet, AirDrop), read while its security scope is open.
    func openTransferFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        pendingTransferFile = PendingTransferFile(data: TransferImportModel.read(url))
    }

    private static func today(now: Date = Date()) -> String {
        SessionCalendar.localDate(of: Self.now(now), in: .current)
    }

    /// Now, moved by ``TestHooks/dayOffset`` in Debug builds.
    static func now(_ now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: TestHooks.dayOffset, to: now) ?? now
    }
}

/// A file waiting to be imported; each opening is shown, even of the same file again.
struct PendingTransferFile: Identifiable {
    let id = UUID()
    let data: Data?
}
