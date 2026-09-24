import AthkarCore
import Foundation
import Testing

/// P3 (NATIVE_APP_PLAN.md §7.2): places and days where prayer-time code usually breaks. The gate fails on a nil
/// result, a negative night, or Fajr after sunrise; each case and its documented behaviour is listed in
/// spec/prayer-times/README.md.
@Suite("Prayer times P3: edge cases")
struct PrayerTimesEdgeCaseTests {
    struct Place: CustomTestStringConvertible, Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
        let zone: String

        var testDescription: String { name }
        var coordinates: GeoCoordinates { GeoCoordinates(latitude: latitude, longitude: longitude) }
    }

    private let port = AdhanPrayerTimes()

    private func schedule(_ place: Place, _ date: String,
                          settings: CalculationSettings = CalculationSettings()) throws -> PrayerSchedule {
        try port.schedule(on: date, at: place.coordinates, in: try #require(TimeZone(identifier: place.zone)),
                          settings: settings)
    }

    /// All six times exist and are strictly increasing; `onDate` of them fall on the schedule's local date.
    private func checkDay(_ schedule: PrayerSchedule, onDate: [PrayerTime] = PrayerTime.allCases,
                          _ label: String) throws {
        let times = try PrayerTime.allCases.map { time in
            try #require(schedule[time], "\(label): no \(time.rawValue)")
        }
        for (earlier, later) in zip(times, times.dropFirst()) {
            #expect(earlier < later, "\(label): times out of order \(times.map(SessionCalendar.isoString))")
        }
        for time in onDate {
            let local = PrayerTimesTestCalendar.localDate(of: schedule[time]!, in: schedule.zone)
            #expect(local == schedule.localDate, "\(label): \(time.rawValue) falls on \(local)")
        }
    }

    // MARK: Equator

    static let pontianak = Place(name: "Pontianak (0.03° S)", latitude: -0.03, longitude: 109.33,
                                 zone: "Asia/Pontianak")

    @Test("Equator: complete day of about 12 h 7 min all year", arguments: ["2026-03-20", "2026-06-21", "2026-12-21"])
    func equator(date: String) throws {
        let day = try schedule(Self.pontianak, date)
        try checkDay(day, date)
        let daylight = day.maghrib!.timeIntervalSince(day.sunrise!)
        #expect((12 * 3600...12 * 3600 + 15 * 60).contains(daylight), "\(date): daylight \(daylight) s")
    }

    @Test("Equator at the equinox: the Sun passes overhead, so Asr (shadow = object) is 3 h after noon")
    func equatorEquinoxAsr() throws {
        let day = try schedule(Self.pontianak, "2026-03-20")
        let afterNoon = day.asr!.timeIntervalSince(day.dhuhr!)
        #expect(abs(afterNoon - 3 * 3600) <= 5 * 60, "Asr \(afterNoon) s after Dhuhr")
    }

    // MARK: High latitude in June

    static let northernSummer = [
        Place(name: "Helsinki (60.17° N)", latitude: 60.17, longitude: 24.94, zone: "Europe/Helsinki"),
        Place(name: "Reykjavík (64.15° N)", latitude: 64.15, longitude: -21.94, zone: "Atlantic/Reykjavik"),
        Place(name: "Fairbanks (64.84° N)", latitude: 64.84, longitude: -147.72, zone: "America/Anchorage"),
        Place(name: "Luleå (65.58° N)", latitude: 65.58, longitude: 22.15, zone: "Europe/Stockholm"),
    ]

    /// Twilight never ends at these latitudes in June, so Fajr and Isha come from the high-latitude rule. Maghrib and
    /// Isha can fall after local midnight (Reykjavík: sunset 00:04), so only Fajr through Asr must be on the date.
    /// Documented: `.middleOfTheNight` puts Isha and the next Fajr both at the middle of the night, but Adhan measures
    /// each from its own day's night, so Isha can end up seconds after the next Fajr (14 s at Reykjavík).
    @Test("≥ 60° N at the June solstice: every rule gives six ordered times and a positive night",
          arguments: northernSummer, HighLatitudeRule.allCases)
    func highLatitudeJune(place: Place, rule: HighLatitudeRule) throws {
        let settings = CalculationSettings(highLatitudeRule: rule)
        let days = try ["2026-06-20", "2026-06-21", "2026-06-22"].map { try schedule(place, $0, settings: settings) }
        try checkDay(days[1], onDate: [.fajr, .sunrise, .dhuhr, .asr], "\(place.name) \(rule.rawValue)")
        for (today, tomorrow) in zip(days, days.dropFirst()) {
            let gap = tomorrow.fajr!.timeIntervalSince(today.isha!)
            let label: Comment = "\(place.name) \(rule.rawValue): Isha \(today.localDate) to Fajr \(tomorrow.localDate) \(gap) s"
            if rule == .middleOfTheNight {
                #expect(abs(gap) <= 60, label)
            } else {
                #expect(gap > 0, label)
            }
        }
    }

    /// Documented: where the Sun does not rise or set, Adhan has no times at all (the PWA's `computed: false`).
    @Test("Tromsø (69.65° N): no times under the midnight sun or the polar night",
          arguments: ["2026-06-21", "2026-12-21"])
    func polarDayAndNight(date: String) throws {
        let day = try schedule(Place(name: "Tromsø", latitude: 69.65, longitude: 18.96, zone: "Europe/Oslo"), date)
        #expect(PrayerTime.allCases.allSatisfy { day[$0] == nil })
    }

    /// On the first day the Sun rises after the polar night every time exists and the day's frame holds. Where Asr
    /// falls relative to Maghrib is not asserted: the Asr shadow altitude is below the horizon that day and Adhan 1.5.0
    /// puts Asr after Maghrib (documented in spec/prayer-times/README.md).
    @Test("Tromsø on the first sunrise after the polar night: six times, Fajr < sunrise < Dhuhr < Maghrib < Isha")
    func polarNightEdge() throws {
        let day = try schedule(Place(name: "Tromsø", latitude: 69.65, longitude: 18.96, zone: "Europe/Oslo"),
                               "2026-01-15")
        let fajr = try #require(day.fajr), sunrise = try #require(day.sunrise), dhuhr = try #require(day.dhuhr)
        let asr = try #require(day.asr), maghrib = try #require(day.maghrib), isha = try #require(day.isha)
        #expect(fajr < sunrise && sunrise < dhuhr && dhuhr < maghrib && maghrib < isha)
        #expect(asr > dhuhr)
    }

    // MARK: Southern hemisphere

    @Test("Southern hemisphere: complete ordered days at both solstices",
          arguments: [Place(name: "Sydney (33.87° S)", latitude: -33.87, longitude: 151.21, zone: "Australia/Sydney"),
                      Place(name: "Johannesburg (26.2° S)", latitude: -26.2, longitude: 28.05,
                            zone: "Africa/Johannesburg")],
          ["2026-06-21", "2026-12-21"])
    func southernHemisphere(place: Place, date: String) throws {
        try checkDay(try schedule(place, date), "\(place.name) \(date)")
    }

    /// Adhan's own `recommended(for:)` compares the signed latitude with 48, so it would never pick a high-latitude
    /// rule in the south. The port always passes the chosen rule: at 53° S in December twilight does not end and
    /// Fajr is the twilight-angle clamp, sunrise − 18/60 of the night.
    @Test("Punta Arenas (53.16° S) in December: the default rule applies south of −48° too")
    func southernHighLatitude() throws {
        let place = Place(name: "Punta Arenas", latitude: -53.16, longitude: -70.91, zone: "America/Punta_Arenas")
        let today = try schedule(place, "2026-12-21")
        let tomorrow = try schedule(place, "2026-12-22")
        try checkDay(today, onDate: [.fajr, .sunrise, .dhuhr, .asr, .maghrib], "Punta Arenas 2026-12-21")
        let night = tomorrow.sunrise!.timeIntervalSince(today.maghrib!)
        let clamp = today.sunrise!.addingTimeInterval(-night * 18 / 60)
        #expect(abs(today.fajr!.timeIntervalSince(clamp)) <= 2)
        #expect(today.isha! < tomorrow.fajr!)
    }

    // MARK: DST

    /// Each transition day and its neighbours: every time on its own local date, each time about 24 h after the
    /// previous day's (UTC is continuous), and the wall clock moving by exactly the change in UTC offset.
    @Test("DST transitions in both directions",
          arguments: [
              (Place(name: "New York", latitude: 40.71, longitude: -74.01, zone: "America/New_York"), "2026-03-08"),
              (Place(name: "New York", latitude: 40.71, longitude: -74.01, zone: "America/New_York"), "2026-11-01"),
              (Place(name: "Sydney", latitude: -33.87, longitude: 151.21, zone: "Australia/Sydney"), "2026-04-05"),
              (Place(name: "Sydney", latitude: -33.87, longitude: 151.21, zone: "Australia/Sydney"), "2026-10-04"),
              (Place(name: "London", latitude: 51.51, longitude: -0.13, zone: "Europe/London"), "2026-03-29"),
              (Place(name: "London", latitude: 51.51, longitude: -0.13, zone: "Europe/London"), "2026-10-25"),
          ])
    func dstTransition(place: Place, date: String) throws {
        let zone = try #require(TimeZone(identifier: place.zone))
        let dates = [-1, 0, 1].map { PrayerTimesTestCalendar.localDate(date, adding: $0) }
        let days = try dates.map { try schedule(place, $0) }
        for day in days {
            try checkDay(day, "\(place.name) \(day.localDate)")
        }
        let offsetChange = Double(zone.secondsFromGMT(for: days[1].dhuhr!) - zone.secondsFromGMT(for: days[0].dhuhr!))
        #expect(offsetChange != 0, "\(date) is not a transition day in \(place.zone)")
        for (before, after) in zip(days, days.dropFirst()) {
            for time in PrayerTime.allCases {
                let step = after[time]!.timeIntervalSince(before[time]!)
                #expect(abs(step - 86_400) <= 5 * 60, "\(place.name) \(time.rawValue) \(after.localDate): \(step) s")
            }
        }
        let wallClockStep = PrayerTimesTestCalendar.wallClockHours(of: days[1].dhuhr!, in: zone)
            - PrayerTimesTestCalendar.wallClockHours(of: days[0].dhuhr!, in: zone)
        #expect(abs(wallClockStep * 3600 - offsetChange) <= 5 * 60, "Dhuhr wall clock moved \(wallClockStep) h")
    }

    // MARK: Dateline

    /// Kiritimati (UTC+14 at 157° W) and Apia (UTC+13 at 172° W): the civil day's transit is on the previous UTC date,
    /// which the adapter must hand to Adhan (spec/prayer-times/README.md). Pago Pago (UTC−11, 171° W) needs no shift.
    @Test("Dateline zones: times on the requested local date, noon near 12:00",
          arguments: [Place(name: "Kiritimati", latitude: 1.87, longitude: -157.47, zone: "Pacific/Kiritimati"),
                      Place(name: "Pago Pago", latitude: -14.28, longitude: -170.7, zone: "Pacific/Pago_Pago"),
                      Place(name: "Apia", latitude: -13.83, longitude: -171.76, zone: "Pacific/Apia")],
          ["2026-01-01", "2026-06-21"])
    func dateline(place: Place, date: String) throws {
        let day = try schedule(place, date)
        try checkDay(day, "\(place.name) \(date)")
        let noon = PrayerTimesTestCalendar.wallClockHours(of: day.dhuhr!, in: day.zone)
        #expect((11.5...13.5).contains(noon), "\(place.name) \(date): Dhuhr at \(noon) h")
        let next = try schedule(place, PrayerTimesTestCalendar.localDate(date, adding: 1))
        #expect(abs(next.dhuhr!.timeIntervalSince(day.dhuhr!) - 86_400) <= 60)
    }

    // MARK: Input

    @Test("Rejects dates that are not calendar days and coordinates out of range")
    func invalidInput() throws {
        let zone = TimeZone(identifier: "Asia/Riyadh")!
        let mecca = GeoCoordinates(latitude: 21.42, longitude: 39.83)
        for date in ["2026-02-30", "2026-1-15", "15-01-2026"] {
            #expect(throws: PrayerTimesError.invalidLocalDate(date)) {
                try port.schedule(on: date, at: mecca, in: zone, settings: CalculationSettings())
            }
        }
        for coordinates in [GeoCoordinates(latitude: 91, longitude: 0), GeoCoordinates(latitude: 0, longitude: -181),
                            GeoCoordinates(latitude: .nan, longitude: 0)] {
            #expect(throws: PrayerTimesError.self) {
                try port.schedule(on: "2026-01-15", at: coordinates, in: zone, settings: CalculationSettings())
            }
        }
    }
}
