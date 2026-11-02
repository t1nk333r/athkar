import Foundation
import GRDB

/// What an import wrote, or would write on confirmation (a dry run): the review screen's list.
public struct BackupImportSummary: Equatable, Sendable {
    /// Adhkar sessions (a date and a period).
    public var adhkar = 0
    /// Dates of ruqyah progress or a ruqyah sura.
    public var ruqyah = 0
    /// Dates of «سور» pages or suras.
    public var suwar = 0
    /// Dates of «مسبحة» counts.
    public var tasbih = 0
    /// Prayer records.
    public var prayers = 0
    /// Reminder rules.
    public var reminders = 0
    /// `settings` rows, the «مسبحة» phrases and the selected «سور» sura included.
    public var settings = 0
    /// The location profile.
    public var location = false

    public init() {}

    /// Nothing in the file is missing here.
    public var isEmpty: Bool {
        adhkar + ruqyah + suwar + tasbih + prayers + reminders + settings == 0 && !location
    }
}

/// Format 2 merge (spec/schema.md "Import", envelope format 2). The device wins wherever it has something: a unit is
/// imported only when the device has nothing for it, and imported rows are stamped with `meta.exportedAt`. So a file
/// can be imported over existing progress, and importing it again writes nothing.
///
/// Units: adhkar `(date, period)` (completion and item rows together, as format 1); ruqyah completion `(date)`,
/// counts `(date, segment)` (clamped to the segment's repeat, unknown segments dropped, as format 1), sura `(date,
/// sura)`; «سور» `(date, sura)` (its pages and completion together); «مسبحة» `(date)` (the day's counts together,
/// so the first-use order stays whole); a prayer record `(date, prayer)`, imported over a device record only when
/// that is still unrecorded; a reminder rule `(id)` with its last shown date; the location (only into an empty
/// profile, as `import`). Settings are written with origin `native`, so they replace a PWA's rows but never a
/// native one.
extension BackupImporter {
    @discardableResult
    public func importNative(_ backup: NativeBackup, dryRun: Bool = false) throws -> BackupImportSummary {
        try backup.validate()
        let stamp = backup.meta.exportedAt
        return try write(dryRun: dryRun) { db, summary in
            summary.settings += try Self.mergeSettings(backup, into: db, stamp: stamp)
            summary.adhkar += try Self.merge(backup.adhkar, into: db, stamp: stamp)
            summary.ruqyah += try Self.merge(backup.ruqyah, segments: content.ruqyahSegments, into: db,
                                             stamp: stamp)
            summary.suwar += try Self.merge(backup.suwar, into: db)
            summary.tasbih += try Self.merge(backup.tasbih, into: db, stamp: stamp)
            summary.prayers += try Self.merge(backup.prayers, into: db, stamp: stamp)
            try Self.merge(backup.reminders, into: db, stamp: stamp, summary: &summary)
        }
    }

    private static func mergeSettings(_ backup: NativeBackup, into db: Database, stamp: Date) throws -> Int {
        var written = 0
        func put<Value>(_ value: Value?, _ key: SettingKey<Value>) throws {
            guard let value else { return }
            if try SettingsRepository.importValue(value, for: key, in: db, origin: .native, updatedAt: stamp) {
                written += 1
            }
        }
        let preferences = backup.preferences
        try put(preferences.theme, .theme)
        try put(preferences.textSize, .textSize)
        try put(preferences.lineSpacing, .lineSpacing)
        try put(preferences.haptics, .haptics)
        try put(preferences.longOrder, .longOrder)
        try put(preferences.longOrderPromptAnswered, .longOrderPromptAnswered)
        try put(preferences.homePrayerRow, .homePrayerRow)
        let prayer = backup.prayerSettings
        try put(prayer.calculationMethod, .calculationMethod)
        try put(prayer.asrSchool, .asrSchool)
        try put(prayer.highLatitudeRule, .highLatitudeRule)
        try put(prayer.adjustments, .prayerAdjustments)
        try put(prayer.hijriOffset, .hijriOffset)
        try put(prayer.iqamaDelays, .iqamaDelays)
        try put(backup.suwar.selected, .suwarSelectedSura)
        try put(backup.tasbih.selected, .tasbihSelected)
        try put(backup.tasbih.target, .tasbihTarget)
        try put(backup.tasbih.phrases, .tasbihCustomPhrases)
        return written
    }

