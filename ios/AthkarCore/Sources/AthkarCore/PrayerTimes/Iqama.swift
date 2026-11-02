import Foundation

/// Whole minutes from each prayer's adhan to its iqama, when the congregation stands for the prayer. The defaults are
/// the waits Saudi Arabia's Ministry of Islamic Affairs set for its mosques: 25 at Fajr, 10 at Maghrib and 20 for the
/// rest (https://x.com/Saudi_Moia/status/1406558753340772361, 2021). A zero delay shows no iqama for that prayer.
public struct IqamaDelays: Codable, Equatable, Sendable {
    /// What the settings offer and a backup accepts.
    public static let range = 0...60

    public var fajr: Int
    public var dhuhr: Int
    public var asr: Int
    public var maghrib: Int
    public var isha: Int

    public init(fajr: Int = 25, dhuhr: Int = 20, asr: Int = 20, maghrib: Int = 10, isha: Int = 20) {
        self.fajr = fajr
        self.dhuhr = dhuhr
        self.asr = asr
        self.maghrib = maghrib
        self.isha = isha
    }

    public subscript(prayer: ObligatoryPrayer) -> Int {
        get {
            switch prayer {
            case .fajr: fajr
            case .dhuhr: dhuhr
            case .asr: asr
            case .maghrib: maghrib
            case .isha: isha
            }
        }
        set {
            switch prayer {
            case .fajr: fajr = newValue
            case .dhuhr: dhuhr = newValue
            case .asr: asr = newValue
            case .maghrib: maghrib = newValue
            case .isha: isha = newValue
            }
        }
    }

    /// The iqama of `time` in `schedule`: its adhan plus the delay. `nil` for sunrise, a zero delay, a time the
    /// schedule could not compute, and a clamped Asr, which is undetermined.
    public func iqama(of time: PrayerTime, in schedule: PrayerSchedule) -> Date? {
        guard let prayer = ObligatoryPrayer(rawValue: time.rawValue), self[prayer] > 0,
              !(time == .asr && schedule.asrClamped), let adhan = schedule[time] else { return nil }
        return adhan.addingTimeInterval(TimeInterval(self[prayer] * 60))
    }
}

/// What the prayer counters count down to: the iqama of a prayer whose adhan has sounded, until it is due, and
/// otherwise the next adhan (``NextPrayer``).
public struct PrayerCountdown: Equatable, Sendable {
    public enum Event: String, Equatable, Sendable {
        case adhan, iqama
    }

    public let event: Event
    public let prayer: PrayerTime
    public let at: Date
    /// The calculation date the prayer belongs to.
    public let date: String

    public init(event: Event, prayer: PrayerTime, at: Date, date: String) {
        self.event = event
        self.prayer = prayer
        self.at = at
        self.date = date
    }

    /// At `now` in `zone`: the iqama still ahead of the latest adhan at or before `now`, from yesterday's schedule as
    /// well as today's (an Isha iqama can fall after midnight), else the next adhan by
    /// ``NextPrayer/upcoming(after:in:schedule:)``. `nil` when there is neither.
    public static func at(_ now: Date, in zone: TimeZone, delays: IqamaDelays,
                          schedule: (String) -> PrayerSchedule?) -> PrayerCountdown? {
        let today = SessionCalendar.localDate(of: now, in: zone)
        var pending: PrayerCountdown?
        for day in [LocalDate.adding(-1, to: today), today].compactMap({ $0 }).compactMap(schedule) {
            for prayer in NextPrayer.prayers {
                guard let adhan = day[prayer], adhan <= now, let iqama = delays.iqama(of: prayer, in: day),
                      iqama > now else { continue }
                pending = PrayerCountdown(event: .iqama, prayer: prayer, at: iqama, date: day.localDate)
            }
        }
        if let pending { return pending }
        return NextPrayer.upcoming(after: now, in: zone, schedule: schedule).map {
            PrayerCountdown(event: .adhan, prayer: $0.prayer, at: $0.at, date: $0.date)
        }
    }
}
