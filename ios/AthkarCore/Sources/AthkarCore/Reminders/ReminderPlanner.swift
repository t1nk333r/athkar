import Foundation

/// One local notification the app should have pending (NATIVE_APP_PLAN.md §7.5).
public struct PlannedNotification: Equatable, Sendable {
    public enum Target: Equatable, Hashable, Sendable {
        case adhkar(Period)
        case prayer(ReminderRule.PrayerKey)
    }

    /// Stable: `adhkar.morning.<local_date>`, `prayer.fajr.<local_date>`. Replanning replaces a request with the
    /// same ID instead of adding a second one.
    public let id: String
    public let target: Target
    /// The civil date, in the plan's zone, of the prayer the notification belongs to.
    public let localDate: String
    public let fireAt: Date
    /// Minutes from the prayer: the adhkar rules' 60, or a prayer rule's offset (negative is before).
    public let offsetMinutes: Int
    /// Planned late, inside the catch-up window, to fire at once.
    public let isCatchUp: Bool

    public init(id: String, target: Target, localDate: String, fireAt: Date, offsetMinutes: Int, isCatchUp: Bool) {
        self.id = id
        self.target = target
        self.localDate = localDate
        self.fireAt = fireAt
        self.offsetMinutes = offsetMinutes
        self.isCatchUp = isCatchUp
    }
}

/// A plan and what the budget left out of it.
public struct ReminderPlan: Equatable, Sendable {
    /// The earliest `budget` notifications, by fire time.
    public let notifications: [PlannedNotification]
    /// Wanted inside the horizon but beyond the budget: the furthest ones, left out.
    public let droppedByBudget: Int

    public init(notifications: [PlannedNotification], droppedByBudget: Int) {
        self.notifications = notifications
        self.droppedByBudget = droppedByBudget
    }
}

/// Which pending notifications the app should have, from the rules and the prayer times: a pure function of its
/// inputs so the fixtures can check it (NATIVE_APP_PLAN.md §7.5). The PWA's `nextReminderTime` and
/// `scheduleReminders` are its adhkar part:
/// - a time still ahead is planned;
/// - a rule that already fired today is not planned again today;
/// - a time up to 15 minutes past (inclusive) is planned to fire at once (catch-up);
/// - an adhkar period already complete today is not planned today;
/// - a day without times (polar day or night, no location) plans nothing;
/// - an Asr clamped to Maghrib is undetermined: neither the Asr prayer reminder nor evening adhkar (Asr + 60) that day;
/// - a prayer occurrence the tracker records as `prayed` or `not_applicable` is not planned, on any day; `unrecorded`
///   (never recorded, undone, or cleared) is planned as usual. Adhkar reminders do not depend on the tracker.
/// It plans `horizonDays` days ahead and keeps the earliest `budget` (iOS allows 64 pending requests per app).
public enum ReminderPlanner {
    public static let horizonDays = 7
    public static let budget = 64
    public static let catchUpWindow: TimeInterval = 15 * 60
    /// How far after planning a catch-up fires: soon, but after the request is added.
    public static let catchUpDelay: TimeInterval = 1

    /// - Parameters:
    ///   - rules: enabled and disabled rules; personal (fixed-time) rules are not planned in 1.0.
    ///   - schedule: the prayer times of a civil date in `zone`, or `nil` when there are none.
    ///   - completeToday: adhkar periods complete today (`periodIsComplete`).
    ///   - firedToday: IDs of rules whose notification already fired today (delivered, or `lastShown` is today).
    ///   - prayerStates: the tracker's state of each recorded occurrence; one with no entry is `unrecorded`.
    public static func plan(now: Date, zone: TimeZone, rules: [ReminderRule],
                            schedule: (String) -> PrayerSchedule?, completeToday: Set<Period>,
                            firedToday: Set<String>,
                            prayerStates: [PrayerOccurrence: PrayerRecordState] = [:]) -> [PlannedNotification] {
        makePlan(now: now, zone: zone, rules: rules, schedule: schedule, completeToday: completeToday,
                 firedToday: firedToday, prayerStates: prayerStates).notifications
    }

