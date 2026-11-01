import Foundation

/// A validated transfer code (spec/transfer/transfer-v1.md §1), or an athkar `.athkarbackup` read as one (`source`
/// `.backup`: the envelope only, no suwar, tasbih or reset epochs).
public struct TransferContainer: Equatable, Sendable {
    public enum Source: String, Sendable {
        case code
        case backup
    }

    public var source: Source
    /// The envelope, without `reminders.location` (a backup file may carry one; it is never imported).
    public var envelope: BackupEnvelope
    /// The stores the envelope cannot carry; `nil` for a backup file.
    public var athkar: Athkar?
    /// The container exactly as the PWA's decoder returns it (a backup's envelope as read), for the fixtures.
    let json: TransferJSON

    /// The code's day: its sender's local date when it was made.
    public var date: String { envelope.adhkar?.today.date ?? "" }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source && lhs.envelope == rhs.envelope && lhs.athkar == rhs.athkar && lhs.json == rhs.json
    }

    /// `athkar`: the sender's stores beyond the envelope, as tuples in the code's order.
    public struct Athkar: Equatable, Sendable {
        public var adhkar: Adhkar
        public var suwar: Suwar
        public var tasbih: Tasbih
    }

    /// A store's reset epochs: `"date"` (every unit of that day) or `"date|unit"` → the instant of the reset.
    public typealias Resets = [Reset]

    public struct Reset: Equatable, Sendable {
        public var date: String
        /// `nil` for a day epoch.
        public var unit: String?
        public var at: Date
    }

    public struct Adhkar: Equatable, Sendable {
        public var resets: Resets
        /// The past days of the 31-day window, newest first.
        public var history: [BackupEnvelope.Adhkar.HistoryEntry]
    }

    public struct Suwar: Equatable, Sendable {
        public var date: String
        public var selected: String
        /// Sura → its read pages (each `true`).
        public var read: [(sura: String, pages: [String])]
        public var completedAt: [(sura: String, at: Date?)]
        /// Past day → sura → completion instant.
        public var history: [(date: String, suras: [(sura: String, at: Date)])]
        public var resets: Resets

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.date == rhs.date && lhs.selected == rhs.selected && lhs.resets == rhs.resets
                && lhs.read.map(\.sura) == rhs.read.map(\.sura) && lhs.read.map(\.pages) == rhs.read.map(\.pages)
                && lhs.completedAt.map(\.sura) == rhs.completedAt.map(\.sura)
                && lhs.completedAt.map(\.at) == rhs.completedAt.map(\.at)
                && lhs.history.map(\.date) == rhs.history.map(\.date)
                && zip(lhs.history, rhs.history).allSatisfy {
                    $0.suras.map(\.sura) == $1.suras.map(\.sura) && $0.suras.map(\.at) == $1.suras.map(\.at)
                }
        }
    }

    public struct Tasbih: Equatable, Sendable {
        public var date: String
        public var selected: String
        public var target: Int?
        public var counts: [(key: String, count: Int)]
        public var firstUse: [String]
        public var custom: [String]
        public var history: [(date: String, counts: [(key: String, count: Int)])]
        public var resets: Resets

        public static func == (lhs: Self, rhs: Self) -> Bool {
            func same(_ a: [(key: String, count: Int)], _ b: [(key: String, count: Int)]) -> Bool {
                a.count == b.count && zip(a, b).allSatisfy { TasbihPhrase.same($0.key, $1.key) && $0.count == $1.count }
            }
            return lhs.date == rhs.date && TasbihPhrase.same(lhs.selected, rhs.selected) && lhs.target == rhs.target
                && same(lhs.counts, rhs.counts) && lhs.firstUse.map(TasbihPhrase.units) == rhs.firstUse.map(TasbihPhrase.units)
                && lhs.custom.map(TasbihPhrase.units) == rhs.custom.map(TasbihPhrase.units)
                && lhs.history.map(\.date) == rhs.history.map(\.date)
                && zip(lhs.history, rhs.history).allSatisfy { same($0.counts, $1.counts) }
                && lhs.resets == rhs.resets
        }
    }
}

