import Foundation
import GRDB

/// A reminder rule: either prayer-relative (`prayerKey` + `offsetMinutes`) or at a fixed `localTime`.
public struct ReminderRule: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "reminder_rules"

    public enum Kind: String, Codable, Sendable, DatabaseValueConvertible {
        case adhkarMorning = "adhkar_morning"
        case adhkarEvening = "adhkar_evening"
        case prayer
        case personal
    }

    public enum PrayerKey: String, Codable, Sendable, DatabaseValueConvertible {
        case fajr, dhuhr, asr, maghrib, isha
    }

    /// Bit `n` is weekday `n + 1` in `Calendar` numbering (bit 0 Sunday … bit 6 Saturday).
    public static let everyDay = 0b111_1111

    public var id: String
    public var kind: Kind
    public var prayerKey: PrayerKey?
    public var offsetMinutes: Int?
    /// `HH:MM`, for fixed-time rules only.
    public var localTime: String?
    public var weekdayMask: Int
    public var enabled: Bool
    public var updatedAt: Date

    public init(id: String, kind: Kind, prayerKey: PrayerKey?, offsetMinutes: Int?, localTime: String?,
                weekdayMask: Int = everyDay, enabled: Bool, updatedAt: Date) {
        self.id = id
        self.kind = kind
        self.prayerKey = prayerKey
        self.offsetMinutes = offsetMinutes
        self.localTime = localTime
        self.weekdayMask = weekdayMask
        self.enabled = enabled
        self.updatedAt = updatedAt
    }

    /// The adhkar rule for `period`: the PWA's fixed `fajr + 60` / `asr + 60` (NATIVE_APP_PLAN.md §6.2).
    /// Its `id` equals its kind, so there is at most one per period.
    public static func adhkar(_ period: Period, enabled: Bool, updatedAt: Date) -> ReminderRule {
        ReminderRule(id: adhkarId(period), kind: period == .morning ? .adhkarMorning : .adhkarEvening,
                     prayerKey: period == .morning ? .fajr : .asr, offsetMinutes: 60, localTime: nil,
                     enabled: enabled, updatedAt: updatedAt)
    }

    public static func adhkarId(_ period: Period) -> String {
        period == .morning ? Kind.adhkarMorning.rawValue : Kind.adhkarEvening.rawValue
    }
}

/// The last local date a rule's notification was shown (the PWA's `athkar-reminders-v2.lastShown`).
public struct ReminderState: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "reminder_state"

    public var ruleId: String
    public var lastShownLocalDate: String

    public init(ruleId: String, lastShownLocalDate: String) {
        self.ruleId = ruleId
        self.lastShownLocalDate = lastShownLocalDate
    }
}

public struct ReminderRepository: Sendable {
    let writer: any DatabaseWriter

    public func rules() throws -> [ReminderRule] {
        try writer.read { try ReminderRule.order(Column("id")).fetchAll($0) }
    }

    public func rule(id: String) throws -> ReminderRule? {
        try writer.read { try ReminderRule.fetchOne($0, key: id) }
    }

    public func save(_ rule: ReminderRule) throws {
        try writer.write { try rule.upsert($0) }
    }

    /// Deletes the rule and its shown state.
    public func deleteRule(id: String) throws {
        try writer.write { _ = try ReminderRule.deleteOne($0, key: id) }
    }

    public func lastShown(ruleId: String) throws -> String? {
        try writer.read { try ReminderState.fetchOne($0, key: ruleId)?.lastShownLocalDate }
    }

    /// Requires the rule to exist.
    public func setLastShown(_ localDate: String, ruleId: String) throws {
        try writer.write { try ReminderState(ruleId: ruleId, lastShownLocalDate: localDate).upsert($0) }
    }
}
