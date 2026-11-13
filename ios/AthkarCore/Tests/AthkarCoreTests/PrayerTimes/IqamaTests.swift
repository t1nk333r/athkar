import AthkarCore
import Foundation
import Testing

struct IqamaTests {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!

    /// Local `hour`:`minute` on 1970-01-0(`day` + 4) in Riyadh, which is UTC+3 all year: day 0 is a Sunday, so no
    /// day before 5 is a Friday, when Dhuhr has no iqama.
    private func local(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: TimeInterval((((day + 3) * 24 + hour - 3) * 60 + minute) * 60))
    }

    private func schedule(day: Int, asrClamped: Bool = false, isha: (Int, Int) = (19, 30)) -> PrayerSchedule {
        PrayerSchedule(localDate: "1970-01-0\(day + 4)", zone: zone, fajr: local(day: day, 4),
                       sunrise: local(day: day, 5, 30), dhuhr: local(day: day, 12),
                       asr: asrClamped ? local(day: day, 18) : local(day: day, 15, 30), maghrib: local(day: day, 18),
                       isha: local(day: day, isha.0, isha.1), asrClamped: asrClamped)
    }

    private var days: [PrayerSchedule] { [schedule(day: 0), schedule(day: 1), schedule(day: 2)] }

    private func countdown(_ now: Date, delays: IqamaDelays = IqamaDelays(),
                           schedules: [PrayerSchedule]) -> PrayerCountdown? {
        PrayerCountdown.at(now, in: zone, delays: delays) { date in schedules.first { $0.localDate == date } }
    }

    @Test func iqamaIsTheAdhanPlusItsDelay() {
        let day = schedule(day: 1)
        let delays = IqamaDelays()
        #expect(delays.iqama(of: .fajr, in: day) == local(day: 1, 4, 25))
        #expect(delays.iqama(of: .dhuhr, in: day) == local(day: 1, 12, 20))
        #expect(delays.iqama(of: .asr, in: day) == local(day: 1, 15, 50))
        #expect(delays.iqama(of: .maghrib, in: day) == local(day: 1, 18, 10))
        #expect(delays.iqama(of: .isha, in: day) == local(day: 1, 19, 50))
        #expect(delays.iqama(of: .sunrise, in: day) == nil)
        #expect(IqamaDelays(dhuhr: 0).iqama(of: .dhuhr, in: day) == nil)
        #expect(delays.iqama(of: .asr, in: schedule(day: 1, asrClamped: true)) == nil)
    }

    /// Day 5 is Friday 1970-01-09: Jumu'ah's iqama follows the khutbah, so Dhuhr has none and the counters go from
    /// its adhan to Asr's. The other prayers keep theirs.
    @Test func aFridayDhuhrHasNoIqama() {
        let friday = schedule(day: 5)
        #expect(IqamaDelays.followsKhutbah(.dhuhr, in: friday))
        #expect(!IqamaDelays.followsKhutbah(.dhuhr, in: schedule(day: 4)))
        #expect(!IqamaDelays.followsKhutbah(.asr, in: friday))
        #expect(IqamaDelays().iqama(of: .dhuhr, in: friday) == nil)
        #expect(IqamaDelays().iqama(of: .asr, in: friday) == local(day: 5, 15, 50))
        #expect(countdown(local(day: 5, 12, 5), schedules: [schedule(day: 4), friday])
                == PrayerCountdown(event: .adhan, prayer: .asr, at: local(day: 5, 15, 30), date: "1970-01-09"))
    }

    @Test func beforeTheAdhanItCountsToTheAdhan() {
        #expect(countdown(local(day: 1, 11, 30), schedules: days)
                == PrayerCountdown(event: .adhan, prayer: .dhuhr, at: local(day: 1, 12), date: "1970-01-05"))
    }

    /// From the adhan itself until the iqama, then on to the next adhan.
    @Test func afterTheAdhanItCountsToTheIqamaThenTheNextAdhan() {
        let iqama = PrayerCountdown(event: .iqama, prayer: .dhuhr, at: local(day: 1, 12, 20), date: "1970-01-05")
        #expect(countdown(local(day: 1, 12), schedules: days) == iqama)
        #expect(countdown(local(day: 1, 12, 19), schedules: days) == iqama)
        #expect(countdown(local(day: 1, 12, 20), schedules: days)
                == PrayerCountdown(event: .adhan, prayer: .asr, at: local(day: 1, 15, 30), date: "1970-01-05"))
    }

    @Test func aZeroDelayGoesStraightToTheNextAdhan() {
        #expect(countdown(local(day: 1, 18, 3), delays: IqamaDelays(maghrib: 0), schedules: days)
                == PrayerCountdown(event: .adhan, prayer: .isha, at: local(day: 1, 19, 30), date: "1970-01-05"))
    }

    /// The clamped Asr shares Maghrib's instant; only Maghrib's iqama counts, and after it Isha's adhan, not an Asr
    /// iqama at 18:20.
    @Test func aClampedAsrHasNoIqama() {
        let clamped = [schedule(day: 0), schedule(day: 1, asrClamped: true)]
        #expect(countdown(local(day: 1, 18, 3), schedules: clamped)
                == PrayerCountdown(event: .iqama, prayer: .maghrib, at: local(day: 1, 18, 10), date: "1970-01-05"))
        #expect(countdown(local(day: 1, 18, 15), schedules: clamped)
                == PrayerCountdown(event: .adhan, prayer: .isha, at: local(day: 1, 19, 30), date: "1970-01-05"))
    }

    /// An Isha at 23:50 has its iqama at 00:10 the next civil day, still counted from yesterday's schedule.
    @Test func anIshaIqamaAfterMidnightComesFromYesterday() {
        let late = [schedule(day: 0), schedule(day: 1, isha: (23, 50)), schedule(day: 2)]
        #expect(countdown(local(day: 2, 0, 3), schedules: late)
                == PrayerCountdown(event: .iqama, prayer: .isha, at: local(day: 2, 0, 10), date: "1970-01-05"))
        #expect(countdown(local(day: 2, 0, 10), schedules: late)
                == PrayerCountdown(event: .adhan, prayer: .fajr, at: local(day: 2, 4), date: "1970-01-06"))
    }

    /// When a long delay outlasts the next adhan, the latest adhan's iqama is the one counted.
    @Test func theLatestAdhanWins() {
        let close = [schedule(day: 0), schedule(day: 1, isha: (18, 45))]
        #expect(countdown(local(day: 1, 18, 50), delays: IqamaDelays(maghrib: 60), schedules: close)
                == PrayerCountdown(event: .iqama, prayer: .isha, at: local(day: 1, 19, 5), date: "1970-01-05"))
    }

    @Test func withoutSchedulesThereIsNothingToCount() {
        #expect(countdown(local(day: 1, 12), schedules: []) == nil)
    }
}
