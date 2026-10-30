import AthkarCore
import Foundation
import Testing

struct ProhibitedTimeTests {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!

    /// Fajr 4:00, sunrise 5:30, Dhuhr 12:00, Asr 15:30, Maghrib 18:00, Isha 19:30 (hours since the epoch).
    private func schedule(asrClamped: Bool = false, fajr: Bool = true, sunrise: Bool = true) -> PrayerSchedule {
        func at(_ hours: Double) -> Date { Date(timeIntervalSince1970: hours * 3600) }
        return PrayerSchedule(localDate: "2026-10-30", zone: zone, fajr: fajr ? at(4) : nil,
                              sunrise: sunrise ? at(5.5) : nil, dhuhr: at(12),
                              asr: asrClamped ? at(18) : at(15.5), maghrib: at(18), isha: at(19.5),
                              asrClamped: asrClamped)
    }

    private func at(_ hours: Double, minutes: Double = 0) -> Date {
        Date(timeIntervalSince1970: hours * 3600 + minutes * 60)
    }

    @Test func fromFajrUntilTwentyMinutesAfterSunrise() {
        let day = schedule()
        #expect(ProhibitedTime.current(at: at(3, minutes: 59), today: day) == nil)
        let window = ProhibitedTime(kind: .afterFajr, start: at(4), end: at(5, minutes: 50))
        #expect(ProhibitedTime.current(at: at(4), today: day) == window)
        #expect(ProhibitedTime.current(at: at(5, minutes: 49), today: day) == window)
        // The sun has risen «قيد رمح»: voluntary prayer is allowed again.
        #expect(ProhibitedTime.current(at: at(5, minutes: 50), today: day) == nil)
    }

    @Test func noWindowBeforeDhuhr() {
        // The owner's rule shows no zenith window, so the minutes before Dhuhr are clear.
        #expect(ProhibitedTime.current(at: at(11, minutes: 50), today: schedule()) == nil)
        #expect(ProhibitedTime.current(at: at(12), today: schedule()) == nil)
    }

    @Test func fromAsrUntilTheMaghribAdhan() {
        let day = schedule()
        #expect(ProhibitedTime.current(at: at(15, minutes: 29), today: day) == nil)
        let window = ProhibitedTime(kind: .afterAsr, start: at(15.5), end: at(18))
        #expect(ProhibitedTime.current(at: at(15.5), today: day) == window)
        #expect(ProhibitedTime.current(at: at(17, minutes: 59), today: day) == window)
        #expect(ProhibitedTime.current(at: at(18), today: day) == nil)
        #expect(ProhibitedTime.current(at: at(19.5), today: day) == nil)
    }

    @Test func aClampedAsrOpensNoWindow() {
        #expect(ProhibitedTime.windows(schedule(asrClamped: true)).map(\.kind) == [.afterFajr])
        #expect(ProhibitedTime.current(at: at(17), today: schedule(asrClamped: true)) == nil)
    }

    @Test func aMissingFajrOrSunriseOpensNoMorningWindow() {
        #expect(ProhibitedTime.windows(schedule(fajr: false)).map(\.kind) == [.afterAsr])
        #expect(ProhibitedTime.windows(schedule(sunrise: false)).map(\.kind) == [.afterAsr])
        #expect(ProhibitedTime.windows(schedule()).map(\.kind) == [.afterFajr, .afterAsr])
    }
}