    private static func merge(_ adhkar: NativeBackup.Adhkar, into db: Database, stamp: Date) throws -> Int {
        struct Unit: Hashable {
            var date: String
            var period: Period
        }
        let days = Dictionary(grouping: adhkar.days) { Unit(date: $0.date, period: $0.period) }
        let items = Dictionary(grouping: adhkar.items) { Unit(date: $0.date, period: $0.period) }
        var merged = 0
        for unit in Set(days.keys).union(items.keys).sorted(by: { ($0.date, $0.period.rawValue) < ($1.date, $1.period.rawValue) }) {
            guard try AdhkarRepository.session(in: db, on: unit.date, period: unit.period).isEmpty else { continue }
            let key = Column("local_date") == unit.date && Column("period") == unit.period
            try AdhkarItemProgress.filter(key).deleteAll(db)
            try AdhkarDay.filter(key).deleteAll(db)
            for day in days[unit] ?? [] {
                try AdhkarDay(localDate: day.date, period: day.period, completedAt: day.completedAt,
                              completionOrigin: day.origin).insert(db)
            }
            for item in items[unit] ?? [] {
                try AdhkarItemProgress(localDate: item.date, period: item.period, itemId: item.itemId,
                                       count: item.count, target: item.target, updatedAt: stamp).insert(db)
            }
            merged += 1
        }
        return merged
    }

    /// Returns the number of dates something was written for.
    private static func merge(_ ruqyah: NativeBackup.Ruqyah, segments: [RuqyahSegment], into db: Database,
                              stamp: Date) throws -> Int {
        var dates = Set<String>()
        for day in ruqyah.days where try !RuqyahDay.exists(db, key: day.date) {
            try RuqyahDay(localDate: day.date, completedAt: day.completedAt, completionOrigin: day.origin).insert(db)
            dates.insert(day.date)
        }
        let repeats = Dictionary(segments.map { ($0.id, $0.repeatCount) }, uniquingKeysWith: { first, _ in first })
        for segment in ruqyah.segments {
            guard let repeatCount = repeats[segment.segmentId] else { continue }
            let count = min(segment.count, repeatCount)
            let key: [String: (any DatabaseValueConvertible)?] = ["local_date": segment.date,
                                                                  "segment_id": segment.segmentId]
            if let native = try RuqyahSegmentProgress.fetchOne(db, key: key), native.count > 0 { continue }
            try RuqyahSegmentProgress(localDate: segment.date, segmentId: segment.segmentId, count: count,
                                      updatedAt: stamp).upsert(db)
            if count > 0 { dates.insert(segment.date) }
        }
        for sura in ruqyah.suras {
            let key: [String: (any DatabaseValueConvertible)?] = ["local_date": sura.date, "sura_id": sura.suraId]
            if try RuqyahSuraDay.exists(db, key: key) { continue }
            try RuqyahSuraDay(localDate: sura.date, suraId: sura.suraId, completedAt: sura.completedAt).insert(db)
            dates.insert(sura.date)
        }
        return dates.count
    }

