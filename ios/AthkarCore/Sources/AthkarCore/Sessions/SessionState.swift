import Foundation

/// The PWA's `athkar-progress-v2` state: today's counters, chosen targets, completion bookkeeping and the
/// last seven days of history.
///
/// Dates are local `YYYY-MM-DD` strings. Timestamps (`completedAt`, `morningAt`, `eveningAt`) keep the
/// PWA's stored strings verbatim (normally `toISOString()` output; ``SessionCalendar/isoString(_:)``
/// writes new ones), because the PWA copies any stored string through normalisation unchanged.
public struct SessionState: Codable, Sendable, Equatable {
    public var date: String
    /// Raw tap counters keyed by item id, in their stored shape. Read them through ``count(for:in:)``.
    public var progress: SessionPeriods<ItemValues>
    /// Raw chosen targets keyed by item id, in their stored shape. Read them through ``target(for:in:)``.
    public var targets: SessionPeriods<ItemValues>
    public var completedAt: SessionPeriods<String?>
    public var manualCompletion: SessionPeriods<Bool>
    /// Newest first, at most ``historyLimit`` entries after a rollover.
    public var history: [HistoryEntry]

    /// `localStorage` key of the current format.
    public static let storageKey = "athkar-progress-v2"
    /// `localStorage` key of the previous format, read only when ``storageKey`` is empty.
    public static let legacyStorageKey = "athkar-progress-v1"
    /// Days kept in ``history``.
    public static let historyLimit = 7
    /// `longDhikrThreshold`: an item whose target is at least this is "long".
    public static let longDhikrThreshold = 10

    public init(
        date: String,
        progress: SessionPeriods<ItemValues>,
        targets: SessionPeriods<ItemValues>,
        completedAt: SessionPeriods<String?>,
        manualCompletion: SessionPeriods<Bool>,
        history: [HistoryEntry]
    ) {
        self.date = date
        self.progress = progress
        self.targets = targets
        self.completedAt = completedAt
        self.manualCompletion = manualCompletion
        self.history = history
    }

    /// `emptyState(date)`.
    public static func empty(date: String) -> SessionState {
        SessionState(
            date: date,
            progress: SessionPeriods(morning: [:], evening: [:]),
            targets: SessionPeriods(morning: [:], evening: [:]),
            completedAt: SessionPeriods(morning: nil, evening: nil),
            manualCompletion: SessionPeriods(morning: false, evening: false),
            history: []
        )
    }

    /// One day of history: whether each period was complete (by counters or manually) and when.
    public struct HistoryEntry: Codable, Sendable, Equatable {
        public var date: String
        public var morning: Bool
        public var evening: Bool
        public var morningAt: String?
        public var eveningAt: String?

        public init(date: String, morning: Bool, evening: Bool, morningAt: String? = nil, eveningAt: String? = nil) {
            self.date = date
            self.morning = morning
            self.evening = evening
            self.morningAt = morningAt
            self.eveningAt = eveningAt
        }

        public func isComplete(_ period: Period) -> Bool {
            switch period {
            case .morning: morning
            case .evening: evening
            }
        }

        public func completedAt(_ period: Period) -> String? {
            switch period {
            case .morning: morningAt
            case .evening: eveningAt
            }
        }

        private enum CodingKeys: String, CodingKey {
            case date, morning, evening, morningAt, eveningAt
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(String.self, forKey: .date)
            morning = try container.decode(Bool.self, forKey: .morning)
            evening = try container.decode(Bool.self, forKey: .evening)
            morningAt = try container.decodeIfPresent(String.self, forKey: .morningAt)
            eveningAt = try container.decodeIfPresent(String.self, forKey: .eveningAt)
        }

