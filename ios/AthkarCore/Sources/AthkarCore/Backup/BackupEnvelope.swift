import Foundation

/// Which PWA wrote a backup file (`meta.app`).
public enum BackupApp: String, Codable, Sendable, CaseIterable {
    case athkarPWA = "athkar-pwa"
    case ruqyahPWA = "ruqyah-pwa"
}

public enum BackupError: Error, Equatable, Sendable {
    /// Not JSON, or JSON that does not have the envelope's shape.
    case malformed(String)
    /// `meta.format` is not 1.
    case unsupportedFormat(Int)
    /// Well-formed JSON that breaks a rule of spec/backup/envelope-v1.schema.json.
    case invalid(path: String, reason: String)
}

/// `athkar-backup` format 1 (spec/backup/envelope-v1.md, envelope-v1.schema.json).
///
/// Optional properties are sections or keys that may be absent; they are omitted when encoding. Keys the
/// schema requires but allows to be `null` are non-optional in shape: they are always written, as `null`
/// when empty. Instants are `Date`, read and written in the `toISOString()` form only by `decode(_:)` and
/// `encoded()`, so use those rather than a bare `JSONDecoder`/`JSONEncoder`.
public struct BackupEnvelope: Codable, Equatable, Sendable {
    public var meta: Meta
    public var adhkar: Adhkar?
    public var ruqyah: Ruqyah?
    public var reminders: Reminders?
    public var preferences: Preferences?

    public init(meta: Meta, adhkar: Adhkar? = nil, ruqyah: Ruqyah? = nil, reminders: Reminders? = nil,
                preferences: Preferences? = nil) {
        self.meta = meta
        self.adhkar = adhkar
        self.ruqyah = ruqyah
        self.reminders = reminders
        self.preferences = preferences
    }

    public static let format = 1

    public struct Meta: Codable, Equatable, Sendable {
        public var format: Int
        public var app: BackupApp
        public var exportedAt: Date
        /// IANA zone every `date` field is local to.
        public var timeZone: String

        public init(app: BackupApp, exportedAt: Date, timeZone: String) {
            self.format = BackupEnvelope.format
            self.app = app
            self.exportedAt = exportedAt
            self.timeZone = timeZone
        }
    }

    /// `{morning, evening}` pair; both keys are required.
    public struct PerPeriod<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
        public var morning: Value
        public var evening: Value

        public init(morning: Value, evening: Value) {
            self.morning = morning
            self.evening = evening
        }

