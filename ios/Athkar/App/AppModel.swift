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
    let prayer: PrayerTimesModel
    let reminders: ReminderModel
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
    /// The adhkar period last on screen (`activePeriod`): long-order keeps its current card.
    private(set) var lastPeriod: Period = .morning
    /// Set when a database write fails; the screen shows it once.
    var failure: String?

    init(database: AppDatabase, content: BundledContent, today: String) throws {
        var reportFailure: (any Error) -> Void = { _ in }
        let report: (any Error) -> Void = { reportFailure($0) }
        settings = try SettingsModel(repository: database.settings, report: report)
        adhkar = try AdhkarSessionModel(database: database, content: content,
                                        longAdhkarLast: settings.longOrder == .last, today: today, report: report)
        morning = AdhkarDeckModel(period: .morning, session: adhkar)
        evening = AdhkarDeckModel(period: .evening, session: adhkar)
        ruqyah = try RuqyahDeckModel(database: database, content: content, today: today, report: report)
        suwar = try SuwarDeckModel(database: database, content: content, today: today, report: report)
        prayer = try PrayerTimesModel(database: database, report: report)
        reminders = try ReminderModel(repository: database.reminders, report: report)
        reportFailure = { [weak self] error in
            self?.failure = "تعذّر حفظ التغيير على هذا الجهاز. (\(error.localizedDescription))"
        }
        reminders.inputs = { [weak self] now in
            guard let self else { return nil }
            ensureCurrentDay(now: now)
            let prayer = prayer
            let zone = prayer.zone
            // Completion counts only for the planner's own date, in its zone at the pass's instant.
            return ReminderModel.PlanInputs(
                zone: zone,
                schedule: { date in prayer.schedule(on: date) },
                completeToday: adhkar.completedPeriods(on: SessionCalendar.localDate(of: now, in: zone)))
        }
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

    private var rollover: DayRollover { DayRollover(adhkar: adhkar, ruqyah: ruqyah, suwar: suwar) }

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

    private static func today(now: Date = Date()) -> String {
        let shifted = Calendar.current.date(byAdding: .day, value: TestHooks.dayOffset, to: now) ?? now
        return SessionCalendar.localDate(of: shifted, in: .current)
    }
}