        /// Absent timestamps are written as `null`, as the PWA stores them.
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

// MARK: - Loading stored state

extension SessionState {
    /// `normalizeState(parsed)`: sanitises any parsed JSON into a well-formed state.
    ///
    /// - A `date` that is not `YYYY-MM-DD` becomes `today`.
    /// - `history` keeps the first seven objects with a string `date`; legacy `morningSkipped`/`eveningSkipped`
    ///   count as complete; non-string timestamps become `nil`.
    /// - `progress`/`targets` containers that are not objects or arrays become `{}`; containers and their
    ///   values are kept verbatim.
    /// - Legacy `skipped` flags count as `manualCompletion`.
    public static func normalized(_ parsed: StoredValue, today: String) -> SessionState {
        func truthy(_ value: StoredValue?) -> Bool { value?.isTruthy ?? false }
        func container(_ section: String, _ period: Period) -> ItemValues {
            parsed.property(section)?.property(period.rawValue).flatMap(ItemValues.init) ?? [:]
        }
        func pair<Value>(_ read: (Period) -> Value) -> SessionPeriods<Value> {
            SessionPeriods(morning: read(.morning), evening: read(.evening))
        }

        var history: [HistoryEntry] = []
        if case .array(let stored)? = parsed.property("history") {
            for entry in stored where history.count < historyLimit {
                guard let entryDate = entry.property("date")?.stringValue else { continue }
                history.append(HistoryEntry(
                    date: entryDate,
                    morning: truthy(entry.property("morning")) || truthy(entry.property("morningSkipped")),
                    evening: truthy(entry.property("evening")) || truthy(entry.property("eveningSkipped")),
                    morningAt: entry.property("morningAt")?.stringValue,
                    eveningAt: entry.property("eveningAt")?.stringValue
                ))
            }
        }

        let storedDate = parsed.property("date")?.stringValue
        return SessionState(
            date: storedDate.flatMap { isLocalDateKey($0) ? $0 : nil } ?? today,
            progress: pair { container("progress", $0) },
            targets: pair { container("targets", $0) },
            completedAt: pair { parsed.property("completedAt")?.property($0.rawValue)?.stringValue },
            manualCompletion: pair {
                truthy(parsed.property("manualCompletion")?.property($0.rawValue))
                    || truthy(parsed.property("skipped")?.property($0.rawValue))
            },
            history: history
        )
    }

    /// `loadState()`: reads `athkar-progress-v2` (or, when that is missing or empty, `athkar-progress-v1`) from
    /// raw `localStorage` strings, normalises it, and rolls it to the local date of `now` in `timeZone`.
    /// Unreadable or non-object JSON yields an empty state for today.
    ///
    /// JSON is read by ``StoredValue/init(parsingJSON:)``, which accepts and rejects what `JSON.parse` does
    /// (see there for the lone-surrogate and nesting-depth exceptions).
    public static func load(
        storage: [String: String],
        now: Date,
        timeZone: TimeZone,
        collections: SessionCollections
    ) -> SessionState {
        let today = SessionCalendar.localDate(of: now, in: timeZone)
        let current = storage[storageKey]
        // `JSON.parse(current || legacy)`: an empty string is falsy; `JSON.parse(null)` is `null`.
        guard let raw = current.flatMap({ $0.isEmpty ? nil : $0 }) ?? storage[legacyStorageKey],
              let parsed = try? StoredValue(parsingJSON: raw)
        else { return .empty(date: today) }
        switch parsed {
        case .object, .array:
            let normalized = normalized(parsed, today: today)
            return normalized.date == today ? normalized : normalized.rolled(to: today, in: collections)
        default:
            return .empty(date: today)
        }
    }

    /// `/^\d{4}-\d{2}-\d{2}$/` (ASCII digits, no trailing newline).
    private static func isLocalDateKey(_ text: String) -> Bool {
        let bytes = text.utf8
        guard bytes.count == 10 else { return false }
        for (offset, byte) in bytes.enumerated() {
            let valid = offset == 4 || offset == 7
                ? byte == UInt8(ascii: "-")
                : (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            if !valid { return false }
        }
        return true
    }
}