        public subscript(period: Period) -> Value {
            get { period == .morning ? morning : evening }
            set { if period == .morning { morning = newValue } else { evening = newValue } }
        }
    }

    public struct Adhkar: Codable, Equatable, Sendable {
        public var today: Today
        /// Newest first, at most 7, all before `today.date`.
        public var history: [HistoryEntry]

        public init(today: Today, history: [HistoryEntry]) {
            self.today = today
            self.history = history
        }

        /// `athkar-progress-v2` for the export's local date.
        public struct Today: Codable, Equatable, Sendable {
            public var date: String
            /// Item ID → tap count, as numbers: not floored, may exceed the target.
            public var progress: PerPeriod<[String: Double]>
            /// Item ID → chosen target.
            public var targets: PerPeriod<[String: Double]>
            public var completedAt: PerPeriod<Date?>
            public var manualCompletion: PerPeriod<Bool>

            public init(date: String, progress: PerPeriod<[String: Double]>, targets: PerPeriod<[String: Double]>,
                        completedAt: PerPeriod<Date?>, manualCompletion: PerPeriod<Bool>) {
                self.date = date
                self.progress = progress
                self.targets = targets
                self.completedAt = completedAt
                self.manualCompletion = manualCompletion
            }
        }

        public struct HistoryEntry: Codable, Equatable, Sendable {
            public var date: String
            public var morning: Bool
            public var evening: Bool
            public var morningAt: Date?
            public var eveningAt: Date?

            public init(date: String, morning: Bool, evening: Bool, morningAt: Date?, eveningAt: Date?) {
                self.date = date
                self.morning = morning
                self.evening = evening
                self.morningAt = morningAt
                self.eveningAt = eveningAt
            }

            private enum CodingKeys: String, CodingKey {
                case date, morning, evening, morningAt, eveningAt
            }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                date = try container.decode(String.self, forKey: .date)
                morning = try container.decode(Bool.self, forKey: .morning)
                evening = try container.decode(Bool.self, forKey: .evening)
                morningAt = try container.decode(Date?.self, forKey: .morningAt)
                eveningAt = try container.decode(Date?.self, forKey: .eveningAt)
            }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(date, forKey: .date)
                try container.encode(morning, forKey: .morning)
                try container.encode(evening, forKey: .evening)
                try container.encode(morningAt, forKey: .morningAt)
                try container.encode(eveningAt, forKey: .eveningAt)
            }
        }
    }

    public struct Ruqyah: Codable, Equatable, Sendable {
        public var today: Today
        /// Local date → completion, at most 365, none after `today.date`.
        public var history: [String: HistoryEntry]

        public init(today: Today, history: [String: HistoryEntry]) {
            self.today = today
            self.history = history
        }

        /// `ruqyah-daily-v1` for the export's local date.
        public struct Today: Codable, Equatable, Sendable {
            public var date: String
            /// Segment ID → count, already clamped to the segment's `repeat`.
            public var counts: [String: Int]

            public init(date: String, counts: [String: Int]) {
                self.date = date
                self.counts = counts
            }
        }

        public struct HistoryEntry: Codable, Equatable, Sendable {
            public var completedAt: Date

            public init(completedAt: Date) {
                self.completedAt = completedAt
            }
        }
    }

    /// `athkar-reminders-v2`.
    public struct Reminders: Codable, Equatable, Sendable {
        public var morning: Toggle
        public var evening: Toggle
        public var calculationMethod: CalculationMethod
        public var asrSchool: AsrSchool
        /// Local date each period's reminder was last shown.
        public var lastShown: PerPeriod<String?>
        /// Present only when the user chose to include it in this export.
        public var location: Location?

        public init(morning: Toggle, evening: Toggle, calculationMethod: CalculationMethod, asrSchool: AsrSchool,
                    lastShown: PerPeriod<String?>, location: Location?) {
            self.morning = morning
            self.evening = evening
            self.calculationMethod = calculationMethod
            self.asrSchool = asrSchool
            self.lastShown = lastShown
            self.location = location
        }

        public subscript(period: Period) -> Toggle {
            period == .morning ? morning : evening
        }

        public struct Toggle: Codable, Equatable, Sendable {
            public var enabled: Bool

            public init(enabled: Bool) {
                self.enabled = enabled
            }
        }

        public struct Location: Codable, Equatable, Sendable {
            public var latitude: Double
            public var longitude: Double
            public var updatedAt: Date?

            public init(latitude: Double, longitude: Double, updatedAt: Date?) {
                self.latitude = latitude
                self.longitude = longitude
                self.updatedAt = updatedAt
            }

            private enum CodingKeys: String, CodingKey {
                case latitude, longitude, updatedAt
            }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                latitude = try container.decode(Double.self, forKey: .latitude)
                longitude = try container.decode(Double.self, forKey: .longitude)
                updatedAt = try container.decode(Date?.self, forKey: .updatedAt)
            }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(latitude, forKey: .latitude)
                try container.encode(longitude, forKey: .longitude)
                try container.encode(updatedAt, forKey: .updatedAt)
            }
        }
    }

    /// Effective appearance and deck preferences. `longOrder` and `longOrderPromptAnswered` are athkar only.
    public struct Preferences: Codable, Equatable, Sendable {
        public var theme: Theme
        public var textSize: TextSize
        public var lineSpacing: LineSpacing
        public var haptics: Bool
        public var longOrder: LongOrder?
        public var longOrderPromptAnswered: Bool?

        public init(theme: Theme, textSize: TextSize, lineSpacing: LineSpacing, haptics: Bool,
                    longOrder: LongOrder? = nil, longOrderPromptAnswered: Bool? = nil) {
            self.theme = theme
            self.textSize = textSize
            self.lineSpacing = lineSpacing
            self.haptics = haptics
            self.longOrder = longOrder
            self.longOrderPromptAnswered = longOrderPromptAnswered
        }
    }
}

// MARK: - Reading and writing files