/// `validateTransferContainer` and `validateTransferEnvelope`: exact key sets at every depth and the transfer's bounds,
/// checked in the PWA's order so that a refused code reports the same first path.
enum TransferValidator {
    struct Rejection: Error {
        var error: TransferError
    }

    static let forbiddenKeys: Set<String> = ["__proto__", "constructor", "prototype"]
    static let calculationMethods: Set<String> = ["mwl", "umm-al-qura", "egyptian", "karachi", "north-america"]
    static let historyWindowDays = 31

    static func validateCode(_ value: TransferJSON) -> Result<TransferContainer, TransferError> {
        do {
            return .success(try container(value))
        } catch {
            return .failure(error.error)
        }
    }

    static func validateBackup(_ value: TransferJSON) -> Result<TransferContainer, TransferError> {
        do {
            let envelope = try envelope(value, allowLocation: true)
            let json = TransferJSON.object([
                ("transfer", .number(1)), ("app", .string(TransferCodec.app)), ("envelope", value), ("athkar", .null),
            ])
            return .success(TransferContainer(source: .backup, envelope: envelope, athkar: nil, json: json))
        } catch {
            return .failure(error.error)
        }
    }

    // MARK: Checks

    private static func reject(_ path: String, _ kind: TransferError.Kind = .corrupt, _ reason: String = "invalid")
        -> Rejection {
        Rejection(error: TransferError(kind, reason: reason, path: path))
    }

    private static func check(_ valid: Bool, _ path: String) throws(Rejection) {
        if !valid { throw reject(path) }
    }

    /// `transferFields`: an object with exactly `keys`.
    @discardableResult
    private static func fields(_ value: TransferJSON?, _ path: String, _ keys: [String]) throws(Rejection)
        -> TransferJSON {
        guard let value, let members = value.members else { throw reject(path) }
        try check(members.count == keys.count && keys.allSatisfy { value[$0] != nil }, path)
        return value
    }

    /// `transferEntries`: a map with at most `maxKeys` entries, keys passing `keyIsValid` and never forbidden.
    private static func entries(
        _ value: TransferJSON?, _ path: String, _ maxKeys: Int, _ keyIsValid: (String) -> Bool,
        _ checkValue: (TransferJSON, String) throws(Rejection) -> Void
    ) throws(Rejection) -> [(key: String, value: TransferJSON)] {
        guard let members = value?.members else { throw reject(path) }
        try check(members.count <= maxKeys, path)
        for (key, item) in members {
            try check(!forbiddenKeys.contains(key) && keyIsValid(key), "\(path)/\(key)")
            try checkValue(item, "\(path)/\(key)")
        }
        return members
    }

    private static func instant(_ value: TransferJSON?, _ path: String, nullable: Bool = false) throws(Rejection)
        -> Date? {
        if nullable, value == .null { return nil }
        guard let text = value?.string, let date = backupInstant(text) else { throw reject(path) }
        return date
    }

    /// `backupInstant`: the envelope's instant pattern and a real UTC time.
    static func backupInstant(_ text: String) -> Date? {
        ISOInstant.parse(text)
    }

    static func isRealDateKey(_ value: TransferJSON?) -> Bool {
        guard let text = value?.string else { return false }
        return LocalDate.isValid(text)
    }

    static func cutoff(_ date: String) -> String {
        SessionState.historyCutoff(endingOn: date)
    }

    private static func hasControl(_ text: String) -> Bool {
        text.utf16.contains { $0 < 0x20 || $0 == 0x7F }
    }

    /// `transferPhraseIsValid`.
    static func phraseIsValid(_ value: TransferJSON) -> Bool {
        guard let text = value.string else { return false }
        return !text.isEmpty && TasbihPhrase.same(TasbihPhrase.cleanPhrase(text), text) && !hasControl(text)
    }

