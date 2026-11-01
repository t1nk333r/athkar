import Foundation

/// `athkar-backup` format 2 (spec/backup/envelope-v2.md, envelope-v2.schema.json): the native app's own export.
///
/// Format 1 carries only what the PWAs hold. Format 2 carries every table the user writes (spec/schema.md), so a
/// restore on another device loses no worship data: adhkar, ruqyah with its suras, «سور», «مسبحة», the prayer
/// tracker, the reminder rules, the settings with the calculation profile (`prayerSettings`, NATIVE_APP_PLAN.md
/// §6.4), and the location only when the user includes it. Rows are listed as the tables hold them, sorted by their
/// keys. A setting is written only when the user set it; an absent one reads as its default.
///
/// Keys whose value may be `null` are always written, as `null` when empty (``Nullable``); optional keys are omitted
/// when absent. Read and write files only with `decode(_:)` and `encoded()`.
public struct NativeBackup: Codable, Equatable, Sendable {
    public static let format = 2
    /// `meta.app`: any native app (iOS, later Android) writes and reads the same format.
    public static let app = "athkar-native"

    public var meta: Meta
    public var preferences: Preferences
    public var prayerSettings: PrayerSettings
    public var adhkar: Adhkar
    public var ruqyah: Ruqyah
    public var suwar: Suwar
    public var tasbih: Tasbih
    public var prayers: Prayers
    public var reminders: Reminders

    public init(meta: Meta, preferences: Preferences = .init(), prayerSettings: PrayerSettings = .init(),
                adhkar: Adhkar = .init(), ruqyah: Ruqyah = .init(), suwar: Suwar = .init(), tasbih: Tasbih = .init(),
                prayers: Prayers = .init(), reminders: Reminders = .init()) {
        self.meta = meta
        self.preferences = preferences
        self.prayerSettings = prayerSettings
        self.adhkar = adhkar
        self.ruqyah = ruqyah
        self.suwar = suwar
        self.tasbih = tasbih
        self.prayers = prayers
        self.reminders = reminders
    }

    public struct Meta: Codable, Equatable, Sendable {
        public var format: Int
        public var app: String
        public var exportedAt: Date
        /// IANA zone of the exporting device. Every date is the local date its row was written on.
        public var timeZone: String

        public init(exportedAt: Date, timeZone: String) {
            format = NativeBackup.format
            app = NativeBackup.app
            self.exportedAt = exportedAt
            self.timeZone = timeZone
        }
    }

    /// The `settings` rows for appearance and the decks; absent means the row does not exist.
    public struct Preferences: Codable, Equatable, Sendable {
        public var theme: Theme?
        public var textSize: TextSize?
        public var lineSpacing: LineSpacing?
        public var haptics: Bool?
        public var longOrder: LongOrder?
        public var longOrderPromptAnswered: Bool?
        public var homePrayerRow: Bool?

        public init(theme: Theme? = nil, textSize: TextSize? = nil, lineSpacing: LineSpacing? = nil,
                    haptics: Bool? = nil, longOrder: LongOrder? = nil, longOrderPromptAnswered: Bool? = nil,
                    homePrayerRow: Bool? = nil) {
            self.theme = theme
            self.textSize = textSize
            self.lineSpacing = lineSpacing
            self.haptics = haptics
            self.longOrder = longOrder
            self.longOrderPromptAnswered = longOrderPromptAnswered
            self.homePrayerRow = homePrayerRow
        }
    }

    /// The calculation profile's `settings` rows (NATIVE_APP_PLAN.md §6.4 `prayerSettings`): every method, native
    /// presets included, the high-latitude rule, the minute adjustments and the Hijri offset.
    public struct PrayerSettings: Codable, Equatable, Sendable {
        public var calculationMethod: CalculationMethod?
        public var asrSchool: AsrSchool?
        public var highLatitudeRule: HighLatitudeRule?
        public var adjustments: PrayerAdjustments?
        public var hijriOffset: Int?

