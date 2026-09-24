import AthkarCore
import Foundation
import Testing

/// What each calculation method must produce beyond P1's Fajr/sunrise/Asr/sunset: Isha, Maghrib, the presets' minute
/// offsets and rounding (the "Parameters per method" table in spec/prayer-times/README.md), and the user's own
/// adjustments. Angles are checked against `SolarReference`, an independent solar model that agrees with Adhan to
/// about 2 s at these places (10 s allowed). Offsets are checked exactly against the Umm al-Qura schedule, whose
/// sunrise, Dhuhr, Asr and Maghrib carry no offset and no rounding.
@Suite("Prayer times: method presets and adjustments")
struct PrayerTimesMethodTests {
    enum Twilight: Sendable {
        /// The Sun this many degrees below the horizon.
        case angle(Double)
        /// Minutes after Maghrib.
        case interval(Int)
        /// Moonsighting Committee: the 18° time, but no earlier (Fajr) or later (Isha) than its seasonal twilight
        /// (`moonsightingMinutes`, shafaq `general`).
        case seasonal
    }

    struct Preset: Sendable, CustomTestStringConvertible {
        let method: CalculationMethod
        let fajr: Twilight
        let isha: Twilight
        /// Maghrib at this depression instead of sunset.
        var maghribAngle: Double?
        /// Minutes the preset adds to sunrise, Dhuhr, Asr and Maghrib.
        var offsets = PrayerAdjustments()
        var roundsUp = false

        var testDescription: String { method.rawValue }
    }

    static let presets = [
        Preset(method: .mwl, fajr: .angle(18), isha: .angle(17), offsets: PrayerAdjustments(dhuhr: 1)),
        Preset(method: .ummAlQura, fajr: .angle(18.5), isha: .interval(90)),
        Preset(method: .egyptian, fajr: .angle(19.5), isha: .angle(17.5), offsets: PrayerAdjustments(dhuhr: 1)),
        Preset(method: .karachi, fajr: .angle(18), isha: .angle(18), offsets: PrayerAdjustments(dhuhr: 1)),
        Preset(method: .northAmerica, fajr: .angle(15), isha: .angle(15), offsets: PrayerAdjustments(dhuhr: 1)),
        Preset(method: .dubai, fajr: .angle(18.2), isha: .angle(18.2),
               offsets: PrayerAdjustments(sunrise: -3, dhuhr: 3, asr: 3, maghrib: 3)),
        Preset(method: .moonsightingCommittee, fajr: .seasonal, isha: .seasonal,
               offsets: PrayerAdjustments(dhuhr: 5, maghrib: 3)),
        Preset(method: .kuwait, fajr: .angle(18), isha: .angle(17.5)),
        Preset(method: .qatar, fajr: .angle(18), isha: .interval(90)),
        Preset(method: .singapore, fajr: .angle(20), isha: .angle(18), offsets: PrayerAdjustments(dhuhr: 1),
               roundsUp: true),
        Preset(method: .tehran, fajr: .angle(17.7), isha: .angle(14), maghribAngle: 4.5),
        Preset(method: .turkey, fajr: .angle(18), isha: .angle(17),
               offsets: PrayerAdjustments(sunrise: -7, dhuhr: 5, asr: 4, maghrib: 7)),
    ]

    struct Place: Sendable, CustomTestStringConvertible {
        let name: String
        let coordinates: GeoCoordinates
        let zone: String

        var testDescription: String { name }
    }

    /// Every event of these days falls on the same UTC date as its local date, as `SolarReference` needs.
    static let places = [
        Place(name: "Mecca", coordinates: GeoCoordinates(latitude: 21.42, longitude: 39.83), zone: "Asia/Riyadh"),
        Place(name: "Istanbul", coordinates: GeoCoordinates(latitude: 41.01, longitude: 28.98),
              zone: "Europe/Istanbul"),
    ]
    static let date = "2026-01-15"

    private let port = AdhanPrayerTimes()

    private func schedule(_ place: Place, _ settings: CalculationSettings) throws -> PrayerSchedule {
        try port.schedule(on: Self.date, at: place.coordinates, in: try #require(TimeZone(identifier: place.zone)),
                          settings: settings)
    }