    /// `transferTasbihKeyIsValid`.
    static func tasbihKeyIsValid(_ key: String) -> Bool {
        if forbiddenKeys.contains(key) || hasControl(key) { return false }
        if key.hasPrefix(TasbihPhrase.customPrefix) { return TasbihPhrase.canonicalKey(key, custom: []) != nil }
        let bytes = Array(key.utf8)
        return (1...32).contains(bytes.count) && (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(bytes[0])
            && bytes.allSatisfy { (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0) || $0 == UInt8(ascii: "-") }
    }

    static func slugIsValid(_ key: String) -> Bool {
        let bytes = Array(key.utf8)
        let lower = { (c: UInt8) in (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(c) }
        let digit = { (c: UInt8) in (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(c) }
        return (1...48).contains(bytes.count) && (lower(bytes[0]) || digit(bytes[0]))
            && bytes.allSatisfy { lower($0) || digit($0) || $0 == UInt8(ascii: "-") }
    }

    static func timeZoneIsValid(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        return (1...64).contains(bytes.count) && bytes.allSatisfy {
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains($0) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) || "_+-/".utf8.contains($0)
        }
    }

    /// `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`
    static func itemIDIsValid(_ key: String) -> Bool {
        let bytes = Array(key.utf8)
        let alphanumeric = { (c: UInt8) in
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(c) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(c)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(c)
        }
        return (1...64).contains(bytes.count) && alphanumeric(bytes[0])
            && bytes.allSatisfy { alphanumeric($0) || $0 == UInt8(ascii: "_") || $0 == UInt8(ascii: "-") }
    }

    /// `transferHistoryList`.
    private static func historyList(_ value: TransferJSON?, _ path: String, date: String, max: Int, cutoff: String)
        throws(Rejection) -> [BackupEnvelope.Adhkar.HistoryEntry] {
        guard let list = value?.array, list.count <= max else { throw reject(path) }
        var result: [BackupEnvelope.Adhkar.HistoryEntry] = []
        var previous: String?
        for (index, entry) in list.enumerated() {
            let entryPath = "\(path)/\(index)"
            try fields(entry, entryPath, ["date", "morning", "evening", "morningAt", "eveningAt"])
            let day = entry["date"]?.string ?? ""
            try check(isRealDateKey(entry["date"]) && day < date && day >= cutoff && (previous.map { day < $0 } ?? true),
                      "\(entryPath)/date")
            guard let morning = entry["morning"]?.bool, let evening = entry["evening"]?.bool else {
                throw reject(entryPath)
            }
            let morningAt = try instant(entry["morningAt"], "\(entryPath)/morningAt", nullable: true)
            let eveningAt = try instant(entry["eveningAt"], "\(entryPath)/eveningAt", nullable: true)
            result.append(.init(date: day, morning: morning, evening: evening, morningAt: morningAt, eveningAt: eveningAt))
            previous = day
        }
        return result
    }

    /// `transferResets`.
    private static func resets(_ value: TransferJSON?, _ path: String, date: String, unitIsValid: (String) -> Bool)
        throws(Rejection) -> TransferContainer.Resets {
        let cutoff = cutoff(date)
        var result: TransferContainer.Resets = []
        for (key, at) in try entries(value, path, 512, { key in
            let (day, unit) = splitReset(key)
            return LocalDate.isValid(day) && day >= cutoff && day <= date && (unit.map(unitIsValid) ?? true)
        }, { at, itemPath throws(Rejection) in _ = try instant(at, itemPath) }) {
            let (day, unit) = splitReset(key)
            result.append(.init(date: day, unit: unit, at: backupInstant(at.string ?? "")!))
        }
        return result
    }

    static func splitReset(_ key: String) -> (date: String, unit: String?) {
        guard let separator = key.firstIndex(of: "|") else { return (key, nil) }
        return (String(key[..<separator]), String(key[key.index(after: separator)...]))
    }

    // MARK: Envelope

    /// `validateTransferEnvelope`: envelope v1 as the athkar PWA writes it, with the transfer's tighter bounds.
    static func envelope(_ value: TransferJSON, allowLocation: Bool) throws(Rejection) -> BackupEnvelope {
        guard value.members != nil else { throw reject("envelope") }
        let meta = value["meta"]
        if let meta, meta.members != nil {
            if let format = meta["format"]?.integer, format > 1 { throw reject("envelope/meta/format", .newer, "format") }
            if meta["app"]?.string == "ruqyah-pwa" { throw reject("envelope/meta/app", .wrongApp, "app") }
        }
        try fields(value, "envelope", ["meta", "adhkar", "reminders", "preferences"])
        try fields(meta, "envelope/meta", ["format", "app", "exportedAt", "timeZone"])
        try check(meta?["format"] == .number(1) && meta?["app"]?.string == TransferCodec.app, "envelope/meta")
        let exportedAt = try instant(meta?["exportedAt"], "envelope/meta/exportedAt")!
        guard let timeZone = meta?["timeZone"]?.string, timeZoneIsValid(timeZone) else {
            throw reject("envelope/meta/timeZone")
        }
        let adhkar = try fields(value["adhkar"], "envelope/adhkar", ["today", "history"])
        let today = try fields(adhkar["today"], "envelope/adhkar/today",
                               ["date", "progress", "targets", "completedAt", "manualCompletion"])
        try check(isRealDateKey(today["date"]), "envelope/adhkar/today/date")
        let date = today["date"]!.string!
        var counts: [String: [Period: [String: Double]]] = [:]
        var completedAt: [Period: Date?] = [:]
        var manual: [Period: Bool] = [:]
        for field in ["progress", "targets", "completedAt", "manualCompletion"] {
            let periods = try fields(today[field], "envelope/adhkar/today/\(field)", ["morning", "evening"])
            for period in [Period.morning, .evening] {
                let path = "envelope/adhkar/today/\(field)/\(period.rawValue)"
                let member = periods[period.rawValue]
                switch field {
                case "completedAt": completedAt[period] = .some(try instant(member, path, nullable: true))
                case "manualCompletion":
                    guard let flag = member?.bool else { throw reject(path) }
                    manual[period] = flag
                default:
                    var values: [String: Double] = [:]
                    for (key, count) in try entries(member, path, 128, itemIDIsValid, { count, countPath throws(Rejection) in
                        guard let number = count.number, number.isFinite, number >= 0, number <= 9_007_199_254_740_991
                        else { throw reject(countPath) }
                    }) {
                        values[key] = count.number!
                    }
                    counts[field, default: [:]][period] = values
                }
            }
        }
        let history = try historyList(adhkar["history"], "envelope/adhkar/history", date: date, max: 7, cutoff: "")

        let reminders = value["reminders"]
        let withLocation = allowLocation && reminders?.members != nil && reminders?["location"] != nil
        try fields(reminders, "envelope/reminders",
                   ["morning", "evening", "calculationMethod", "asrSchool", "lastShown"] + (withLocation ? ["location"] : []))
        var toggles: [Period: Bool] = [:]
        for period in [Period.morning, .evening] {
            let toggle = try fields(reminders?[period.rawValue], "envelope/reminders/\(period.rawValue)", ["enabled"])
            guard let enabled = toggle["enabled"]?.bool else {
                throw reject("envelope/reminders/\(period.rawValue)/enabled")
            }
            toggles[period] = enabled
        }
        guard let methodName = reminders?["calculationMethod"]?.string, calculationMethods.contains(methodName),
              let method = CalculationMethod(rawValue: methodName)
        else { throw reject("envelope/reminders/calculationMethod") }
        guard let asrName = reminders?["asrSchool"]?.string, let asr = AsrSchool(rawValue: asrName) else {
            throw reject("envelope/reminders/asrSchool")
        }
        let lastShown = try fields(reminders?["lastShown"], "envelope/reminders/lastShown", ["morning", "evening"])
        var shown: [Period: String?] = [:]
        for period in [Period.morning, .evening] {
            let member = lastShown[period.rawValue]
            try check(member == .null || isRealDateKey(member), "envelope/reminders/lastShown/\(period.rawValue)")
            shown[period] = .some(member?.string)
        }
        if withLocation {
            let location = try fields(reminders?["location"], "envelope/reminders/location",
                                      ["latitude", "longitude", "updatedAt"])
            guard let latitude = location["latitude"]?.number, latitude >= -90, latitude <= 90,
                  let longitude = location["longitude"]?.number, longitude >= -180, longitude <= 180
            else { throw reject("envelope/reminders/location") }
            _ = try instant(location["updatedAt"], "envelope/reminders/location/updatedAt", nullable: true)
        }
        let preferences = try fields(value["preferences"], "envelope/preferences",
                                     ["theme", "textSize", "lineSpacing", "haptics", "longOrder", "longOrderPromptAnswered"])
        guard let theme = preferences["theme"]?.string.flatMap(Theme.init(rawValue:)),
              let textSize = preferences["textSize"]?.string.flatMap(TextSize.init(rawValue:)),
              let lineSpacing = preferences["lineSpacing"]?.string.flatMap(LineSpacing.init(rawValue:)),
              let haptics = preferences["haptics"]?.bool,
              let longOrder = preferences["longOrder"]?.string.flatMap(LongOrder.init(rawValue:)),
              let answered = preferences["longOrderPromptAnswered"]?.bool
        else { throw reject("envelope/preferences") }

        func perPeriod<Value>(_ values: [Period: Value]) -> BackupEnvelope.PerPeriod<Value> {
            .init(morning: values[.morning]!, evening: values[.evening]!)
        }
        var envelope = BackupEnvelope(meta: .init(app: .athkarPWA, exportedAt: exportedAt, timeZone: timeZone))
        envelope.adhkar = .init(
            today: .init(date: date, progress: perPeriod(counts["progress"]!), targets: perPeriod(counts["targets"]!),
                         completedAt: perPeriod(completedAt), manualCompletion: perPeriod(manual)),
            history: history
        )
        envelope.reminders = .init(morning: .init(enabled: toggles[.morning]!), evening: .init(enabled: toggles[.evening]!),
                                   calculationMethod: method, asrSchool: asr, lastShown: perPeriod(shown), location: nil)
        envelope.preferences = .init(theme: theme, textSize: textSize, lineSpacing: lineSpacing, haptics: haptics,
                                     longOrder: longOrder, longOrderPromptAnswered: answered)
        return envelope
    }

    // MARK: Container

    /// `validateTransferContainer`.
    static func container(_ value: TransferJSON) throws(Rejection) -> TransferContainer {
        guard value.members != nil else { throw reject("transfer") }
        if let version = value["transfer"]?.integer, version > TransferCodec.version {
            throw reject("transfer/transfer", .newer, "version")
        }
        if value["app"]?.string == "ruqyah-pwa" { throw reject("transfer/app", .wrongApp, "app") }
        try fields(value, "transfer", ["transfer", "app", "envelope", "athkar"])
        try check(value["transfer"] == .number(1) && value["app"]?.string == TransferCodec.app, "transfer")
        let envelope = try envelope(value["envelope"]!, allowLocation: false)
        let date = envelope.adhkar!.today.date
        let windowStart = cutoff(date)
        let athkar = try fields(value["athkar"], "athkar", ["adhkar", "suwar", "tasbih"])

        let adhkarPart = try fields(athkar["adhkar"], "athkar/adhkar", ["resets", "history"])
        let adhkarHistory = try historyList(adhkarPart["history"], "athkar/adhkar/history", date: date,
                                            max: historyWindowDays, cutoff: windowStart)
        let adhkarResets = try resets(adhkarPart["resets"], "athkar/adhkar/resets", date: date) {
            $0 == "morning" || $0 == "evening"
        }

        let suwar = try fields(athkar["suwar"], "athkar/suwar", ["date", "selected", "read", "completedAt", "history", "resets"])
        try check(suwar["date"]?.string == date, "athkar/suwar/date")
        guard let selectedSura = suwar["selected"]?.string, slugIsValid(selectedSura) else {
            throw reject("athkar/suwar/selected")
        }
        let read = try entries(suwar["read"], "athkar/suwar/read", 16, slugIsValid) { pages, path throws(Rejection) in
            _ = try entries(pages, path, 64, slugIsValid) { mark, pagePath throws(Rejection) in
                try check(mark == .bool(true), pagePath)
            }
        }
        let suwarCompleted = try entries(suwar["completedAt"], "athkar/suwar/completedAt", 16, slugIsValid) {
            at, path throws(Rejection) in _ = try instant(at, path, nullable: true)
        }
        let inWindow = { (day: String) in LocalDate.isValid(day) && day < date && day >= windowStart }
        let suwarHistory = try entries(suwar["history"], "athkar/suwar/history", historyWindowDays, inWindow) {
            entry, path throws(Rejection) in
            _ = try entries(entry, path, 16, slugIsValid) { at, suraPath throws(Rejection) in _ = try instant(at, suraPath) }
        }
        let suwarResets = try resets(suwar["resets"], "athkar/suwar/resets", date: date, unitIsValid: slugIsValid)

        let tasbih = try fields(athkar["tasbih"], "athkar/tasbih",
                                ["date", "selected", "target", "counts", "firstUse", "custom", "history", "resets"])
        try check(tasbih["date"]?.string == date, "athkar/tasbih/date")
        guard let selectedKey = tasbih["selected"]?.string, tasbihKeyIsValid(selectedKey) else {
            throw reject("athkar/tasbih/selected")
        }
        let targetValue = tasbih["target"]
        var target: Int?
        if targetValue != .null {
            guard let value = targetValue?.integer, (1...9999).contains(value) else { throw reject("athkar/tasbih/target") }
            target = value
        }
        func counts(_ entry: TransferJSON?, _ path: String) throws(Rejection) -> [(key: String, count: Int)] {
            try entries(entry, path, 256, tasbihKeyIsValid) { count, keyPath throws(Rejection) in
                guard let value = count.integer, (1...TasbihCount.maxCount).contains(value) else { throw reject(keyPath) }
            }.map { ($0.key, $0.value.integer!) }
        }
        let tasbihCounts = try counts(tasbih["counts"], "athkar/tasbih/counts")
        guard let firstUse = tasbih["firstUse"]?.array, firstUse.count <= 256,
              firstUse.allSatisfy({ $0.string.map(tasbihKeyIsValid) ?? false })
        else { throw reject("athkar/tasbih/firstUse") }
        guard let custom = tasbih["custom"]?.array, custom.count <= TasbihPhrase.maxCustom, custom.allSatisfy(phraseIsValid)
        else { throw reject("athkar/tasbih/custom") }
        var tasbihHistory: [(date: String, counts: [(key: String, count: Int)])] = []
        for (day, entry) in try entries(tasbih["history"], "athkar/tasbih/history", historyWindowDays, inWindow, {
            entry, path throws(Rejection) in _ = try counts(entry, path)
        }) {
            tasbihHistory.append((day, try counts(entry, "athkar/tasbih/history/\(day)")))
        }
        let tasbihResets = try resets(tasbih["resets"], "athkar/tasbih/resets", date: date, unitIsValid: tasbihKeyIsValid)

        let part = TransferContainer.Athkar(
            adhkar: .init(resets: adhkarResets, history: adhkarHistory),
            suwar: .init(
                date: date, selected: selectedSura,
                read: read.map { sura, pages in (sura, pages.members!.map(\.key)) },
                completedAt: suwarCompleted.map { sura, at in (sura, at.string.flatMap(backupInstant)) },
                history: suwarHistory.map { day, entry in
                    (day, entry.members!.map { sura, at in (sura, backupInstant(at.string!)!) })
                },
                resets: suwarResets
            ),
            tasbih: .init(
                date: date, selected: selectedKey, target: target, counts: tasbihCounts,
                firstUse: firstUse.map { $0.string! }, custom: custom.map { $0.string! }, history: tasbihHistory,
                resets: tasbihResets
            )
        )
        return TransferContainer(source: .code, envelope: envelope, athkar: part, json: value)
    }
}
