import Foundation
import GRDB

/// Merges a backup file into the database (NATIVE_APP_PLAN.md §6.4, spec/schema.md "Import"). Format 2 merges by
/// the rules in NativeBackupImport.swift.
///
/// - The whole file is validated first and merged in one transaction: a bad file changes nothing.
/// - Each section merges into its own tables, so the two PWA files can be imported alone or both, in any order.
/// - Merge units are `(local_date, period)` for adhkar (completion row and item rows together),
///   `(local_date)` for ruqyah completion, `(local_date, segment_id)` for ruqyah counts. An existing unit wins
///   unless it is empty; imported rows are stamped with `meta.exportedAt`. Re-import is therefore a no-op.
/// - Settings rows (preferences, calculation profile) follow origin precedence native > athkar-pwa > ruqyah-pwa.
/// - Today's data is checked against the content: adhkar completion must follow from the counters (or manual
///   completion), and ruqyah counts are clamped to each segment's `repeat`, unknown segments dropped.
public struct BackupImporter: Sendable {
    let database: AppDatabase
    let content: ContentPacks

    public init(database: AppDatabase, content: ContentPacks) {
        self.database = database
        self.content = content
    }

    /// Decodes, validates, and merges a format 1 backup file. Returns the decoded envelope.
    @discardableResult
    public func importBackup(_ data: Data) throws -> BackupEnvelope {
        let envelope = try BackupEnvelope.decode(data)
        try importEnvelope(envelope)
        return envelope
    }

    /// Merges a decoded file of either format. With `dryRun`, the merge runs and is rolled back: the summary says
    /// what confirming would write, and nothing is written.
    @discardableResult
    public func importFile(_ file: BackupFile, dryRun: Bool = false) throws -> BackupImportSummary {
        switch file {
        case let .pwa(envelope): try importEnvelope(envelope, dryRun: dryRun)
        case let .native(backup): try importNative(backup, dryRun: dryRun)
        }
    }

    @discardableResult
    public func importEnvelope(_ envelope: BackupEnvelope, dryRun: Bool = false) throws -> BackupImportSummary {
        try envelope.validate()
        let stamp = envelope.meta.exportedAt
        let origin: SettingOrigin = envelope.meta.app == .athkarPWA ? .athkarPWA : .ruqyahPWA
        return try write(dryRun: dryRun) { db, summary in
            if let adhkar = envelope.adhkar {
                summary.adhkar += try Self.merge(adhkar, collections: content.adhkar, into: db, stamp: stamp)
            }
            if let ruqyah = envelope.ruqyah {
                summary.ruqyah += try Self.merge(ruqyah, segments: content.ruqyahSegments, into: db, stamp: stamp)
            }
            if let reminders = envelope.reminders {
                try Self.merge(reminders, into: db, origin: origin, stamp: stamp, summary: &summary)
            }
            if let preferences = envelope.preferences {
                summary.settings += try Self.merge(preferences, into: db, origin: origin, stamp: stamp)
            }
        }
    }

    /// One transaction; with `dryRun` it is rolled back after `merge` has counted what it wrote.
    func write(dryRun: Bool,
               _ merge: @Sendable (Database, inout BackupImportSummary) throws -> Void) throws -> BackupImportSummary {
        struct RolledBack: Error {
            var summary: BackupImportSummary
        }
        do {
            return try database.writer.write { db in
                var summary = BackupImportSummary()
                try merge(db, &summary)
                if dryRun { throw RolledBack(summary: summary) }
                return summary
            }
        } catch let rolledBack as RolledBack {
            return rolledBack.summary
        }
    }

    // MARK: Adhkar

    private static func merge(_ adhkar: BackupEnvelope.Adhkar, collections: SessionCollections, into db: Database,
                              stamp: Date) throws -> Int {
        var merged = 0
        for session in sessions(from: adhkar, collections: collections) {
            // An imported unit with no rows and no completion has nothing to contribute.
            guard session.completion != nil || !session.progress.isEmpty || !session.targets.isEmpty else { continue }
            let native = try AdhkarRepository.session(in: db, on: session.localDate, period: session.period)
            if native.isEmpty {
                try AdhkarRepository.replace(in: db, with: session, updatedAt: stamp)
                merged += 1
            }
        }
        return merged
    }

