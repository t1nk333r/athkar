import AthkarCore
import Foundation
import Testing

/// Umm al-Qura's Isha is 120 minutes after Maghrib on the days the Umm al-Qura calendar, shifted by the user's Hijri
/// offset, counts as Ramadan (spec/prayer-times/README.md, "Ramadan Isha"). In that calendar Ramadan 1448 runs from
/// 2027-02-08 to 2027-03-08.
@Suite("Prayer times: Umm al-Qura's Isha in Ramadan")
struct UmmAlQuraRamadanTests {
    private let port = AdhanPrayerTimes()
    private let mecca = GeoCoordinates(latitude: 21.42, longitude: 39.83)
    private let zone = TimeZone(identifier: "Asia/Riyadh")!

    private func schedule(_ date: String, _ method: CalculationMethod = .ummAlQura, offset: Int = 0,
                          adjustments: PrayerAdjustments = PrayerAdjustments()) throws -> PrayerSchedule {
        try port.schedule(on: date, at: mecca, in: zone,
                          settings: CalculationSettings(method: method, adjustments: adjustments, hijriOffset: offset))
    }

    private func ishaMinutes(_ date: String, offset: Int = 0) throws -> Double {
        let day = try schedule(date, offset: offset)
        return try #require(day.isha).timeIntervalSince(try #require(day.maghrib)) / 60
    }

    @Test func ishaIsTwoHoursAfterMaghribThroughRamadan() throws {
        #expect(try ishaMinutes("2027-02-07") == 90) // 30 Sha'ban
        #expect(try ishaMinutes("2027-02-08") == 120) // 1 Ramadan
        #expect(try ishaMinutes("2027-03-08") == 120) // 29 Ramadan
        #expect(try ishaMinutes("2027-03-09") == 90) // 1 Shawwal
    }

    /// The offset moves Ramadan with the Hijri date the app shows.
    @Test func theHijriOffsetMovesRamadan() throws {
        #expect(try ishaMinutes("2027-02-07", offset: 1) == 120)
        #expect(try ishaMinutes("2027-02-08", offset: -1) == 90)
        #expect(try ishaMinutes("2027-03-08", offset: 1) == 90)
        #expect(try ishaMinutes("2027-03-09", offset: -1) == 120)
    }

    /// Only Isha moves: the other five times are those of the same day outside Ramadan (with an offset of 2, the
    /// app shows 29 Ramadan as 2 Shawwal).
    @Test func onlyIshaMoves() throws {
        let ramadan = try schedule("2027-03-08")
        let shawwal = try schedule("2027-03-08", offset: 2)
        for time in PrayerTime.allCases where time != .isha {
            #expect(ramadan[time] == shawwal[time], "\(time.rawValue)")
        }
        #expect(try #require(ramadan.isha).timeIntervalSince(try #require(shawwal.isha)) == 30 * 60)
    }

    /// The user's Isha adjustment still applies on top.
    @Test func theIshaAdjustmentAddsToIt() throws {
        let day = try schedule("2027-02-20", adjustments: PrayerAdjustments(isha: 5))
        #expect(try #require(day.isha).timeIntervalSince(try #require(day.maghrib)) == 125 * 60)
    }

    /// Qatar's interval stays 90 minutes, and the other methods ignore the month.
    @Test(arguments: [CalculationMethod.qatar, .mwl, .egyptian, .moonsightingCommittee])
    func otherMethodsIgnoreRamadan(_ method: CalculationMethod) throws {
        #expect(try schedule("2027-03-08", method) == schedule("2027-03-08", method, offset: 2))
    }
}
