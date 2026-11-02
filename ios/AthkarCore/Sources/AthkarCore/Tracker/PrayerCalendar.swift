import Foundation

/// One day of the calendar month (spec/tracker/tracker.md, "Calendar month"): plain counts, with nothing that scores
/// the day. `unrecorded` is neutral and `notApplicable` leaves the denominator.
public struct PrayerDaySummary: Equatable, Sendable {
    public var date: String
    /// 1 Sunday … 7 Saturday.
    public var weekday: Int
    /// After today: read-only.
    public var isFuture: Bool
    public var prayed: Int
    public var notApplicable: Int
    public var morning: Bool
    public var evening: Bool
    public var ruqyah: Bool

    public init(date: String, weekday: Int, isFuture: Bool, prayed: Int, notApplicable: Int, morning: Bool,
                evening: Bool, ruqyah: Bool) {
        self.date = date
        self.weekday = weekday
        self.isFuture = isFuture
        self.prayed = prayed
        self.notApplicable = notApplicable
        self.morning = morning
        self.evening = evening
        self.ruqyah = ruqyah
    }

    /// Occurrences with an `unrecorded` record or none.
    public var unrecorded: Int { ObligatoryPrayer.allCases.count - prayed - notApplicable }
    /// The denominator: the five prayers less those marked not applicable.
    public var applicable: Int { ObligatoryPrayer.allCases.count - notApplicable }
    /// Something is recorded for a prayer that day.
    public var hasPrayerRecords: Bool { prayed > 0 || notApplicable > 0 }
}

/// The month's plain counts.
public struct PrayerMonthTotals: Equatable, Sendable {
    /// Records with `prayed`.
    public var prayed: Int
    /// Days with a morning, evening or ruqyah completion.
    public var morning: Int
    public var evening: Int
    public var ruqyah: Int

    public init(prayed: Int, morning: Int, evening: Int, ruqyah: Int) {
        self.prayed = prayed
        self.morning = morning
        self.evening = evening
        self.ruqyah = ruqyah
    }
}

public struct PrayerCalendarMonth: Equatable, Sendable {
    /// `YYYY-MM`.
    public var month: String
    public var days: [PrayerDaySummary]
    public var totals: PrayerMonthTotals
}

/// A record's state, all the calendar reads of it.
public struct PrayerStateMark: Equatable, Sendable {
    public var date: String
    public var prayer: ObligatoryPrayer
    public var state: PrayerRecordState

    public init(date: String, prayer: ObligatoryPrayer, state: PrayerRecordState) {
        self.date = date
        self.prayer = prayer
        self.state = state
    }
}

public enum PrayerCalendar {
    /// The summary of `month` (`YYYY-MM`), or `nil` unless it names a real month. Marks and completions on other days
    /// are ignored. `morning`, `evening` and `ruqyah` are the dates with an `adhkar_days` or `ruqyah_days` row.
    public static func month(_ month: String, today: String, marks: [PrayerStateMark], morning: Set<String>,
                             evening: Set<String>, ruqyah: Set<String>) -> PrayerCalendarMonth? {
        guard let dates = LocalDate.days(inMonth: month) else { return nil }
        var prayed: [String: Int] = [:]
        var notApplicable: [String: Int] = [:]
        for mark in marks {
            switch mark.state {
            case .prayed: prayed[mark.date, default: 0] += 1
            case .notApplicable: notApplicable[mark.date, default: 0] += 1
            case .unrecorded: break
            }
        }
        let days = dates.map { date in
            PrayerDaySummary(date: date, weekday: LocalDate.weekday(date) ?? 1, isFuture: date > today,
                             prayed: prayed[date] ?? 0, notApplicable: notApplicable[date] ?? 0,
                             morning: morning.contains(date), evening: evening.contains(date),
                             ruqyah: ruqyah.contains(date))
        }
        let totals = PrayerMonthTotals(prayed: days.reduce(0) { $0 + $1.prayed },
                                       morning: days.filter(\.morning).count, evening: days.filter(\.evening).count,
                                       ruqyah: days.filter(\.ruqyah).count)
        return PrayerCalendarMonth(month: month, days: days, totals: totals)
    }
}