extension BackupEnvelope {
    /// Decodes and validates a backup file. A leading UTF-8 BOM is ignored.
    public static func decode(_ data: Data) throws -> BackupEnvelope {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let json = data.starts(with: bom) ? data.dropFirst(bom.count) : data[...]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ISOInstant.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "\(text) is not an ISO-8601 UTC instant")
            }
            return date
        }

        // Check the format before the shape, so a future format reports as such rather than as malformed.
        struct Probe: Decodable {
            struct Meta: Decodable { var format: Int }
            var meta: Meta
        }
        let format: Int
        do {
            format = try decoder.decode(Probe.self, from: json).meta.format
        } catch {
            throw BackupError.malformed(Self.describe(error))
        }
        guard format == Self.format else { throw BackupError.unsupportedFormat(format) }

        let envelope: BackupEnvelope
        do {
            envelope = try decoder.decode(BackupEnvelope.self, from: json)
        } catch {
            throw BackupError.malformed(Self.describe(error))
        }
        // `Codable` ignores keys it does not know; the schema forbids them (`additionalProperties: false`).
        try KeyShape.envelope.check(try JSONSerialization.jsonObject(with: json), path: "")
        try envelope.validate()
        return envelope
    }

    /// Pretty-printed JSON with sorted keys and instants in `toISOString()` form.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISOInstant.format(date))
        }
        return try encoder.encode(self)
    }

    /// The rules of envelope-v1.schema.json and tools/backup-validate.mjs that the types cannot express:
    /// sections per app, calendar dates, number ranges, list sizes, history order relative to `today`.
    func validate() throws {
        func invalid(_ path: String, _ reason: String) -> BackupError { .invalid(path: path, reason: reason) }
        func checkDate(_ value: String, _ path: String) throws {
            guard LocalDate.isValid(value) else { throw invalid(path, "\(value) is not a YYYY-MM-DD calendar date") }
        }
        /// JSON numbers the PWAs can write exactly: finite, non-negative, at most `Number.MAX_SAFE_INTEGER`.
        func checkCount(_ value: Double, _ path: String) throws {
            guard value.isFinite, value >= 0, value <= Self.maxSafeInteger else {
                throw invalid(path, "\(value) is not a count between 0 and 2^53 - 1")
            }
        }

        guard !meta.timeZone.isEmpty else { throw invalid("meta.timeZone", "empty") }

        let isAthkar = meta.app == .athkarPWA
        let sections: [(String, Bool)] = [("adhkar", adhkar != nil), ("ruqyah", ruqyah != nil),
                                          ("reminders", reminders != nil), ("preferences", preferences != nil)]
        let required: Set = isAthkar ? ["adhkar", "reminders", "preferences"] : ["ruqyah", "preferences"]
        for (name, present) in sections where present != required.contains(name) {
            throw invalid(name, present ? "not allowed for \(meta.app.rawValue)" : "missing")
        }
        if let preferences {
            for (name, present) in [("longOrder", preferences.longOrder != nil),
                                    ("longOrderPromptAnswered", preferences.longOrderPromptAnswered != nil)]
            where present != isAthkar {
                throw invalid("preferences.\(name)", present ? "athkar-pwa only" : "missing")
            }
        }

        if let adhkar {
            let today = adhkar.today.date
            try checkDate(today, "adhkar.today.date")
            for period in Period.allCases {
                for (name, values) in [("progress", adhkar.today.progress[period]),
                                       ("targets", adhkar.today.targets[period])] {
                    for (itemId, value) in values {
                        try checkCount(value, "adhkar.today.\(name).\(period.rawValue).\(itemId)")
                    }
                }
            }
            guard adhkar.history.count <= 7 else { throw invalid("adhkar.history", "more than 7 entries") }
            var newer = today
            for (index, entry) in adhkar.history.enumerated() {
                try checkDate(entry.date, "adhkar.history[\(index)].date")
                guard entry.date < newer else {
                    throw invalid("adhkar.history[\(index)].date",
                                  "\(entry.date) is not before \(index == 0 ? "today.date" : "the previous entry")")
                }
                newer = entry.date
            }
        }

        if let ruqyah {
            let today = ruqyah.today.date
            try checkDate(today, "ruqyah.today.date")
            for (segmentId, count) in ruqyah.today.counts {
                try checkCount(Double(count), "ruqyah.today.counts.\(segmentId)")
            }
            guard ruqyah.history.count <= 365 else { throw invalid("ruqyah.history", "more than 365 entries") }
            for date in ruqyah.history.keys.sorted() {
                try checkDate(date, "ruqyah.history.\(date)")
                guard date <= today else { throw invalid("ruqyah.history.\(date)", "after today.date") }
            }
        }

        if let reminders {
            for period in Period.allCases {
                if let date = reminders.lastShown[period] {
                    try checkDate(date, "reminders.lastShown.\(period.rawValue)")
                }
            }
            if let location = reminders.location {
                guard (-90...90).contains(location.latitude) else {
                    throw invalid("reminders.location.latitude", "\(location.latitude) is out of range")
                }
                guard (-180...180).contains(location.longitude) else {
                    throw invalid("reminders.location.longitude", "\(location.longitude) is out of range")
                }
            }
        }
    }

    /// `Number.MAX_SAFE_INTEGER`.
    static let maxSafeInteger: Double = 9_007_199_254_740_991

    private static func describe(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return String(describing: error) }
        let (context, summary): (DecodingError.Context, String) = switch error {
        case let .typeMismatch(type, context): (context, "expected \(type)")
        case let .valueNotFound(type, context): (context, "missing \(type) value")
        case let .keyNotFound(key, context): (context, "missing key \(key.stringValue)")
        case let .dataCorrupted(context): (context, context.debugDescription)
        @unknown default: (DecodingError.Context(codingPath: [], debugDescription: ""), "\(error)")
        }
        let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        return path.isEmpty ? summary : "\(path): \(summary)"
    }
}

