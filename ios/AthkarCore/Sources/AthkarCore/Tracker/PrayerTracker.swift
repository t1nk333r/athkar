import Foundation
import GRDB

/// The five obligatory prayers the tracker records (spec/tracker/tracker.md). Sunrise is not one of them.
public enum ObligatoryPrayer: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case fajr, dhuhr, asr, maghrib, isha

    public var time: PrayerTime {
        switch self {
        case .fajr: .fajr
        case .dhuhr: .dhuhr
        case .asr: .asr
        case .maghrib: .maghrib
        case .isha: .isha
        }
    }
}

/// The tracker's neutral states. `unrecorded` is the default and never means missed: no missed or failed value exists.
public enum PrayerRecordState: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case unrecorded
    case prayed
    case notApplicable = "not_applicable"
}

/// The timing the user chose for a prayed record. The app never derives it from the clock.
public enum PrayerTiming: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case onTime = "on_time"
    case late
    case madeUp = "made_up"
}

/// Which noon prayer a Friday's Dhuhr slot records.
public enum NoonPrayer: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case dhuhr, jumuah
}

/// One prayer on one calculation date: a record's identity.
public struct PrayerOccurrence: Hashable, Sendable {
    public var date: String
    public var prayer: ObligatoryPrayer

    public init(date: String, prayer: ObligatoryPrayer) {
        self.date = date
        self.prayer = prayer
    }

    /// The Dhuhr slot of a Friday, which may record Jumu'ah instead.
    public var isFridayDhuhr: Bool { prayer == .dhuhr && LocalDate.isFriday(date) }
}

/// What the user chose for an occurrence; the part of a record commands change.
public struct PrayerEntry: Equatable, Sendable {
    public var state: PrayerRecordState
    public var timing: PrayerTiming?
    public var noon: NoonPrayer?
    /// When the current state was set; `nil` exactly when the state is `unrecorded`.
    public var loggedAt: Date?

    public init(state: PrayerRecordState, timing: PrayerTiming? = nil, noon: NoonPrayer? = nil, loggedAt: Date? = nil) {
        self.state = state
        self.timing = timing
        self.noon = noon
        self.loggedAt = loggedAt
    }

    public static let unrecorded = PrayerEntry(state: .unrecorded)

    /// Whether the entry keeps the rules of spec/tracker/tracker.md for `occurrence`.
    public func isValid(for occurrence: PrayerOccurrence) -> Bool {
        (timing == nil || state == .prayed)
            && (noon == nil || (state == .prayed && occurrence.isFridayDhuhr))
            && ((loggedAt == nil) == (state == .unrecorded))
    }
}

/// What a command is made with: the clock, the device's zone, and the occurrence's calculated time and profile. The
/// metadata is captured only when the command creates the record.
public struct PrayerCommandContext: Sendable {
    public var now: Date
    public var zone: TimeZone
    public var scheduledAt: Date?
    public var profileVersion: String

    public init(now: Date, zone: TimeZone, scheduledAt: Date?, profileVersion: String) {
        self.now = now
        self.zone = zone
        self.scheduledAt = scheduledAt
        self.profileVersion = profileVersion
    }

    /// The civil date of `now` in `zone`.
    public var today: String { SessionCalendar.localDate(of: now, in: zone) }
}

/// The tracker's commands (spec/tracker/tracker.md, "Commands").
public enum PrayerCommand: Equatable, Sendable {
    /// Record as prayed; `noon` chooses Jumu'ah or Dhuhr on a Friday's Dhuhr, `nil` keeps what is stored.
    case record(noon: NoonPrayer? = nil)
    case unrecord
    case setTiming(PrayerTiming?)
    case markNotApplicable
    case unmarkNotApplicable
    /// The undo: back to the entry the occurrence had before a command.
    case restore(PrayerEntry)
}

/// Why a command was refused. Nothing was written.
public enum PrayerCommandRefusal: String, Error, Sendable {
    case invalidDate = "invalid-date"
    case futureDate = "future-date"
    case notPrayed = "not-prayed"
    case notFridayDhuhr = "not-friday-dhuhr"
    case invalidEntry = "invalid-entry"
}

/// A command's result when it was not refused.
public enum PrayerCommandOutcome: Equatable, Sendable {
    /// Nothing to write.
    case unchanged
    /// The record to store, new or changed.
    case changed(PrayerRecord)
}