        public init(calculationMethod: CalculationMethod? = nil, asrSchool: AsrSchool? = nil,
                    highLatitudeRule: HighLatitudeRule? = nil, adjustments: PrayerAdjustments? = nil,
                    hijriOffset: Int? = nil) {
            self.calculationMethod = calculationMethod
            self.asrSchool = asrSchool
            self.highLatitudeRule = highLatitudeRule
            self.adjustments = adjustments
            self.hijriOffset = hijriOffset
        }
    }

    /// `adhkar_days` and `adhkar_item_progress`, every date.
    public struct Adhkar: Codable, Equatable, Sendable {
        public var days: [Day]
        public var items: [Item]

        public init(days: [Day] = [], items: [Item] = []) {
            self.days = days
            self.items = items
        }

        public struct Day: Codable, Equatable, Sendable {
            public var date: String
            public var period: Period
            @Nullable public var completedAt: Date?
            public var origin: CompletionOrigin

            public init(date: String, period: Period, completedAt: Date?, origin: CompletionOrigin) {
                self.date = date
                self.period = period
                self.completedAt = completedAt
                self.origin = origin
            }
        }

        public struct Item: Codable, Equatable, Sendable {
            public var date: String
            public var period: Period
            public var itemId: String
            @Nullable public var count: Int?
            @Nullable public var target: Int?

            public init(date: String, period: Period, itemId: String, count: Int?, target: Int?) {
                self.date = date
                self.period = period
                self.itemId = itemId
                self.count = count
                self.target = target
            }
        }
    }

    /// `ruqyah_days`, `ruqyah_segment_progress` and `ruqyah_sura_days`.
    public struct Ruqyah: Codable, Equatable, Sendable {
        public var days: [Day]
        public var segments: [Segment]
        public var suras: [SuraDay]

        public init(days: [Day] = [], segments: [Segment] = [], suras: [SuraDay] = []) {
            self.days = days
            self.segments = segments
            self.suras = suras
        }

        public struct Day: Codable, Equatable, Sendable {
            public var date: String
            public var completedAt: Date
            public var origin: CompletionOrigin

            public init(date: String, completedAt: Date, origin: CompletionOrigin) {
                self.date = date
                self.completedAt = completedAt
                self.origin = origin
            }
        }

        public struct Segment: Codable, Equatable, Sendable {
            public var date: String
            public var segmentId: String
            public var count: Int

            public init(date: String, segmentId: String, count: Int) {
                self.date = date
                self.segmentId = segmentId
                self.count = count
            }
        }
    }

    /// A sura completed on a date: `ruqyah_sura_days`, `suwar_sura_days`.
    public struct SuraDay: Codable, Equatable, Sendable {
        public var date: String
        public var suraId: String
        public var completedAt: Date

        public init(date: String, suraId: String, completedAt: Date) {
            self.date = date
            self.suraId = suraId
            self.completedAt = completedAt
        }
    }

    /// `suwar_page_reads`, `suwar_sura_days` and the `suwar_selected_sura` setting.
    public struct Suwar: Codable, Equatable, Sendable {
        public var selected: String?
        public var pages: [Page]
        public var suras: [SuraDay]

        public init(selected: String? = nil, pages: [Page] = [], suras: [SuraDay] = []) {
            self.selected = selected
            self.pages = pages
            self.suras = suras
        }

        public struct Page: Codable, Equatable, Sendable {
            public var date: String
            public var suraId: String
            public var pageId: String
            public var readAt: Date

            public init(date: String, suraId: String, pageId: String, readAt: Date) {
                self.date = date
                self.suraId = suraId
                self.pageId = pageId
                self.readAt = readAt
            }
        }
    }

    /// `tasbih_counts` and the three «مسبحة» settings.
    public struct Tasbih: Codable, Equatable, Sendable {
        public var selected: String?
        public var target: Int?
        public var phrases: [String]?
        public var counts: [Count]

        public init(selected: String? = nil, target: Int? = nil, phrases: [String]? = nil, counts: [Count] = []) {
            self.selected = selected
            self.target = target
            self.phrases = phrases
            self.counts = counts
        }