/// The object keys envelope-v1.schema.json allows, for rejecting unknown ones at any depth. Types and required
/// keys are checked by `Codable`; this only looks at key names.
private indirect enum KeyShape: Sendable {
    /// A scalar or `null`.
    case value
    /// An object with exactly these optional keys.
    case object([String: KeyShape])
    /// An object with arbitrary keys (item IDs, dates) whose values have one shape.
    case map(KeyShape)
    case list(KeyShape)

    static let envelope: KeyShape = {
        let perPeriod = KeyShape.object(["morning": .value, "evening": .value])
        let countsPerPeriod = KeyShape.object(["morning": .map(.value), "evening": .map(.value)])
        let toggle = KeyShape.object(["enabled": .value])
        return .object([
            "meta": .object(["format": .value, "app": .value, "exportedAt": .value, "timeZone": .value]),
            "adhkar": .object([
                "today": .object([
                    "date": .value, "progress": countsPerPeriod, "targets": countsPerPeriod,
                    "completedAt": perPeriod, "manualCompletion": perPeriod,
                ]),
                "history": .list(.object([
                    "date": .value, "morning": .value, "evening": .value, "morningAt": .value, "eveningAt": .value,
                ])),
            ]),
            "ruqyah": .object([
                "today": .object(["date": .value, "counts": .map(.value)]),
                "history": .map(.object(["completedAt": .value])),
            ]),
            "reminders": .object([
                "morning": toggle, "evening": toggle, "calculationMethod": .value, "asrSchool": .value,
                "lastShown": perPeriod,
                "location": .object(["latitude": .value, "longitude": .value, "updatedAt": .value]),
            ]),
            "preferences": .object([
                "theme": .value, "textSize": .value, "lineSpacing": .value, "haptics": .value,
                "longOrder": .value, "longOrderPromptAnswered": .value,
            ]),
        ])
    }()

    /// Throws `.invalid` for the first key `json` has that the shape does not allow. `json` has already
    /// decoded as a `BackupEnvelope`, so container types match the shape.
    func check(_ json: Any, path: String) throws {
        func child(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }
        switch self {
        case .value:
            return
        case let .object(keys):
            guard let object = json as? [String: Any] else { return }
            for key in object.keys.sorted() {
                guard let shape = keys[key] else {
                    throw BackupError.invalid(path: child(key), reason: "unknown key")
                }
                try shape.check(object[key]!, path: child(key))
            }
        case let .map(shape):
            guard let object = json as? [String: Any] else { return }
            for key in object.keys.sorted() { try shape.check(object[key]!, path: child(key)) }
        case let .list(shape):
            guard let list = json as? [Any] else { return }
            for (index, element) in list.enumerated() { try shape.check(element, path: "\(path)[\(index)]") }
        }
    }
}
