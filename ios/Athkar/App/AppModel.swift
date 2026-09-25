import AthkarCore
import Foundation
import Observation

/// Reading and appearance settings (`settings` table). Each change is written at once; SQLite is the only store.
@MainActor
@Observable
final class SettingsModel {
    var theme: Theme { didSet { write(theme, .theme) } }
    var textSize: TextSize { didSet { write(textSize, .textSize) } }
    var lineSpacing: LineSpacing { didSet { write(lineSpacing, .lineSpacing) } }
    var haptics: Bool { didSet { write(haptics, .haptics) } }
    private(set) var longOrder: LongOrder
    private(set) var longOrderPromptAnswered: Bool

    @ObservationIgnored private let repository: SettingsRepository
    @ObservationIgnored private let report: (any Error) -> Void

    init(repository: SettingsRepository, report: @escaping (any Error) -> Void) throws {
        self.repository = repository
        self.report = report
        theme = try repository.value(for: .theme)
        textSize = try repository.value(for: .textSize)
        lineSpacing = try repository.value(for: .lineSpacing)
        haptics = try repository.value(for: .haptics)
        longOrder = try repository.value(for: .longOrder)
        longOrderPromptAnswered = try repository.value(for: .longOrderPromptAnswered)
    }

    fileprivate func setLongOrder(_ value: LongOrder) {
        longOrder = value
        write(value, .longOrder)
    }

    fileprivate func markLongOrderPromptAnswered() {
        longOrderPromptAnswered = true
        write(true, .longOrderPromptAnswered)
    }

    private func write<Value>(_ value: Value, _ key: SettingKey<Value>) {
        do {
            try repository.set(value, for: key)
        } catch {
            report(error)
        }
    }
}

/// The running app: database, bundled content, settings and the three decks, plus the day they belong to.
@MainActor
@Observable
final class AppModel {
    let settings: SettingsModel
    let adhkar: AdhkarSessionModel
    let morning: AdhkarDeckModel
    let evening: AdhkarDeckModel
    let ruqyah: RuqyahDeckModel
    var selection: DeckID = .morning {
        didSet {
            switch selection {
            case .morning: lastPeriod = .morning
            case .evening: lastPeriod = .evening
            case .ruqyah: break
            }
        }
    }
    /// The adhkar period last on screen (`activePeriod`): long-order keeps its current card.
    private(set) var lastPeriod: Period = .morning
    /// Set when a database write fails; the screen shows it once.
    var failure: String?

    private init(database: AppDatabase, content: BundledContent, today: String) throws {
        var reportFailure: (any Error) -> Void = { _ in }
        let report: (any Error) -> Void = { reportFailure($0) }
        settings = try SettingsModel(repository: database.settings, report: report)
        adhkar = try AdhkarSessionModel(database: database, content: content,
                                        longAdhkarLast: settings.longOrder == .last, today: today, report: report)
        morning = AdhkarDeckModel(period: .morning, session: adhkar)
        evening = AdhkarDeckModel(period: .evening, session: adhkar)
        ruqyah = try RuqyahDeckModel(database: database, content: content, today: today, report: report)
        reportFailure = { [weak self] error in
            self?.failure = "تعذّر حفظ التغيير على هذا الجهاز. (\(error.localizedDescription))"
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
        }
    }

    /// The day rollover (`ensureCurrentDay`): run on `NSCalendarDayChanged`, on returning to the foreground, and
    /// before counting a tap. Returns whether the day changed.
    @discardableResult
    func ensureCurrentDay() -> Bool {
        let today = Self.today()
        guard today != adhkar.state.date || today != ruqyah.progress.date else { return false }
        adhkar.roll(to: today)
        ruqyah.roll(to: today)
        return true
    }

    /// The settings toggle «تأخير الأذكار الطويلة».
    func setLongOrder(_ enabled: Bool) {
        settings.setLongOrder(enabled ? .last : .original)
        adhkar.applyLongOrder(enabled, active: lastPeriod)
    }

    /// The one-time question «تأجيل الأذكار الطويلة؟».
    func answerLongOrderPrompt(moveLongLast: Bool) {
        settings.markLongOrderPromptAnswered()
        setLongOrder(moveLongLast)
    }

    private static func today() -> String {
        let now = Date()
        let shifted = Calendar.current.date(byAdding: .day, value: TestHooks.dayOffset, to: now) ?? now
        return SessionCalendar.localDate(of: shifted, in: .current)
    }
}
