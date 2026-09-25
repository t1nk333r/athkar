import AthkarCore
import Foundation
import Testing

/// P1 (NATIVE_APP_PLAN.md §7.2): the production adapter against the PWA's `prayerTimesForDate`/`solarDay` for Fajr,
/// sunrise, Asr and sunset over all of `spec/prayer-times/vectors.json`, with the default high-latitude rule.
/// A time outside the file's tolerance passes only if one of `Exception`'s classes explains it and it stays within
/// that class's bound. Membership is decided by mechanism, not by place: apart from the grazing-sun day, Adhan's
/// time must agree with `SolarReference` (an independent model with the mechanism Adhan uses) to within
/// `referenceAgreement`, so the difference is the PWA's model, not a fault in the adapter. Classes, counts and
/// maxima: spec/prayer-times/README.md.
@Suite("Prayer times P1: legacy parity")
struct PrayerTimesParityTests {
    enum Field: String, CaseIterable {
        case fajr, sunrise, asr, sunset
    }

    /// Why a vector may sit outside tolerance. Each class is written up in spec/prayer-times/README.md.
    enum Exception: String, CaseIterable {
        /// The Sun's noon or midnight altitude is within `grazingMargin` of the sunrise altitude (Tromsø 2026-01-15:
        /// the first sunrise after the polar night). Sunrise, sunset and Fajr are ill-conditioned there: both
        /// models' approximations move them by minutes. Asr, when the noon Sun is that low, is not a usable time at
        /// all; it is checked against the Dhuhr–Maghrib window instead of a bound.
        case grazingSun = "grazing-sun"
        /// Fajr where a night-fraction clamp decides it: the PWA takes the night from the previous day's sunset to
        /// today's sunrise, Adhan's `.twilightAngle` from today's sunset to tomorrow's sunrise. Proven per vector:
        /// the PWA's rule applied to Adhan's own angle Fajr, sunrise and previous sunset lands within tolerance.
        case clampNightSpan = "clamp-night-span"
        /// Fajr, sunrise, sunset: the PWA evaluates every event with the Sun's declination at local solar noon,
        /// Adhan (like `SolarReference`) with the Sun's position at the event itself. Where the Sun crosses the event
        /// altitude at a shallow angle, that 0.1–0.2° moves the event by minutes.
        case solarPositionAtEvent = "solar-position-at-event"
        /// Asr: as above, and Adhan (like `SolarReference.asr`) takes the shadow angle from the declination at
        /// 0h UTC of the date where the PWA takes it at local solar noon.
        case asrShadowDeclination = "asr-shadow-declination"

        /// The largest difference the class accounts for (grazing Asr: see above).
        var bound: TimeInterval {
            switch self {
            case .grazingSun: 20 * 60
            case .clampNightSpan: 6 * 60
            case .solarPositionAtEvent: 3 * 60
            case .asrShadowDeclination: 7 * 60
            }
        }
    }

    /// Degrees between the Sun's noon or midnight altitude and the sunrise altitude (−0.833°) below which a day is
    /// grazing. The closest out-of-tolerance time outside it, in this grid and in the external review's 30 places, is
    /// 5.6° away (Nuuk 2026-01-15 Asr).
    static let grazingMargin = 2.0

    /// How closely Adhan must agree with `SolarReference` for a class to apply. Measured over every vector except the
    /// grazing-sun day: Fajr 8.0 s, sunrise 2.8 s, sunset 4.2 s, Asr 29.0 s. These are this grid's maxima; above
    /// about 62° they do not hold (spec/prayer-times/README.md).
    static func referenceAgreement(_ field: Field) -> TimeInterval {
        field == .asr ? 30 : 10
    }

    private let port = AdhanPrayerTimes()

