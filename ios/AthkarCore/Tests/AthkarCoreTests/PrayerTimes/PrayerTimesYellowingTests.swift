import AthkarCore
import Foundation
import Testing

/// ``PrayerSchedule/yellowing``: «اصفرار الشمس» estimated as the double shadow (hanafi Asr), which divides the fourth
/// and fifth of ``ProhibitedTime``'s five times.
struct PrayerTimesYellowingTests {
    private let port = AdhanPrayerTimes()
    private let mecca = GeoCoordinates(latitude: 21.4225, longitude: 39.8262)
    private let riyadh = TimeZone(identifier: "Asia/Riyadh")!

    private func mecca(_ settings: CalculationSettings) throws -> PrayerSchedule {
        try port.schedule(on: "2026-10-30", at: mecca, in: riyadh, settings: settings)
    }

    @Test func isTheDoubleShadowBetweenAsrAndMaghrib() throws {
        let standard = try mecca(CalculationSettings())
        let hanafi = try mecca(CalculationSettings(asrSchool: .hanafi))
        let yellowing = try #require(standard.yellowing)
        #expect(yellowing == hanafi.asr)
        // Under the hanafi school the Asr adhan is the yellowing itself.
        #expect(hanafi.yellowing == yellowing)
        let asr = try #require(standard.asr)
        let maghrib = try #require(standard.maghrib)
        #expect(asr < yellowing && yellowing < maghrib)
    }

    @Test func anAsrAdjustmentMovesTheAdhanNotTheYellowing() throws {
        let plain = try mecca(CalculationSettings())
        let adjusted = try mecca(CalculationSettings(adjustments: PrayerAdjustments(asr: 30)))
        #expect(adjusted.asr == plain.asr?.addingTimeInterval(30 * 60))
        #expect(adjusted.yellowing != nil)
        #expect(adjusted.yellowing == plain.yellowing)
    }

    /// Where Adhan misplaces Asr near the polar night it can misplace the double shadow too; the adapter then gives
    /// none rather than a time outside the afternoon. Without times there is no yellowing either.
    @Test("Near the polar night: unknown, or strictly between Dhuhr and Maghrib", arguments: AsrSchool.allCases)
    func staysInTheAfternoon(school: AsrSchool) throws {
        let tromso = GeoCoordinates(latitude: 69.65, longitude: 18.96)
        let oslo = try #require(TimeZone(identifier: "Europe/Oslo"))
        let dates = (0..<31).map { PrayerTimesTestCalendar.localDate("2026-01-01", adding: $0) }
            + (0..<41).map { PrayerTimesTestCalendar.localDate("2026-11-10", adding: $0) }
        let settings = CalculationSettings(asrSchool: school)
        var known = 0
        for date in dates {
            let day = try port.schedule(on: date, at: tromso, in: oslo, settings: settings)
            guard let dhuhr = day.dhuhr, let maghrib = day.maghrib else {
                #expect(day.yellowing == nil, "\(date): a yellowing without times")
                continue
            }
            guard let yellowing = day.yellowing else { continue }
            known += 1
            #expect(dhuhr < yellowing && yellowing < maghrib, "\(date): \(SessionCalendar.isoString(yellowing))")
        }
        #expect(known > 0, "no day with a yellowing")
    }
}