    /// Returns the number of dates something was written for.
    private static func merge(_ suwar: NativeBackup.Suwar, into db: Database) throws -> Int {
        struct Unit: Hashable {
            var date: String
            var suraId: String
        }
        let pages = Dictionary(grouping: suwar.pages) { Unit(date: $0.date, suraId: $0.suraId) }
        let suras = Dictionary(grouping: suwar.suras) { Unit(date: $0.date, suraId: $0.suraId) }
        var dates = Set<String>()
        for unit in Set(pages.keys).union(suras.keys).sorted(by: { ($0.date, $0.suraId) < ($1.date, $1.suraId) }) {
            let rows = Column("local_date") == unit.date && Column("sura_id") == unit.suraId
            guard try SuwarPageRead.filter(rows).fetchCount(db) == 0,
                  try SuwarSuraDay.filter(rows).fetchCount(db) == 0
            else { continue }
            var wrote = false
            for page in pages[unit] ?? [] {
                // A page read on that date under another sura (an ID reused across packs) stays as it is.
                let key: [String: (any DatabaseValueConvertible)?] = ["local_date": page.date, "page_id": page.pageId]
                if try SuwarPageRead.exists(db, key: key) { continue }
                try SuwarPageRead(localDate: page.date, suraId: page.suraId, pageId: page.pageId, readAt: page.readAt)
                    .insert(db)
                wrote = true
            }
            for sura in suras[unit] ?? [] {
                try SuwarSuraDay(localDate: sura.date, suraId: sura.suraId, completedAt: sura.completedAt).insert(db)
                wrote = true
            }
            if wrote { dates.insert(unit.date) }
        }
        return dates.count
    }

    /// Returns the number of dates written.
    private static func merge(_ tasbih: NativeBackup.Tasbih, into db: Database, stamp: Date) throws -> Int {
        let days = Dictionary(grouping: tasbih.counts, by: \.date)
        var merged = 0
        for date in days.keys.sorted() {
            guard try TasbihCount.filter(Column("local_date") == date).fetchCount(db) == 0 else { continue }
            for count in days[date]! {
                try TasbihCount(localDate: count.date, phraseKey: count.phrase, count: count.count,
                                firstUse: count.firstUse, updatedAt: stamp).insert(db)
            }
            merged += 1
        }
        return merged
    }

    private static func merge(_ prayers: NativeBackup.Prayers, into db: Database, stamp: Date) throws -> Int {
        var merged = 0
        for record in prayers.records {
            let key: [String: (any DatabaseValueConvertible)?] = ["calculation_date": record.date,
                                                                  "prayer_key": record.prayer.rawValue]
            if let existing = try PrayerRecord.fetchOne(db, key: key) {
                guard existing.state == .unrecorded, record.state != .unrecorded else { continue }
            }
            try PrayerRecord(calculationDate: record.date, prayerKey: record.prayer, zoneId: record.zone,
                             scheduledAt: record.scheduledAt, profileVersion: record.profile, state: record.state,
                             timing: record.timing, noonPrayer: record.noonPrayer, loggedAt: record.loggedAt,
                             updatedAt: stamp).upsert(db)
            merged += 1
        }
        return merged
    }

    private static func merge(_ reminders: NativeBackup.Reminders, into db: Database, stamp: Date,
                              summary: inout BackupImportSummary) throws {
        for rule in reminders.rules where try !ReminderRule.exists(db, key: rule.id) {
            try ReminderRule(id: rule.id, kind: rule.kind, prayerKey: rule.prayer, offsetMinutes: rule.offsetMinutes,
                             localTime: rule.localTime, weekdayMask: rule.weekdays, enabled: rule.enabled,
                             updatedAt: stamp).insert(db)
            summary.reminders += 1
        }
        for (ruleId, date) in reminders.lastShown.sorted(by: { $0.key < $1.key })
        where try !ReminderState.exists(db, key: ruleId) {
            try ReminderState(ruleId: ruleId, lastShownLocalDate: date).insert(db)
        }
        if let location = reminders.location, try LocationProfile.fetchCount(db) == 0 {
            try LocationProfile(label: location.label, latitude: location.latitude, longitude: location.longitude,
                                zoneId: location.zoneId, source: .imported, updatedAt: location.updatedAt).insert(db)
            summary.location = true
        }
    }
}
