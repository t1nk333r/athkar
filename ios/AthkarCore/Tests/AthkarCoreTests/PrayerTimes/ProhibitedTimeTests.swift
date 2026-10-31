import AthkarCore
import Foundation
import Testing

struct ProhibitedTimeTests {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!

    /// Fajr 4:00, sunrise 5:30, Dhuhr 12:00, Asr 15:30, yellowing 17:00, Maghrib 18:00, Isha 19:30 (hours since the
    /// epoch).
    private func schedule(asrClamped: Bool = false, fajr: Bool = true, sunrise: Bool = true, dhuhr: Bool = true,
                          yellowing: Double? = 17) -> PrayerSchedule {
        func at(_ hours: Double) -> Date { Date(timeIntervalSince1970: hours * 3600) }
        return PrayerSchedule(localDate: "2026-10-30", zone: zone, fajr: fajr ? at(4) : nil,
                              sunrise: sunrise ? at(5.5) : nil, dhuhr: dhuhr ? at(12) : nil,
                              asr: asrClamped ? at(18) : at(15.5), maghrib: at(18), isha: at(19.5),
                              asrClamped: asrClamped, yellowing: yellowing.map(at))
    }

    private func at(_ hours: Double, minutes: Double = 0) -> Date {
        Date(timeIntervalSince1970: hours * 3600 + minutes * 60)
    }

    @Test func fromFajrUntilTwentyMinutesAfterSunrise() {
        let day = schedule()
        #expect(ProhibitedTime.current(at: at(3, minutes: 59), today: day) == nil)
        let dawn = ProhibitedTime(kind: .afterFajr, start: at(4), end: at(5.5))
        #expect(ProhibitedTime.current(at: at(4), today: day) == dawn)
        #expect(ProhibitedTime.current(at: at(5, minutes: 29), today: day) == dawn)
        // At sunrise the second time follows the first without a gap.
        let sunrise = ProhibitedTime(kind: .sunrise, start: at(5.5), end: at(5, minutes: 50))
        #expect(ProhibitedTime.current(at: at(5.5), today: day) == sunrise)
        #expect(ProhibitedTime.current(at: at(5, minutes: 49), today: day) == sunrise)
        // The sun has risen «قيد رمح»: voluntary prayer is allowed again.
        #expect(ProhibitedTime.current(at: at(5, minutes: 50), today: day) == nil)
    }

    @Test func fromTwentyMinutesBeforeTheDhuhrAdhanUntilIt() {
        let day = schedule()
        #expect(ProhibitedTime.current(at: at(11, minutes: 39), today: day) == nil)
        let window = ProhibitedTime(kind: .zenith, start: at(11, minutes: 40), end: at(12))
        #expect(ProhibitedTime.current(at: at(11, minutes: 40), today: day) == window)
        #expect(ProhibitedTime.current(at: at(11, minutes: 59), today: day) == window)
        // The sun has passed its zenith: the Dhuhr adhan.
        #expect(ProhibitedTime.current(at: at(12), today: day) == nil)
    }

    @Test func fromAsrUntilTheMaghribAdhan() {
        let day = schedule()
        #expect(ProhibitedTime.current(at: at(15, minutes: 29), today: day) == nil)
        let afterAsr = ProhibitedTime(kind: .afterAsr, start: at(15.5), end: at(17))
        #expect(ProhibitedTime.current(at: at(15.5), today: day) == afterAsr)
        #expect(ProhibitedTime.current(at: at(16, minutes: 59), today: day) == afterAsr)
        // At the yellowing the fifth time follows the fourth without a gap.
        let sunset = ProhibitedTime(kind: .sunset, start: at(17), end: at(18))
        #expect(ProhibitedTime.current(at: at(17), today: day) == sunset)
        #expect(ProhibitedTime.current(at: at(17, minutes: 59), today: day) == sunset)
        #expect(ProhibitedTime.current(at: at(18), today: day) == nil)
        #expect(ProhibitedTime.current(at: at(19.5), today: day) == nil)
    }