    /// ``plan(now:zone:rules:schedule:completeToday:firedToday:prayerStates:)``, with how many notifications the
    /// budget left out (the diagnostics screen shows it). `budget` is the iOS limit unless a test lowers it.
    public static func makePlan(now: Date, zone: TimeZone, rules: [ReminderRule],
                                schedule: (String) -> PrayerSchedule?, completeToday: Set<Period>,
                                firedToday: Set<String>,
                                prayerStates: [PrayerOccurrence: PrayerRecordState] = [:],
                                budget: Int = ReminderPlanner.budget) -> ReminderPlan {
        let active = rules.filter { $0.enabled && $0.kind != .personal }
        guard !active.isEmpty else { return ReminderPlan(notifications: [], droppedByBudget: 0) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var planned: [PlannedNotification] = []
        for day in 0..<horizonDays {
            let instant = calendar.date(byAdding: .day, value: day, to: now) ?? now
            let localDate = SessionCalendar.localDate(of: instant, in: zone)
            guard let times = schedule(localDate) else { continue }
            for rule in active {
                guard let item = notification(for: rule, times: times, localDate: localDate) else { continue }
                // Prayed or not applicable: nothing to remind of. Unrecorded is neutral and keeps its reminder.
                if case .prayer(let key) = item.target,
                   let state = prayerStates[PrayerOccurrence(date: localDate, prayer: key.obligatory)],
                   state != .unrecorded { continue }
                if day == 0 {
                    if case .adhkar(let period) = item.target, completeToday.contains(period) { continue }
                    // Once a day: shown today, it waits for tomorrow even if today's time is still ahead.
                    if firedToday.contains(rule.id) { continue }
                }
                if item.fireAt > now {
                    planned.append(item)
                } else if day == 0, now.timeIntervalSince(item.fireAt) <= catchUpWindow {
                    planned.append(PlannedNotification(id: item.id, target: item.target, localDate: localDate,
                                                       fireAt: now.addingTimeInterval(catchUpDelay),
                                                       offsetMinutes: item.offsetMinutes, isCatchUp: true))
                }
            }
        }
        // One request per ID: a second rule for the same prayer (not something the UI creates) is dropped.
        var seen = Set<String>()
        planned = planned.filter { seen.insert($0.id).inserted }
        let kept = Array(planned.sorted { ($0.fireAt, $0.id) < ($1.fireAt, $1.id) }.prefix(budget))
        return ReminderPlan(notifications: kept, droppedByBudget: planned.count - kept.count)
    }

    /// The planner's `prayerStates` input from the tracker's records.
    public static func prayerStates(_ records: some Sequence<PrayerRecord>) -> [PrayerOccurrence: PrayerRecordState] {
        Dictionary(records.map { ($0.occurrence, $0.state) }, uniquingKeysWith: { _, last in last })
    }

    private static func notification(for rule: ReminderRule, times: PrayerSchedule, localDate: String)
        -> PlannedNotification? {
        guard let key = rule.prayerKey else { return nil }
        if key == .asr, times.asrClamped { return nil }
        let prayer: PrayerTime = switch key {
        case .fajr: .fajr
        case .dhuhr: .dhuhr
        case .asr: .asr
        case .maghrib: .maghrib
        case .isha: .isha
        }
        guard let base = times[prayer] else { return nil }
        let offset = rule.offsetMinutes ?? 0
        let target: PlannedNotification.Target
        let id: String
        switch rule.kind {
        case .adhkarMorning:
            target = .adhkar(.morning)
            id = "adhkar.morning.\(localDate)"
        case .adhkarEvening:
            target = .adhkar(.evening)
            id = "adhkar.evening.\(localDate)"
        case .prayer:
            target = .prayer(key)
            id = "prayer.\(key.rawValue).\(localDate)"
        case .personal:
            return nil
        }
        return PlannedNotification(id: id, target: target, localDate: localDate,
                                   fireAt: base.addingTimeInterval(TimeInterval(offset * 60)),
                                   offsetMinutes: offset, isCatchUp: false)
    }
}

extension ReminderRule {
    /// The reminder for one prayer, `offsetMinutes` from its time (negative is before). One rule per prayer.
    public static func prayer(_ key: PrayerKey, offsetMinutes: Int, enabled: Bool, updatedAt: Date) -> ReminderRule {
        ReminderRule(id: prayerId(key), kind: .prayer, prayerKey: key, offsetMinutes: offsetMinutes, localTime: nil,
                     enabled: enabled, updatedAt: updatedAt)
    }

    public static func prayerId(_ key: PrayerKey) -> String { "prayer_\(key.rawValue)" }
}

extension ReminderRule.PrayerKey {
    /// The tracker's prayer for this reminder's key.
    public var obligatory: ObligatoryPrayer {
        switch self {
        case .fajr: .fajr
        case .dhuhr: .dhuhr
        case .asr: .asr
        case .maghrib: .maghrib
        case .isha: .isha
        }
    }
}