    private func reference(_ place: Place, depression: Double, afterNoon: Bool) throws -> Date {
        try #require(SolarReference.instant(altitude: -depression, afterNoon: afterNoon, on: Self.date,
                                            latitude: place.coordinates.latitude,
                                            longitude: place.coordinates.longitude))
    }

    @Test("The offset-free baseline (Umm al-Qura) matches the reference sunrise, noon and sunset",
          arguments: places)
    func baseline(place: Place) throws {
        let bare = try schedule(place, CalculationSettings(method: .ummAlQura))
        let noon = SolarReference.transit(on: Self.date, longitude: place.coordinates.longitude)
        #expect(abs(bare.dhuhr!.timeIntervalSince(noon)) <= 10)
        let sunrise = try reference(place, depression: 0.833, afterNoon: false)
        let sunset = try reference(place, depression: 0.833, afterNoon: true)
        #expect(abs(bare.sunrise!.timeIntervalSince(sunrise)) <= 10)
        #expect(abs(bare.maghrib!.timeIntervalSince(sunset)) <= 10)
    }

    @Test("Each preset's Fajr, Isha, Maghrib, offsets and rounding", arguments: presets, places)
    func preset(_ preset: Preset, place: Place) throws {
        let day = try schedule(place, CalculationSettings(method: preset.method))
        let bare = try schedule(place, CalculationSettings(method: .ummAlQura))
        let label = "\(preset.method.rawValue) at \(place.name)"
        // Whole-minute rounding adds up to a minute on top of the model difference.
        let slack: TimeInterval = preset.roundsUp ? 60 : 0

        // Minute offsets, exact against the offset-free baseline (rounded up to the minute where the preset does).
        let offsets: [(PrayerTime, Int)] = [(.sunrise, preset.offsets.sunrise), (.dhuhr, preset.offsets.dhuhr),
                                            (.asr, preset.offsets.asr)]
            + (preset.maghribAngle == nil ? [(.maghrib, preset.offsets.maghrib)] : [])
        for (time, minutes) in offsets {
            let shift = day[time]!.timeIntervalSince(bare[time]!) - Double(minutes * 60)
            #expect((0...slack).contains(shift) && (preset.roundsUp ? shift < 60 : true),
                    "\(label): \(time.rawValue) is \(shift) s off the bare time + \(minutes) min")
        }
        if let angle = preset.maghribAngle {
            let expected = try reference(place, depression: angle, afterNoon: true)
            #expect(abs(day.maghrib!.timeIntervalSince(expected)) <= 10, "\(label): Maghrib at \(angle)°")
        }

        switch preset.fajr {
        case .angle(let angle):
            let expected = try reference(place, depression: angle, afterNoon: false)
            #expect(abs(day.fajr!.timeIntervalSince(expected)) <= 10 + slack, "\(label): Fajr at \(angle)°")
        case .seasonal:
            let angleFajr = try reference(place, depression: 18, afterNoon: false)
            let sunrise = try reference(place, depression: 0.833, afterNoon: false)
            let minutes = Self.moonsightingMinutes(latitude: place.coordinates.latitude, morning: true)
            let expected = max(angleFajr, sunrise.addingTimeInterval(-(minutes * 60).rounded()))
            #expect(abs(day.fajr!.timeIntervalSince(expected)) <= 10, "\(label): seasonal Fajr")
        case .interval:
            Issue.record("\(label): no preset has an interval Fajr")
        }
        switch preset.isha {
        case .angle(let angle):
            let expected = try reference(place, depression: angle, afterNoon: true)
            #expect(abs(day.isha!.timeIntervalSince(expected)) <= 10 + slack, "\(label): Isha at \(angle)°")
        case .interval(let minutes):
            #expect(day.isha!.timeIntervalSince(day.maghrib!) == Double(minutes * 60), "\(label): Isha interval")
        case .seasonal:
            let angleIsha = try reference(place, depression: 18, afterNoon: true)
            let sunset = try reference(place, depression: 0.833, afterNoon: true)
            let minutes = Self.moonsightingMinutes(latitude: place.coordinates.latitude, morning: false)
            let expected = min(angleIsha, sunset.addingTimeInterval((minutes * 60).rounded()))
            #expect(abs(day.isha!.timeIntervalSince(expected)) <= 10, "\(label): seasonal Isha (shafaq general)")
        }

        if preset.roundsUp {
            for time in PrayerTime.allCases {
                #expect(day[time]!.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0,
                        "\(label): \(time.rawValue) not on a whole minute")
            }
        }
    }

    /// Khalid Shaukat's seasonal twilight for the Moonsighting Committee method, in minutes before sunrise or after
    /// sunset, with shafaq `general` (the preset's). Interpolated through four seasonal values that grow with
    /// latitude, for `date` (2026-01-15): 25 days after the December solstice (day of year 15 + 10) in the north.
    static func moonsightingMinutes(latitude: Double, morning: Bool) -> Double {
        let l = abs(latitude) / 55
        let (a, b, c, d) = morning
            ? (75 + 28.65 * l, 75 + 19.44 * l, 75 + 32.74 * l, 75 + 48.10 * l)
            : (75 + 25.60 * l, 75 + 2.050 * l, 75 - 9.210 * l, 75 + 6.140 * l)
        let days = 25.0
        switch days {
        case ..<91: return a + (b - a) / 91 * days
        case ..<137: return b + (c - b) / 46 * (days - 91)
        case ..<183: return c + (d - c) / 46 * (days - 137)
        case ..<229: return d + (c - d) / 46 * (days - 183)
        case ..<275: return c + (b - c) / 46 * (days - 229)
        default: return b + (a - b) / 91 * (days - 275)
        }
    }

    @Test("A user adjustment moves exactly its own time by its minutes", arguments: PrayerTime.allCases, [7, -3])
    func adjustment(time: PrayerTime, minutes: Int) throws {
        var adjustments = PrayerAdjustments()
        switch time {
        case .fajr: adjustments.fajr = minutes
        case .sunrise: adjustments.sunrise = minutes
        case .dhuhr: adjustments.dhuhr = minutes
        case .asr: adjustments.asr = minutes
        case .maghrib: adjustments.maghrib = minutes
        case .isha: adjustments.isha = minutes
        }
        let place = Self.places[0]
        let plain = try schedule(place, CalculationSettings())
        let adjusted = try schedule(place, CalculationSettings(adjustments: adjustments))
        for other in PrayerTime.allCases {
            let shift = adjusted[other]!.timeIntervalSince(plain[other]!)
            #expect(shift == (other == time ? Double(minutes * 60) : 0), "\(other.rawValue) moved \(shift) s")
        }
    }
}