    /// `adhkar.today` and `adhkar.history` as stored sessions. History entries carry only completion.
    /// `validate()` guarantees history dates are distinct and before `today.date`.
    ///
    /// Today's period is complete only as the PWA would judge it from these values: `manualCompletion` (origin
    /// `manual`) or the counters per `SessionState.countersComplete` (origin `counters`). `completedAt` is kept
    /// only then. History booleans are trusted (origin `import`): they were judged against past content.
    static func sessions(from adhkar: BackupEnvelope.Adhkar, collections: SessionCollections) -> [AdhkarSession] {
        let today = adhkar.today
        var state = SessionState.empty(date: today.date)
        for period in Period.allCases {
            state.progress[period] = .object(today.progress[period].mapValues { .number($0) })
            state.targets[period] = .object(today.targets[period].mapValues { .number($0) })
        }
        var sessions = Period.allCases.map { period in
            let origin: CompletionOrigin? = today.manualCompletion[period]
                ? .manual
                : state.countersComplete(period, in: collections) ? .counters : nil
            return AdhkarSession(
                localDate: today.date, period: period,
                progress: today.progress[period].mapValues(storedCount),
                targets: today.targets[period].compactMapValues(storedTarget),
                completion: origin.map {
                    AdhkarDay(localDate: today.date, period: period, completedAt: today.completedAt[period],
                              completionOrigin: $0)
                })
        }
        for entry in adhkar.history {
            for (period, complete, completedAt) in [(Period.morning, entry.morning, entry.morningAt),
                                                    (Period.evening, entry.evening, entry.eveningAt)] where complete {
                sessions.append(AdhkarSession(
                    localDate: entry.date, period: period,
                    completion: AdhkarDay(localDate: entry.date, period: period, completedAt: completedAt,
                                          completionOrigin: .imported)))
            }
        }
        return sessions
    }

    /// Floored, as `countForState` reads it. `validate()` bounds values to 2^53 - 1, so this is exact.
    private static func storedCount(_ value: Double) -> Int {
        Int(value.rounded(.down))
    }

    /// Non-integer targets can never equal a target option, so like the PWA they mean "default": dropped.
    private static func storedTarget(_ value: Double) -> Int? {
        Int(exactly: value)
    }

    // MARK: Ruqyah

    /// Clamped to `0…repeat` and restricted to known segments, as the ruqyah PWA's `normalizeCounts` does.
    /// Returns the number of dates something was written for.
    private static func merge(_ ruqyah: BackupEnvelope.Ruqyah, segments: [RuqyahSegment], into db: Database,
                              stamp: Date) throws -> Int {
        var dates = Set<String>()
        for (date, entry) in ruqyah.history.sorted(by: { $0.key < $1.key })
        where try !RuqyahDay.exists(db, key: date) {
            try RuqyahDay(localDate: date, completedAt: entry.completedAt, completionOrigin: .imported).insert(db)
            dates.insert(date)
        }
        let date = ruqyah.today.date
        for segment in segments {
            guard let imported = ruqyah.today.counts[segment.id] else { continue }
            let count = max(0, min(imported, segment.repeatCount))
            let key: [String: (any DatabaseValueConvertible)?] = ["local_date": date, "segment_id": segment.id]
            if let native = try RuqyahSegmentProgress.fetchOne(db, key: key), native.count > 0 { continue }
            try RuqyahSegmentProgress(localDate: date, segmentId: segment.id, count: count, updatedAt: stamp)
                .upsert(db)
            if count > 0 { dates.insert(date) }
        }
        return dates.count
    }

    // MARK: Reminders and settings

    private static func merge(_ reminders: BackupEnvelope.Reminders, into db: Database, origin: SettingOrigin,
                              stamp: Date, summary: inout BackupImportSummary) throws {
        for period in Period.allCases {
            let ruleId = ReminderRule.adhkarId(period)
            if try !ReminderRule.exists(db, key: ruleId) {
                try ReminderRule.adhkar(period, enabled: reminders[period].enabled, updatedAt: stamp).insert(db)
                summary.reminders += 1
            }
            if let shown = reminders.lastShown[period], try !ReminderState.exists(db, key: ruleId) {
                try ReminderState(ruleId: ruleId, lastShownLocalDate: shown).insert(db)
            }
        }
        for written in [
            try SettingsRepository.importValue(reminders.calculationMethod, for: .calculationMethod, in: db,
                                               origin: origin, updatedAt: stamp),
            try SettingsRepository.importValue(reminders.asrSchool, for: .asrSchool, in: db,
                                               origin: origin, updatedAt: stamp),
        ] where written {
            summary.settings += 1
        }
        if let location = reminders.location, try LocationProfile.fetchCount(db) == 0 {
            try LocationProfile(latitude: location.latitude, longitude: location.longitude, source: .imported,
                                updatedAt: location.updatedAt).insert(db)
            summary.location = true
        }
    }

    /// Returns the number of settings written.
    private static func merge(_ preferences: BackupEnvelope.Preferences, into db: Database, origin: SettingOrigin,
                              stamp: Date) throws -> Int {
        var written = 0
        func put<Value>(_ value: Value, _ key: SettingKey<Value>) throws {
            if try SettingsRepository.importValue(value, for: key, in: db, origin: origin, updatedAt: stamp) {
                written += 1
            }
        }
        try put(preferences.theme, .theme)
        try put(preferences.textSize, .textSize)
        try put(preferences.lineSpacing, .lineSpacing)
        try put(preferences.haptics, .haptics)
        if let longOrder = preferences.longOrder { try put(longOrder, .longOrder) }
        if let answered = preferences.longOrderPromptAnswered { try put(answered, .longOrderPromptAnswered) }
        return written
    }
}
