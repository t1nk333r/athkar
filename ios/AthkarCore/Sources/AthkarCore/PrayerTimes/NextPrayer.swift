import Foundation

/// The prayer the countdown on the prayer-times screen counts to.
public struct NextPrayer: Equatable, Sendable {
    public let prayer: PrayerTime
    public let at: Date

    public init(prayer: PrayerTime, at: Date) {
        self.prayer = prayer
        self.at = at
    }

    /// The five prayers in order; sunrise is shown but is not a prayer.
    public static let prayers: [PrayerTime] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

    /// The first of today's prayers strictly after `now`, else the first of tomorrow's. A time the schedule could not
    /// compute is skipped, and so is a clamped Asr: it is undetermined, not due at Maghrib.
    public static func after(_ now: Date, today: PrayerSchedule, tomorrow: PrayerSchedule?) -> NextPrayer? {
        first(after: now, in: [today, tomorrow].compactMap { $0 })?.next
    }

    /// Today's next prayer (spec/tracker/tracker.md, "Next prayer across a DST change"): ``after(_:today:tomorrow:)``
    /// on the schedules of the civil date of `now` in `zone` and of the next civil date, a calendar day later and not
    /// 24 hours, so a 23- or 25-hour day and a repeated wall-clock hour still name the right day. `nil` without a
    /// schedule for today, or when neither day has a prayer left.
    public static func upcoming(after now: Date, in zone: TimeZone,
                                schedule: (String) -> PrayerSchedule?) -> UpcomingPrayer? {
        let today = SessionCalendar.localDate(of: now, in: zone)
        guard let todaySchedule = schedule(today) else { return nil }
        let tomorrow = LocalDate.adding(1, to: today).flatMap(schedule)
        guard let found = first(after: now, in: [todaySchedule, tomorrow].compactMap { $0 }) else { return nil }
        return UpcomingPrayer(today: today, date: found.date, prayer: found.next.prayer, at: found.next.at)
    }

    private static func first(after now: Date, in schedules: [PrayerSchedule]) -> (next: NextPrayer, date: String)? {
        for schedule in schedules {
            for prayer in prayers where !(prayer == .asr && schedule.asrClamped) {
                guard let at = schedule[prayer], at > now else { continue }
                return (NextPrayer(prayer: prayer, at: at), schedule.localDate)
            }
        }
        return nil
    }
}

/// ``NextPrayer/upcoming(after:in:schedule:)``: the next prayer with the calculation date it belongs to, and today's
/// civil date.
public struct UpcomingPrayer: Equatable, Sendable {
    /// The civil date of the instant asked about.
    public let today: String
    /// The calculation date of the next prayer: `today` or the next civil date.
    public let date: String
    public let prayer: PrayerTime
    public let at: Date

    public var next: NextPrayer { NextPrayer(prayer: prayer, at: at) }
}
