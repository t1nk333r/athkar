import Foundation

/// «أوقات النهي عن الصلاة» as the app shows them: from Fajr until the sun has risen («قيد رمح»), taken as
/// ``afterSunrise`` after sunrise; while the sun stands at its zenith until it passes, taken as the ``beforeDhuhr``
/// before the Dhuhr adhan; and from Asr until the Maghrib adhan. Voluntary prayer is not prayed in them.
///
/// Strictly the first and last begin once Fajr or Asr has been prayed, which the app cannot know, so they open at
/// that adhan and their copy says «من صلاة …». The Dhuhr adhan stands for the zenith's passing, adjustments
/// included, as the Maghrib adhan stands for sunset. A time the schedule could not compute, or a clamped Asr, opens
/// no window.
public struct ProhibitedTime: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// From Fajr until ``afterSunrise`` after sunrise.
        case afterFajr
        /// From ``beforeDhuhr`` before the Dhuhr adhan until the adhan: the sun at its zenith.
        case beforeDhuhr
        /// From Asr until the Maghrib adhan.
        case afterAsr
    }

    public let kind: Kind
    public let start: Date
    public let end: Date

    /// How long after sunrise the sun is taken to have risen «قيد رمح»: the cautious end of the usual 15–20 minutes.
    public static let afterSunrise: TimeInterval = 20 * 60

    /// How long before the Dhuhr adhan the sun is taken to stand at its zenith: «قبيل الزوال», about ten minutes.
    public static let beforeDhuhr: TimeInterval = 10 * 60

    public init(kind: Kind, start: Date, end: Date) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    /// The window `now` falls in (start included, end excluded), if any, from that day's schedule.
    public static func current(at now: Date, today: PrayerSchedule) -> ProhibitedTime? {
        windows(today).first { $0.start <= now && now < $0.end }
    }

    /// The day's windows in order, each only when its bounding times were computed.
    public static func windows(_ day: PrayerSchedule) -> [ProhibitedTime] {
        var windows: [ProhibitedTime] = []
        if let fajr = day.fajr, let sunrise = day.sunrise, fajr < sunrise {
            windows.append(ProhibitedTime(kind: .afterFajr, start: fajr, end: sunrise + afterSunrise))
        }
        if let dhuhr = day.dhuhr {
            windows.append(ProhibitedTime(kind: .beforeDhuhr, start: dhuhr - beforeDhuhr, end: dhuhr))
        }
        if !day.asrClamped, let asr = day.asr, let maghrib = day.maghrib, asr < maghrib {
            windows.append(ProhibitedTime(kind: .afterAsr, start: asr, end: maghrib))
        }
        return windows
    }
}
