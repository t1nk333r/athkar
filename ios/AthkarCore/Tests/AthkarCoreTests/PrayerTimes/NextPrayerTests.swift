import AthkarCore
import Foundation
import Testing

struct NextPrayerTests {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!

    private func schedule(_ date: String, hour base: Double, asrClamped: Bool = false, empty: Bool = false)
        -> PrayerSchedule {
        func at(_ hours: Double) -> Date? { empty ? nil : Date(timeIntervalSince1970: (base + hours) * 3600) }
        return PrayerSchedule(localDate: date, zone: zone, fajr: at(4), sunrise: at(5.5), dhuhr: at(12),
                              asr: asrClamped ? at(18) : at(15.5), maghrib: at(18), isha: at(19.5),
                              asrClamped: asrClamped)
    }

    @Test func picksTheFirstPrayerAfterNowAndSkipsSunrise() {
        let today = schedule("2026-09-26", hour: 0)
        let tomorrow = schedule("2026-09-27", hour: 24)
        #expect(NextPrayer.after(Date(timeIntervalSince1970: 3 * 3600), today: today, tomorrow: tomorrow)?.prayer == .fajr)
        #expect(NextPrayer.after(Date(timeIntervalSince1970: 5 * 3600), today: today, tomorrow: tomorrow)?.prayer == .dhuhr)
        // Exactly at Dhuhr, the next one is Asr.
        #expect(NextPrayer.after(Date(timeIntervalSince1970: 12 * 3600), today: today, tomorrow: tomorrow)?.prayer == .asr)
    }

    @Test func afterIshaItIsTomorrowsFajr() {
        let next = NextPrayer.after(Date(timeIntervalSince1970: 20 * 3600), today: schedule("2026-09-26", hour: 0),
                                    tomorrow: schedule("2026-09-27", hour: 24))
        #expect(next == NextPrayer(prayer: .fajr, at: Date(timeIntervalSince1970: 28 * 3600)))
    }

    @Test func aClampedAsrIsUndeterminedSoMaghribFollowsDhuhr() {
        let next = NextPrayer.after(Date(timeIntervalSince1970: 13 * 3600),
                                    today: schedule("2026-09-26", hour: 0, asrClamped: true), tomorrow: nil)
        #expect(next?.prayer == .maghrib)
    }

    @Test func timesThatCannotBeComputedAreSkipped() {
        let polar = schedule("2026-09-26", hour: 0, empty: true)
        #expect(NextPrayer.after(Date(timeIntervalSince1970: 0), today: polar, tomorrow: polar) == nil)
        let next = NextPrayer.after(Date(timeIntervalSince1970: 0), today: polar,
                                    tomorrow: schedule("2026-09-27", hour: 24))
        #expect(next?.prayer == .fajr)
    }
}

struct UnsetMethodDefaultTests {
    @Test func ummAlQuraUpToFortyEightDegreesThenMWL() {
        #expect(CalculationMethod.unsetDefault(latitude: 24.71) == .ummAlQura) // Riyadh
        #expect(CalculationMethod.unsetDefault(latitude: 48) == .ummAlQura)
        #expect(CalculationMethod.unsetDefault(latitude: 48.01) == .mwl)
        #expect(CalculationMethod.unsetDefault(latitude: -53.16) == .mwl) // Punta Arenas
        #expect(CalculationMethod.unsetDefault(latitude: nil) == .ummAlQura)
    }

    /// Why the limit exists: at Fairbanks in June, Umm al-Qura's Isha (Maghrib + 90 min) is after the next Fajr,
    /// while MWL with the default rule keeps a positive night.
    @Test func ummAlQuraIshaPassesTheNextFajrFarNorth() throws {
        let zone = TimeZone(identifier: "America/Anchorage")!
        let place = GeoCoordinates(latitude: 64.84, longitude: -147.72)
        func night(_ method: CalculationMethod) throws -> TimeInterval {
            let port = AdhanPrayerTimes()
            let settings = CalculationSettings(method: method)
            let today = try port.schedule(on: "2026-06-21", at: place, in: zone, settings: settings)
            let tomorrow = try port.schedule(on: "2026-06-22", at: place, in: zone, settings: settings)
            return try #require(tomorrow.fajr).timeIntervalSince(try #require(today.isha))
        }
        #expect(try night(.ummAlQura) < 0)
        #expect(try night(.mwl) > 0)
    }
}