        public struct Count: Codable, Equatable, Sendable {
            public var date: String
            public var phrase: String
            public var count: Int
            public var firstUse: Int

            public init(date: String, phrase: String, count: Int, firstUse: Int) {
                self.date = date
                self.phrase = phrase
                self.count = count
                self.firstUse = firstUse
            }
        }
    }

    /// `prayer_records`, metadata included (spec/tracker/tracker.md).
    public struct Prayers: Codable, Equatable, Sendable {
        public var records: [Record]

        public init(records: [Record] = []) {
            self.records = records
        }

        public struct Record: Codable, Equatable, Sendable {
            public var date: String
            public var prayer: ObligatoryPrayer
            public var zone: String
            @Nullable public var scheduledAt: Date?
            public var profile: String
            public var state: PrayerRecordState
            @Nullable public var timing: PrayerTiming?
            @Nullable public var noonPrayer: NoonPrayer?
            @Nullable public var loggedAt: Date?

            public init(date: String, prayer: ObligatoryPrayer, zone: String, scheduledAt: Date?, profile: String,
                        state: PrayerRecordState, timing: PrayerTiming?, noonPrayer: NoonPrayer?, loggedAt: Date?) {
                self.date = date
                self.prayer = prayer
                self.zone = zone
                self.scheduledAt = scheduledAt
                self.profile = profile
                self.state = state
                self.timing = timing
                self.noonPrayer = noonPrayer
                self.loggedAt = loggedAt
            }
        }
    }

    /// `reminder_rules`, `reminder_state` (rule ID → the last local date its notification was shown) and, only when
    /// the user included it, `location_profiles`.
    public struct Reminders: Codable, Equatable, Sendable {
        public var rules: [Rule]
        public var lastShown: [String: String]
        public var location: Location?

        public init(rules: [Rule] = [], lastShown: [String: String] = [:], location: Location? = nil) {
            self.rules = rules
            self.lastShown = lastShown
            self.location = location
        }

        public struct Rule: Codable, Equatable, Sendable {
            public var id: String
            public var kind: ReminderRule.Kind
            @Nullable public var prayer: ReminderRule.PrayerKey?
            @Nullable public var offsetMinutes: Int?
            @Nullable public var localTime: String?
            /// Bit *n* is weekday *n* + 1 in `Calendar` numbering; 127 is every day.
            public var weekdays: Int
            public var enabled: Bool

            public init(id: String, kind: ReminderRule.Kind, prayer: ReminderRule.PrayerKey?, offsetMinutes: Int?,
                        localTime: String?, weekdays: Int, enabled: Bool) {
                self.id = id
                self.kind = kind
                self.prayer = prayer
                self.offsetMinutes = offsetMinutes
                self.localTime = localTime
                self.weekdays = weekdays
                self.enabled = enabled
            }
        }

        /// Coordinates rounded to 2 decimals, as stored (§7.4).
        public struct Location: Codable, Equatable, Sendable {
            public var latitude: Double
            public var longitude: Double
            @Nullable public var label: String?
            @Nullable public var zoneId: String?
            @Nullable public var updatedAt: Date?

            public init(latitude: Double, longitude: Double, label: String?, zoneId: String?, updatedAt: Date?) {
                self.latitude = latitude
                self.longitude = longitude
                self.label = label
                self.zoneId = zoneId
                self.updatedAt = updatedAt
            }
        }
    }
}

/// A key that is always written, as `null` when the value is absent, and must be present when read.
@propertyWrapper
public struct Nullable<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var wrappedValue: Value?

    public init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? nil : try container.decode(Value.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue { try container.encode(wrappedValue) } else { try container.encodeNil() }
    }
}

// MARK: - Reading and writing files

