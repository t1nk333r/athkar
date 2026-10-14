import Foundation

/// The PWA's `athkar-progress-v2` state: today's counters, chosen targets, completion bookkeeping and the
/// history retained over a 31-local-date window.
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
    /// Stored order, with the predecessor prepended on rollover. Normalization preserves duplicates and future
    /// dates; the SQL bridge loads all earlier completed dates without a retention limit.
    public var history: [HistoryEntry]

    /// `localStorage` key of the current format.
    public static let storageKey = "athkar-progress-v2"
    /// `localStorage` key of the previous format, read only when ``storageKey`` is empty.
    public static let legacyStorageKey = "athkar-progress-v1"
    /// Local dates in the PWA's history window, including the current date (`resetEpochDays`). Normalization
    /// also limits the stored input to this many entries; rollover filters by date without an entry cap.
    public static let historyWindowDays = 31
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
    /// - `history` keeps the first 31 entries with real dates at or after the window's cutoff, relative to the
    ///   stored date. Order, duplicates and future dates survive; legacy `morningSkipped`/`eveningSkipped` count
    ///   as complete; non-string timestamps become `nil`.
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

        let storedDate = parsed.property("date")?.stringValue
        let date = storedDate.flatMap { isLocalDateKey($0) ? $0 : nil } ?? today
        let cutoff = historyCutoff(endingOn: date)
        var history: [HistoryEntry] = []
        if case .array(let stored)? = parsed.property("history") {
            for entry in stored {
                guard history.count < historyWindowDays else { break }
                guard let entryDate = entry.property("date")?.stringValue,
                      LocalDate.isValid(entryDate), entryDate >= cutoff else { continue }
                history.append(HistoryEntry(
                    date: entryDate,
                    morning: truthy(entry.property("morning")) || truthy(entry.property("morningSkipped")),
                    evening: truthy(entry.property("evening")) || truthy(entry.property("eveningSkipped")),
                    morningAt: entry.property("morningAt")?.stringValue,
                    eveningAt: entry.property("eveningAt")?.stringValue
                ))
            }
        }

        return SessionState(
            date: date,
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

    /// `resetCutoff(date)`: subtract 30 civil days, independent of time zone or DST. As in `setUTCFullYear`,
    /// shaped but impossible state dates overflow into the next month/year, and years 0...99 stay literal.
    static func historyCutoff(endingOn date: String) -> String {
        guard isLocalDateKey(date) else { return date }
        let parts = date.split(separator: "-").map { Int64($0)! }
        let year = parts[0] + (parts[1] == 0 ? -1 : (parts[1] - 1) / 12)
        let month = (parts[1] + 11) % 12 + 1
        let day = LocalDate.daysFromCivil(year: year, month: month, day: parts[2]) - Int64(historyWindowDays - 1)
        return String(SessionCalendar.isoString(Date(timeIntervalSince1970: Double(day) * 86_400)).prefix(10))
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