/// One prayer's record on one calculation date (spec/schema.md, `prayer_records`): the user's entry and the metadata
/// captured when the record was first created, never rewritten.
public struct PrayerRecord: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "prayer_records"

    public var calculationDate: String
    public var prayerKey: ObligatoryPrayer
    /// The IANA zone of the device when the record was created.
    public var zoneId: String
    /// The occurrence's calculated time when the record was created; `nil` when it could not be calculated.
    public var scheduledAt: Date?
    /// `CalculationSettings.profileVersion` when the record was created.
    public var profileVersion: String
    public var state: PrayerRecordState
    public var timing: PrayerTiming?
    public var noonPrayer: NoonPrayer?
    public var loggedAt: Date?
    public var updatedAt: Date

    public init(calculationDate: String, prayerKey: ObligatoryPrayer, zoneId: String, scheduledAt: Date?,
                profileVersion: String, state: PrayerRecordState, timing: PrayerTiming?, noonPrayer: NoonPrayer?,
                loggedAt: Date?, updatedAt: Date) {
        self.calculationDate = calculationDate
        self.prayerKey = prayerKey
        self.zoneId = zoneId
        self.scheduledAt = scheduledAt
        self.profileVersion = profileVersion
        self.state = state
        self.timing = timing
        self.noonPrayer = noonPrayer
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
    }

    public var occurrence: PrayerOccurrence { PrayerOccurrence(date: calculationDate, prayer: prayerKey) }

    public var entry: PrayerEntry {
        get { PrayerEntry(state: state, timing: timing, noon: noonPrayer, loggedAt: loggedAt) }
        set {
            state = newValue.state
            timing = newValue.timing
            noonPrayer = newValue.noon
            loggedAt = newValue.loggedAt
        }
    }
}

/// The tracker's transitions, apart from storage (spec/tracker/tracker.md).
public enum PrayerTracker {
    /// The result of `command` on `occurrence`, whose stored record is `existing`. A new record takes its metadata
    /// from `context`; an existing one keeps its own.
    public static func apply(_ command: PrayerCommand, to occurrence: PrayerOccurrence, existing: PrayerRecord?,
                             context: PrayerCommandContext) throws(PrayerCommandRefusal) -> PrayerCommandOutcome {
        try check(occurrence.date, context: context)
        let current = existing?.entry ?? .unrecorded
        let now = context.now
        let next: PrayerEntry
        switch command {
        case let .record(noon):
            if noon != nil, !occurrence.isFridayDhuhr { throw .notFridayDhuhr }
            if current.state == .prayed {
                next = PrayerEntry(state: .prayed, timing: current.timing, noon: noon ?? current.noon,
                                   loggedAt: current.loggedAt)
            } else {
                next = PrayerEntry(state: .prayed, noon: noon, loggedAt: now)
            }
        case .unrecord:
            next = .unrecorded
        case let .setTiming(timing):
            guard current.state == .prayed else { throw .notPrayed }
            next = PrayerEntry(state: .prayed, timing: timing, noon: current.noon, loggedAt: current.loggedAt)
        case .markNotApplicable:
            next = current.state == .notApplicable ? current : PrayerEntry(state: .notApplicable, loggedAt: now)
        case .unmarkNotApplicable:
            next = current.state == .notApplicable ? .unrecorded : current
        case let .restore(entry):
            guard entry.isValid(for: occurrence) else { throw .invalidEntry }
            next = entry
        }
        if next == current { return .unchanged }
        var record = existing ?? PrayerRecord(
            calculationDate: occurrence.date, prayerKey: occurrence.prayer, zoneId: context.zone.identifier,
            scheduledAt: context.scheduledAt, profileVersion: context.profileVersion, state: .unrecorded, timing: nil,
            noonPrayer: nil, loggedAt: nil, updatedAt: now)
        record.entry = next
        record.updatedAt = now
        return .changed(record)
    }

    /// `clearDay`: every record of `date` back to `unrecorded`. Returns the records that changed.
    public static func clearDay(_ date: String, records: [PrayerRecord],
                                context: PrayerCommandContext) throws(PrayerCommandRefusal) -> [PrayerRecord] {
        try check(date, context: context)
        var changed: [PrayerRecord] = []
        for record in records where record.calculationDate == date {
            if case let .changed(cleared) = try apply(.unrecord, to: record.occurrence, existing: record,
                                                       context: context) {
                changed.append(cleared)
            }
        }
        return changed
    }

    private static func check(_ date: String, context: PrayerCommandContext) throws(PrayerCommandRefusal) {
        guard LocalDate.epochDay(date) != nil else { throw .invalidDate }
        guard date <= context.today else { throw .futureDate }
    }
}

extension CalculationSettings {
    /// The profile a record's calculated time came from (spec/tracker/tracker.md, "Metadata"):
    /// `method/asr school/high-latitude rule/fajr,sunrise,dhuhr,asr,maghrib,isha`. The Hijri offset is not part of it.
    public var profileVersion: String {
        let minutes = [adjustments.fajr, adjustments.sunrise, adjustments.dhuhr, adjustments.asr, adjustments.maghrib,
                       adjustments.isha].map(String.init).joined(separator: ",")
        return "\(method.rawValue)/\(asrSchool.rawValue)/\(highLatitudeRule.rawValue)/\(minutes)"
    }
}

extension PrayerSchedule {
    /// The occurrence time a new record captures: `nil` when it could not be calculated, or for a clamped Asr, which
    /// is undetermined (``NextPrayer``).
    public func scheduledTime(of prayer: ObligatoryPrayer) -> Date? {
        if prayer == .asr, asrClamped { return nil }
        return self[prayer.time]
    }
}