extension NativeBackup {
    /// Decodes and validates a format 2 file, accepting and rejecting what tools/backup-validate.mjs does, read as
    /// `JSON.parse` reads it (`BackupJSON.parse`).
    public static func decode(_ data: Data) throws -> NativeBackup {
        let (root, json, format) = try BackupJSON.parse(data)
        guard format == Self.format else { throw BackupError.unsupportedFormat(format) }
        let backup: NativeBackup
        do {
            backup = try BackupJSON.decoder.decode(NativeBackup.self, from: json)
        } catch {
            throw BackupError.malformed(BackupJSON.describe(error))
        }
        try KeyShape.native.check(root, path: "")
        try backup.validate()
        return backup
    }

    /// Pretty-printed JSON with sorted keys and instants in `toISOString()` form.
    public func encoded() throws -> Data {
        try BackupJSON.encoder.encode(self)
    }

    /// The rules of envelope-v2.schema.json and tools/backup-validate.mjs that the types cannot express: the app,
    /// calendar dates, ranges, each table's key unique, IDs without U+0000, and the tables' own checks.
    func validate() throws {
        func invalid(_ path: String, _ reason: String) -> BackupError { .invalid(path: path, reason: reason) }
        func checkDate(_ value: String, _ path: String) throws {
            guard LocalDate.isValid(value) else { throw invalid(path, "\(value) is not a YYYY-MM-DD calendar date") }
        }
        /// SQLite binds text up to the first U+0000, so such an ID would be stored truncated (and could collide).
        func checkID(_ id: String, _ path: String) throws {
            guard !id.isEmpty else { throw invalid(path, "empty") }
            guard !id.utf8.contains(0) else { throw invalid(path, "contains U+0000") }
        }
        func checkRange(_ value: Int, _ range: ClosedRange<Int>, _ path: String) throws {
            guard range.contains(value) else { throw invalid(path, "\(value) is not in \(range)") }
        }
        /// The table's key is unique. Parts compare as code points, as SQLite compares text (Swift's `==` would equate
        /// canonically equivalent spellings, which are two rows); no part contains U+0000.
        func checkUnique(_ keys: [[String]], _ path: String) throws {
            var seen = Set<[UInt8]>()
            for (index, key) in keys.enumerated() where !seen.insert(Array(key.joined(separator: "\u{0}").utf8)).inserted {
                throw invalid("\(path)[\(index)]", "repeats an earlier row's key")
            }
        }
        let maxSafe = Int(BackupEnvelope.maxSafeInteger)

        guard meta.app == Self.app else { throw invalid("meta.app", "\(meta.app) is not \(Self.app)") }
        guard !meta.timeZone.isEmpty else { throw invalid("meta.timeZone", "empty") }

        if let adjustments = prayerSettings.adjustments {
            for (name, value) in [("fajr", adjustments.fajr), ("sunrise", adjustments.sunrise),
                                  ("dhuhr", adjustments.dhuhr), ("asr", adjustments.asr),
                                  ("maghrib", adjustments.maghrib), ("isha", adjustments.isha)] {
                try checkRange(value, -30...30, "prayerSettings.adjustments.\(name)")
            }
        }
        if let offset = prayerSettings.hijriOffset { try checkRange(offset, -2...2, "prayerSettings.hijriOffset") }

        for (index, day) in adhkar.days.enumerated() {
            try checkDate(day.date, "adhkar.days[\(index)].date")
        }
        try checkUnique(adhkar.days.map { [$0.date, $0.period.rawValue] }, "adhkar.days")
        for (index, item) in adhkar.items.enumerated() {
            let path = "adhkar.items[\(index)]"
            try checkDate(item.date, "\(path).date")
            try checkID(item.itemId, "\(path).itemId")
            guard item.count != nil || item.target != nil else { throw invalid(path, "neither count nor target") }
            if let count = item.count { try checkRange(count, 0...maxSafe, "\(path).count") }
            if let target = item.target { try checkRange(target, 0...maxSafe, "\(path).target") }
        }
        try checkUnique(adhkar.items.map { [$0.date, $0.period.rawValue, $0.itemId] }, "adhkar.items")

        for (index, day) in ruqyah.days.enumerated() {
            try checkDate(day.date, "ruqyah.days[\(index)].date")
            guard day.origin != .manual else { throw invalid("ruqyah.days[\(index)].origin", "ruqyah has no manual") }
        }
        try checkUnique(ruqyah.days.map { [$0.date] }, "ruqyah.days")
        for (index, segment) in ruqyah.segments.enumerated() {
            try checkDate(segment.date, "ruqyah.segments[\(index)].date")
            try checkID(segment.segmentId, "ruqyah.segments[\(index)].segmentId")
            try checkRange(segment.count, 0...maxSafe, "ruqyah.segments[\(index)].count")
        }
        try checkUnique(ruqyah.segments.map { [$0.date, $0.segmentId] }, "ruqyah.segments")
        for (name, suras) in [("ruqyah.suras", ruqyah.suras), ("suwar.suras", suwar.suras)] {
            for (index, sura) in suras.enumerated() {
                try checkDate(sura.date, "\(name)[\(index)].date")
                try checkID(sura.suraId, "\(name)[\(index)].suraId")
            }
            try checkUnique(suras.map { [$0.date, $0.suraId] }, name)
        }

        if let selected = suwar.selected { try checkID(selected, "suwar.selected") }
        for (index, page) in suwar.pages.enumerated() {
            try checkDate(page.date, "suwar.pages[\(index)].date")
            try checkID(page.suraId, "suwar.pages[\(index)].suraId")
            try checkID(page.pageId, "suwar.pages[\(index)].pageId")
        }
        try checkUnique(suwar.pages.map { [$0.date, $0.pageId] }, "suwar.pages")

        if let selected = tasbih.selected { try checkID(selected, "tasbih.selected") }
        if let target = tasbih.target { try checkRange(target, 0...9999, "tasbih.target") }
        if let phrases = tasbih.phrases {
            guard phrases.count <= 8 else { throw invalid("tasbih.phrases", "more than 8 phrases") }
            for (index, phrase) in phrases.enumerated() {
                try checkID(phrase, "tasbih.phrases[\(index)]")
                guard phrase.utf16.count <= 60 else { throw invalid("tasbih.phrases[\(index)]", "longer than 60") }
            }
        }
        for (index, count) in tasbih.counts.enumerated() {
            let path = "tasbih.counts[\(index)]"
            try checkDate(count.date, "\(path).date")
            try checkID(count.phrase, "\(path).phrase")
            // SQLite's length() counts characters as code points.
            guard count.phrase.unicodeScalars.count <= 62 else { throw invalid("\(path).phrase", "longer than 62") }
            try checkRange(count.count, 1...TasbihCount.maxCount, "\(path).count")
            try checkRange(count.firstUse, 1...maxSafe, "\(path).firstUse")
        }
        try checkUnique(tasbih.counts.map { [$0.date, $0.phrase] }, "tasbih.counts")
        try checkUnique(tasbih.counts.map { [$0.date, String($0.firstUse)] }, "tasbih.counts")

        for (index, record) in prayers.records.enumerated() {
            let path = "prayers.records[\(index)]"
            try checkDate(record.date, "\(path).date")
            try checkID(record.zone, "\(path).zone")
            try checkID(record.profile, "\(path).profile")
            guard record.timing == nil || record.state == .prayed else {
                throw invalid("\(path).timing", "only a prayed record has a timing")
            }
            if record.noonPrayer != nil {
                guard record.state == .prayed, record.prayer == .dhuhr, LocalDate.isFriday(record.date) else {
                    throw invalid("\(path).noonPrayer", "only a prayed Dhuhr on a Friday has a noon prayer")
                }
            }
            guard (record.loggedAt == nil) == (record.state == .unrecorded) else {
                throw invalid("\(path).loggedAt", "set exactly when the prayer is recorded")
            }
        }
        try checkUnique(prayers.records.map { [$0.date, $0.prayer.rawValue] }, "prayers.records")

        for (index, rule) in reminders.rules.enumerated() {
            let path = "reminders.rules[\(index)]"
            try checkID(rule.id, "\(path).id")
            if rule.kind == .adhkarMorning || rule.kind == .adhkarEvening {
                guard rule.id == rule.kind.rawValue else { throw invalid("\(path).id", "an adhkar rule's ID is its kind") }
            }
            guard (rule.prayer == nil) == (rule.offsetMinutes == nil) else {
                throw invalid("\(path).offsetMinutes", "set exactly when the rule follows a prayer")
            }
            guard (rule.prayer == nil) != (rule.localTime == nil) else {
                throw invalid("\(path).localTime", "set exactly when the rule follows no prayer")
            }
            if let time = rule.localTime, !Self.isLocalTime(time) {
                throw invalid("\(path).localTime", "\(time) is not HH:MM")
            }
            try checkRange(rule.weekdays, 0...ReminderRule.everyDay, "\(path).weekdays")
        }
        try checkUnique(reminders.rules.map { [$0.id] }, "reminders.rules")
        let ruleIds = Set(reminders.rules.map { Array($0.id.utf8) })
        for (ruleId, date) in reminders.lastShown.sorted(by: { $0.key < $1.key }) {
            guard ruleIds.contains(Array(ruleId.utf8)) else { throw invalid("reminders.lastShown.\(ruleId)", "no such rule") }
            try checkDate(date, "reminders.lastShown.\(ruleId)")
        }
        if let location = reminders.location {
            guard (-90...90).contains(location.latitude) else {
                throw invalid("reminders.location.latitude", "\(location.latitude) is out of range")
            }
            guard (-180...180).contains(location.longitude) else {
                throw invalid("reminders.location.longitude", "\(location.longitude) is out of range")
            }
            if let zone = location.zoneId { try checkID(zone, "reminders.location.zoneId") }
        }
    }

