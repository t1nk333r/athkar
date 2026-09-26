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
        for schedule in [today, tomorrow].compactMap({ $0 }) {
            for prayer in prayers where !(prayer == .asr && schedule.asrClamped) {
                if let at = schedule[prayer], at > now { return NextPrayer(prayer: prayer, at: at) }
            }
        }
        return nil
    }
}