    @Test("All vectors within tolerance or explained")
    func legacyParity() throws {
        let file = try PrayerTimesVectors.load()
        #expect(file.vectors.count == 3600)
        var inTolerance: [Field: (count: Int, max: TimeInterval)] = [:]
        var explained: [Exception: (count: Int, max: TimeInterval)] = [:]
        var notComputed = 0, grazingAsr = 0

        for vector in file.vectors {
            let zone = try #require(TimeZone(identifier: vector.timeZone))
            let schedule = try port.schedule(on: vector.date, at: vector.coordinates, in: zone,
                                             settings: CalculationSettings(method: vector.method,
                                                                           asrSchool: vector.asrSchool))
            guard vector.expected.computed else {
                // The PWA returned null (no sunrise: Tromsø at the solstices); Adhan has no times either.
                #expect(PrayerTime.allCases.allSatisfy { schedule[$0] == nil }, "\(vector): Adhan computed times")
                notComputed += 1
                continue
            }
            // Maghrib is sunset for the PWA's five methods: none has a Maghrib angle or offset.
            let actual: [Field: Date?] = [.fajr: schedule.fajr, .sunrise: schedule.sunrise, .asr: schedule.asr,
                                          .sunset: schedule.maghrib]
            let expected: [Field: String?] = [.fajr: vector.expected.fajr, .sunrise: vector.expected.sunrise,
                                              .asr: vector.expected.asr, .sunset: vector.expected.sunset]
            for field in Field.allCases {
                let expectedText = try #require(expected[field] ?? nil, "\(vector) \(field): PWA value missing")
                guard let actualTime = actual[field] ?? nil else {
                    Issue.record("\(vector) \(field): Adhan computed no time, PWA \(expectedText)")
                    continue
                }
                let delta = actualTime.timeIntervalSince(try SessionsFixtures.instant(expectedText))
                if abs(delta) <= file.tolerance.seconds {
                    inTolerance[field, default: (0, 0)].count += 1
                    inTolerance[field]!.max = max(inTolerance[field]!.max, abs(delta))
                    continue
                }
                let description = "\(vector) \(field): Adhan \(SessionCalendar.isoString(actualTime)), "
                    + "PWA \(expectedText), Δ \(Int(delta.rounded())) s"
                let (exception, reason) = try explanation(for: field, of: vector, actual: actualTime,
                                                          schedule: schedule, zone: zone,
                                                          tolerance: file.tolerance.seconds)
                guard let exception else {
                    Issue.record("\(description): outside tolerance and no explanation class applies (\(reason))")
                    continue
                }
                explained[exception, default: (0, 0)].count += 1
                if exception == .grazingSun && field == .asr {
                    let dhuhr = try #require(schedule.dhuhr), maghrib = try #require(schedule.maghrib)
                    #expect(dhuhr < actualTime && actualTime <= maghrib,
                            "\(description): grazing Asr outside the Dhuhr–Maghrib window")
                    grazingAsr += 1
                    continue
                }
                #expect(abs(delta) <= exception.bound,
                        "\(description): beyond the \(exception.rawValue) bound of \(Int(exception.bound)) s")
                explained[exception]!.max = max(explained[exception]!.max, abs(delta))
            }
        }

        var report = ["P1: \(file.vectors.count) vectors, \(notComputed) not computed by either side"]
        for field in Field.allCases {
            let entry = inTolerance[field] ?? (0, 0)
            report.append("  \(field.rawValue): \(entry.count) within tolerance, max \(Int(entry.max.rounded())) s")
        }
        for exception in Exception.allCases {
            let entry = explained[exception] ?? (0, 0)
            let asr = exception == .grazingSun ? " (\(grazingAsr) of them Asr, in the window)" : ""
            report.append("  \(exception.rawValue): \(entry.count)\(asr), max \(Int(entry.max.rounded())) s")
        }
        print(report.joined(separator: "\n"))
    }

    /// The class whose condition holds for this out-of-tolerance time, or why none does.
    private func explanation(for field: Field, of vector: PrayerTimesVectors.Vector, actual: Date,
                             schedule: PrayerSchedule, zone: TimeZone,
                             tolerance: TimeInterval) throws -> (Exception?, String) {
        let altitudes = SolarReference.extremeAltitudes(on: vector.date, latitude: vector.latitude,
                                                        longitude: vector.longitude)
        let noonMargin = altitudes.noon + 0.833, midnightMargin = -0.833 - altitudes.midnight
        // Asr depends on how high the noon Sun gets; the other three can also graze at midnight.
        if (field == .asr ? noonMargin : min(noonMargin, midnightMargin)) < Self.grazingMargin {
            return (.grazingSun, "")
        }
        guard let reference = reference(field, of: vector) else { return (nil, "the reference has no time") }
        let disagreement = actual.timeIntervalSince(reference)
        guard abs(disagreement) <= Self.referenceAgreement(field) else {
            return (nil, "Adhan is \(Int(disagreement.rounded())) s off the reference")
        }
        switch field {
        case .sunrise, .sunset: return (.solarPositionAtEvent, "")
        case .asr: return (.asrShadowDeclination, "")
        case .fajr:
            let pwaFajr = try SessionsFixtures.instant(vector.expected.fajr!)
            if let fajr = try fajrByPWARule(vector, schedule: schedule, zone: zone),
               abs(fajr.timeIntervalSince(pwaFajr)) <= tolerance {
                return (.clampNightSpan, "")
            }
            return (.solarPositionAtEvent, "")
        }
    }

    /// `SolarReference`'s value for the field. Fajr follows the default `.twilightAngle` rule: the angle Fajr, but no
    /// earlier than sunrise − fajrAngle/60 of the night from today's sunset to tomorrow's sunrise.
    private func reference(_ field: Field, of vector: PrayerTimesVectors.Vector) -> Date? {
        let (date, latitude, longitude) = (vector.date, vector.latitude, vector.longitude)
        func horizon(_ date: String, afterNoon: Bool) -> Date? {
            SolarReference.instant(altitude: -0.833, afterNoon: afterNoon, on: date, latitude: latitude,
                                   longitude: longitude)
        }
        switch field {
        case .sunrise: return horizon(date, afterNoon: false)
        case .sunset: return horizon(date, afterNoon: true)
        case .asr:
            return SolarReference.asr(shadowFactor: vector.asrSchool == .hanafi ? 2 : 1, on: date,
                                      latitude: latitude, longitude: longitude)
        case .fajr:
            guard let sunrise = horizon(date, afterNoon: false), let sunset = horizon(date, afterNoon: true),
                  let nextSunrise = horizon(PrayerTimesTestCalendar.localDate(date, adding: 1), afterNoon: false)
            else { return nil }
            let clamp = sunrise.addingTimeInterval(-nextSunrise.timeIntervalSince(sunset) * vector.fajrAngle / 60)
            let angle = SolarReference.instant(altitude: -vector.fajrAngle, afterNoon: false, on: date,
                                               latitude: latitude, longitude: longitude)
            return max(angle ?? clamp, clamp)
        }
    }

    /// The PWA's Fajr rule on Adhan's astronomy: `max(angle Fajr, sunrise − (sunrise − previous sunset) × angle/60)`,
    /// or the angle Fajr alone when there was no previous sunset. Adhan's angle Fajr is read with
    /// `.middleOfTheNight`: its clamp (half the night) is always earlier than the PWA's (at most 19.5/60 of it), so
    /// where it applies the angle Fajr is earlier still and `max` picks the PWA clamp either way.
    private func fajrByPWARule(_ vector: PrayerTimesVectors.Vector, schedule: PrayerSchedule,
                               zone: TimeZone) throws -> Date? {
        let settings = CalculationSettings(method: vector.method, asrSchool: vector.asrSchool,
                                           highLatitudeRule: .middleOfTheNight)
        guard let angleFajr = try port.schedule(on: vector.date, at: vector.coordinates, in: zone,
                                                settings: settings).fajr,
              let sunrise = schedule.sunrise
        else { return nil }
        let yesterday = PrayerTimesTestCalendar.localDate(vector.date, adding: -1)
        guard let previousSunset = try port.schedule(on: yesterday, at: vector.coordinates, in: zone,
                                                     settings: settings).maghrib
        else { return angleFajr }
        let night = sunrise.timeIntervalSince(previousSunset)
        return max(angleFajr, sunrise.addingTimeInterval(-night * vector.fajrAngle / 60))
    }
}