    /// `HH:MM`, 00:00 … 23:59 (`reminder_rules.local_time`).
    static func isLocalTime(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), let minute = Int(parts[1])
        else { return false }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }
}

extension KeyShape {
    /// The object keys envelope-v2.schema.json allows, and where it allows `null`.
    static let native: KeyShape = {
        func object(_ keys: [String], nullable: [String] = []) -> KeyShape {
            .object(Dictionary(uniqueKeysWithValues: keys.map { ($0, .value) } + nullable.map { ($0, .nullable) }))
        }
        let sura = KeyShape.list(object(["date", "suraId", "completedAt"]))
        return .object([
            "meta": object(["format", "app", "exportedAt", "timeZone"]),
            "preferences": object(["theme", "textSize", "lineSpacing", "haptics", "longOrder",
                                   "longOrderPromptAnswered", "homePrayerRow"]),
            "prayerSettings": .object([
                "calculationMethod": .value, "asrSchool": .value, "highLatitudeRule": .value, "hijriOffset": .value,
                "adjustments": object(["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]),
            ]),
            "adhkar": .object([
                "days": .list(object(["date", "period", "origin"], nullable: ["completedAt"])),
                "items": .list(object(["date", "period", "itemId"], nullable: ["count", "target"])),
            ]),
            "ruqyah": .object([
                "days": .list(object(["date", "completedAt", "origin"])),
                "segments": .list(object(["date", "segmentId", "count"])),
                "suras": sura,
            ]),
            "suwar": .object([
                "selected": .value,
                "pages": .list(object(["date", "suraId", "pageId", "readAt"])),
                "suras": sura,
            ]),
            "tasbih": .object([
                "selected": .value, "target": .value, "phrases": .list(.value),
                "counts": .list(object(["date", "phrase", "count", "firstUse"])),
            ]),
            "prayers": .object([
                "records": .list(object(["date", "prayer", "zone", "profile", "state"],
                                        nullable: ["scheduledAt", "timing", "noonPrayer", "loggedAt"])),
            ]),
            "reminders": .object([
                "rules": .list(object(["id", "kind", "weekdays", "enabled"],
                                      nullable: ["prayer", "offsetMinutes", "localTime"])),
                "lastShown": .map(.value),
                "location": object(["latitude", "longitude"], nullable: ["label", "zoneId", "updatedAt"]),
            ]),
        ])
    }()
}
