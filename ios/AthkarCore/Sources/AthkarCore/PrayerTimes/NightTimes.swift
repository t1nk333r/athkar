import Foundation

/// A local date's Maghrib and Fajr (spec/night/night.md, "Times"). Either is `nil` when it cannot be computed.
public struct NightTimes: Equatable, Sendable {
    public let fajr: Date?
    public let maghrib: Date?

    public init(fajr: Date?, maghrib: Date?) {
        self.fajr = fajr
        self.maghrib = maghrib
    }

    public init(_ schedule: PrayerSchedule) {
        self.init(fajr: schedule.fajr, maghrib: schedule.maghrib)
    }
}

/// «ليلة الجمعة» or «يوم الجمعة», when the «الصلاة على النبي ﷺ» page names the time (spec/night/night.md,
/// "Friday window").
public enum FridayPhase: String, Equatable, Sendable {
    case night, day

    public var title: String {
        switch self {
        case .night: "ليلة الجمعة"
        case .day: "يوم الجمعة"
        }
    }

    /// From Thursday's Maghrib to Friday's Fajr the night, then the day until Friday's Maghrib; `nil` otherwise.
    /// Without a Maghrib there is no night, and without a Fajr all of Friday before Maghrib is the day.
    public static func at(_ now: Date, in zone: TimeZone, times: (String) -> NightTimes?) -> FridayPhase? {
        let today = SessionCalendar.localDate(of: now, in: zone)
        switch LocalDate.weekday(today) {
        case 5:
            guard let maghrib = times(today)?.maghrib, now >= maghrib else { return nil }
            return .night
        case 6:
            let times = times(today)
            if let maghrib = times?.maghrib, now >= maghrib { return nil }
            if let fajr = times?.fajr, now < fajr { return .night }
            return .day
        default:
            return nil
        }
    }
}

/// The last third of a night, from two thirds of the way between Maghrib and the next Fajr to that Fajr
/// (spec/night/night.md, "Last third of the night").
public struct LastThird: Equatable, Sendable {
    public let start: Date
    public let end: Date

    /// `nil` without both times, or when Fajr is not after Maghrib. The start is rounded to the millisecond, half up,
    /// as the PWA's `Math.round` does.
    public init?(maghrib: Date?, fajr: Date?) {
        guard let maghrib, let fajr, fajr > maghrib else { return nil }
        let nightMs = (fajr.timeIntervalSince(maghrib) * 1000).rounded()
        start = maghrib.addingTimeInterval((nightMs * 2 / 3).rounded() / 1000)
        end = fajr
    }

    public func contains(_ now: Date) -> Bool { now >= start && now < end }

    /// The night from `localDate`'s Maghrib to the next calendar day's Fajr.
    public static func night(after localDate: String, times: (String) -> NightTimes?) -> LastThird? {
        guard let next = LocalDate.adding(1, to: localDate) else { return nil }
        return LastThird(maghrib: times(localDate)?.maghrib, fajr: times(next)?.fajr)
    }

    /// The night `now` is in, or the next one: before today's Fajr, the night that began at yesterday's Maghrib; from
    /// it on, or when today has no Fajr, the night that begins at today's.
    public static func tonight(at now: Date, in zone: TimeZone, times: (String) -> NightTimes?) -> LastThird? {
        let today = SessionCalendar.localDate(of: now, in: zone)
        if let fajr = times(today)?.fajr, now < fajr {
            guard let yesterday = LocalDate.adding(-1, to: today) else { return nil }
            return LastThird(maghrib: times(yesterday)?.maghrib, fajr: fajr)
        }
        return night(after: today, times: times)
    }
}
