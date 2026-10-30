import AthkarCore
import Foundation
import Testing

struct ProhibitedTimeTests {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!

    /// Fajr 4:00, sunrise 5:30, Dhuhr 12:00, Asr 15:30, Maghrib 18:00, Isha 19:30 (hours since the epoch).
    private func schedule(asrClamped: Bool = false, fajr: Bool = true, sunrise: Bool = true,
                          dhuhr: Bool = true) -> PrayerSchedule {
        func at(_ hours: Double) -> Date { Date(timeIntervalSince1970: hours * 3600) }
        return PrayerSchedule(localDate: "2026-10-30", zone: zone, fajr: fajr ? at(4) : nil,
                              sunrise: sunrise ? at(5.5) : nil, dhuhr: dhuhr ? at(12) : nil,
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

    @Test func fromTenMinutesBeforeTheDhuhrAdhanUntilIt() {
        let day = schedule()
        #expect(ProhibitedTime.current(at: at(11, minutes: 49), today: day) == nil)
        let window = ProhibitedTime(kind: .beforeDhuhr, start: at(11, minutes: 50), end: at(12))
        #expect(ProhibitedTime.current(at: at(11, minutes: 50), today: day) == window)
        #expect(ProhibitedTime.current(at: at(11, minutes: 59), today: day) == window)
        // The sun has passed its zenith: the Dhuhr adhan.
        #expect(ProhibitedTime.current(at: at(12), today: day) == nil)
    }

    @Test func aMissingDhuhrOpensNoZenithWindow() {
        #expect(ProhibitedTime.windows(schedule(dhuhr: false)).map(\.kind) == [.afterFajr, .afterAsr])
        #expect(ProhibitedTime.current(at: at(11, minutes: 55), today: schedule(dhuhr: false)) == nil)
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
        #expect(ProhibitedTime.windows(schedule(asrClamped: true)).map(\.kind) == [.afterFajr, .beforeDhuhr])
        #expect(ProhibitedTime.current(at: at(17), today: schedule(asrClamped: true)) == nil)
    }

    @Test func aMissingFajrOrSunriseOpensNoMorningWindow() {
        #expect(ProhibitedTime.windows(schedule(fajr: false)).map(\.kind) == [.beforeDhuhr, .afterAsr])
        #expect(ProhibitedTime.windows(schedule(sunrise: false)).map(\.kind) == [.beforeDhuhr, .afterAsr])
        #expect(ProhibitedTime.windows(schedule()).map(\.kind) == [.afterFajr, .beforeDhuhr, .afterAsr])
    }

    @Test func anEmptyOrInvertedRangeOpensNoWindow() {
        func kinds(fajr: Double, sunrise: Double, asr: Double) -> [ProhibitedTime.Kind] {
            let day = PrayerSchedule(localDate: "2026-10-30", zone: zone, fajr: at(fajr), sunrise: at(sunrise),
                                     dhuhr: at(12), asr: at(asr), maghrib: at(18), isha: at(19.5), asrClamped: false)
            return ProhibitedTime.windows(day).map(\.kind)
        }
        #expect(kinds(fajr: 5.5, sunrise: 4, asr: 15.5) == [.beforeDhuhr, .afterAsr])
        #expect(kinds(fajr: 5.5, sunrise: 5.5, asr: 15.5) == [.beforeDhuhr, .afterAsr])
        #expect(kinds(fajr: 4, sunrise: 5.5, asr: 18) == [.afterFajr, .beforeDhuhr])
        #expect(kinds(fajr: 4, sunrise: 5.5, asr: 19) == [.afterFajr, .beforeDhuhr])
    }
}
