import Foundation

/// «أوقات النهي عن الصلاة», the five of Shaykh Ibn Baz's fatwa (binbaz.org.sa, fatwa 10693), in the day's order:
/// from dawn until sunrise; from sunrise until the sun has risen «قيد رمح», taken as ``afterSunrise``; while it
/// stands at its zenith until it passes, taken as ``beforeDhuhr`` before the Dhuhr adhan; from Asr until the sun
/// yellows; and from the yellowing until it sets. Voluntary prayer is not prayed in them.
///
/// The fourth strictly begins once Asr has been prayed, which the app cannot know, so it opens at the adhan. The
/// Dhuhr and Maghrib adhans stand for the zenith's passing and for sunset. The yellowing is the schedule's estimate
/// (``PrayerSchedule/yellowing``); without it the fourth runs to Maghrib and no fifth opens. A time the schedule
/// could not compute, an empty range, or a clamped Asr opens no window.
public struct ProhibitedTime: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// From the Fajr adhan («طلوع الفجر») until sunrise.
        case afterFajr
        /// From sunrise until ``afterSunrise`` after it.
        case sunrise
        /// From ``beforeDhuhr`` before the Dhuhr adhan until the adhan.
        case zenith
        /// From the Asr adhan until the yellowing, or until Maghrib when the yellowing is unknown.
        case afterAsr
        /// From the yellowing until the Maghrib adhan.
        case sunset
    }

    public let kind: Kind
    public let start: Date
    public let end: Date

    /// How long after sunrise the sun is taken to have risen «قيد رمح»: the cautious end of the usual 15–20 minutes.
    public static let afterSunrise: TimeInterval = 20 * 60

    /// How long before the Dhuhr adhan the sun is taken to stand at its zenith: «وقت قصير نحو ثلث ساعة، أو ربع ساعة»
    /// in the fatwa, at its cautious end as with ``afterSunrise``.
    public static let beforeDhuhr: TimeInterval = 20 * 60

    public init(kind: Kind, start: Date, end: Date) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    /// The window `now` falls in (start included, end excluded), if any, from that day's schedule.
    public static func current(at now: Date, today: PrayerSchedule) -> ProhibitedTime? {
        windows(today).first { $0.start <= now && now < $0.end }
    }

    /// The day's windows in order, each only when its bounding times were computed and it is not empty.
    public static func windows(_ day: PrayerSchedule) -> [ProhibitedTime] {
        var windows: [ProhibitedTime] = []
        func add(_ kind: Kind, from start: Date?, to end: Date?) {
            guard let start, let end, start < end else { return }
            windows.append(ProhibitedTime(kind: kind, start: start, end: end))
        }
        add(.afterFajr, from: day.fajr, to: day.sunrise)
        add(.sunrise, from: day.sunrise, to: day.sunrise.map { $0 + afterSunrise })
        add(.zenith, from: day.dhuhr.map { $0 - beforeDhuhr }, to: day.dhuhr)
        if !day.asrClamped {
            add(.afterAsr, from: day.asr, to: day.yellowing ?? day.maghrib)
        }
        add(.sunset, from: day.yellowing, to: day.maghrib)
        return windows
    }
}