    @Test func fiveTimesInTheDaysOrder() {
        #expect(ProhibitedTime.windows(schedule()).map(\.kind) == [.afterFajr, .sunrise, .zenith, .afterAsr, .sunset])
    }

    @Test func withoutTheYellowingTheFourthRunsToMaghrib() {
        let day = schedule(yellowing: nil)
        #expect(ProhibitedTime.windows(day).map(\.kind) == [.afterFajr, .sunrise, .zenith, .afterAsr])
        let window = ProhibitedTime(kind: .afterAsr, start: at(15.5), end: at(18))
        #expect(ProhibitedTime.current(at: at(17, minutes: 59), today: day) == window)
    }

    @Test func aYellowingAtAsrLeavesOnlyTheFifth() {
        // Under the hanafi school the Asr adhan is the double shadow itself; an adjustment can put it later still.
        for yellowing in [15.5, 15.0] {
            let day = schedule(yellowing: yellowing)
            #expect(ProhibitedTime.windows(day).map(\.kind) == [.afterFajr, .sunrise, .zenith, .sunset])
            let window = ProhibitedTime(kind: .sunset, start: at(yellowing), end: at(18))
            #expect(ProhibitedTime.current(at: at(15.5), today: day) == window)
        }
    }

    @Test func aClampedAsrOpensNoFourthWindow() {
        #expect(ProhibitedTime.windows(schedule(asrClamped: true, yellowing: nil)).map(\.kind)
                == [.afterFajr, .sunrise, .zenith])
        #expect(ProhibitedTime.current(at: at(17), today: schedule(asrClamped: true, yellowing: nil)) == nil)
        // The yellowing is the Sun's, not the adhan's: an Asr adjusted past Maghrib leaves the fifth time in place.
        #expect(ProhibitedTime.windows(schedule(asrClamped: true)).map(\.kind)
                == [.afterFajr, .sunrise, .zenith, .sunset])
    }

    @Test func aMissingTimeDropsTheWindowsItBounds() {
        #expect(ProhibitedTime.windows(schedule(fajr: false)).map(\.kind) == [.sunrise, .zenith, .afterAsr, .sunset])
        #expect(ProhibitedTime.windows(schedule(sunrise: false)).map(\.kind) == [.zenith, .afterAsr, .sunset])
        #expect(ProhibitedTime.windows(schedule(dhuhr: false)).map(\.kind)
                == [.afterFajr, .sunrise, .afterAsr, .sunset])
        #expect(ProhibitedTime.current(at: at(11, minutes: 55), today: schedule(dhuhr: false)) == nil)
    }

    @Test func anEmptyOrInvertedRangeOpensNoWindow() {
        func kinds(fajr: Double, sunrise: Double, asr: Double) -> [ProhibitedTime.Kind] {
            let day = PrayerSchedule(localDate: "2026-10-30", zone: zone, fajr: at(fajr), sunrise: at(sunrise),
                                     dhuhr: at(12), asr: at(asr), maghrib: at(18), isha: at(19.5), asrClamped: false,
                                     yellowing: at(17))
            return ProhibitedTime.windows(day).map(\.kind)
        }
        #expect(kinds(fajr: 5.5, sunrise: 4, asr: 15.5) == [.sunrise, .zenith, .afterAsr, .sunset])
        #expect(kinds(fajr: 5.5, sunrise: 5.5, asr: 15.5) == [.sunrise, .zenith, .afterAsr, .sunset])
        #expect(kinds(fajr: 4, sunrise: 5.5, asr: 18) == [.afterFajr, .sunrise, .zenith, .sunset])
        #expect(kinds(fajr: 4, sunrise: 5.5, asr: 19) == [.afterFajr, .sunrise, .zenith, .sunset])
    }
}
