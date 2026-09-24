import AthkarCore
import Foundation

/// `spec/prayer-times/vectors.json`: the PWA's `prayerTimesForDate`/`solarDay` output.
struct PrayerTimesVectors: Decodable {
    let tolerance: Tolerance
    let vectors: [Vector]

    struct Tolerance: Decodable {
        let seconds: Double
    }

    struct Vector: Decodable, CustomStringConvertible {
        let location: String
        let latitude: Double
        let longitude: Double
        let timeZone: String
        let date: String
        let method: CalculationMethod
        let fajrAngle: Double
        let asrSchool: AsrSchool
        let expected: Expected

        var description: String { "\(location) \(date) \(method.rawValue) \(asrSchool.rawValue)" }
        var coordinates: GeoCoordinates { GeoCoordinates(latitude: latitude, longitude: longitude) }
    }

    struct Expected: Decodable {
        let computed: Bool
        let fajr: String?
        let sunrise: String?
        let asr: String?
        let sunset: String?
    }

    /// `<repo>/spec/prayer-times/vectors.json`, found from this file's location
    /// (`<repo>/ios/AthkarCore/Tests/AthkarCoreTests/PrayerTimes/`).
    static func load() throws -> PrayerTimesVectors {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appending(path: "spec/prayer-times/vectors.json"))
        return try JSONDecoder().decode(PrayerTimesVectors.self, from: data)
    }
}

/// An independent solar model for checking the Adhan presets: the NOAA formulas the PWA uses (`solarTerms`), with
/// the Sun's position re-evaluated at the event itself so they are comparable with Adhan's (spec/prayer-times/README.md,
/// P1 classes). Times are for the solar day around noon of a UTC calendar date, so use it where the local date and
/// the UTC date of every event agree.
enum SolarReference {
    /// When the Sun's centre is at `altitude` degrees before (`afterNoon: false`) or after solar noon; `nil` if it
    /// never gets there.
    static func instant(altitude: Double, afterNoon: Bool, on utcDate: String, latitude: Double,
                        longitude: Double) -> Date? {
        let midnight = PrayerTimesTestCalendar.utcMidnight(utcDate)
        let julianDay = midnight.timeIntervalSince1970 / 86_400 + 2_440_587.5
        var minutes = 720 - 4 * longitude
        for _ in 0..<4 {
            let (declination, equationOfTime) = terms(julianDay + minutes / 1440)
            let noon = 720 - 4 * longitude - equationOfTime
            let cosine = (sin(radians(altitude)) - sin(radians(latitude)) * sin(radians(declination)))
                / (cos(radians(latitude)) * cos(radians(declination)))
            guard abs(cosine) <= 1 else { return nil }
            let hourAngle = degrees(acos(cosine)) * 4
            minutes = afterNoon ? noon + hourAngle : noon - hourAngle
        }
        return midnight.addingTimeInterval(minutes * 60)
    }

    /// Solar noon.
    static func transit(on utcDate: String, longitude: Double) -> Date {
        let midnight = PrayerTimesTestCalendar.utcMidnight(utcDate)
        let julianDay = midnight.timeIntervalSince1970 / 86_400 + 2_440_587.5
        var minutes = 720 - 4 * longitude
        for _ in 0..<3 {
            minutes = 720 - 4 * longitude - terms(julianDay + minutes / 1440).equationOfTime
        }
        return midnight.addingTimeInterval(minutes * 60)
    }

    /// The PWA's `solarTerms`: declination (degrees) and equation of time (minutes) at a Julian day.
    private static func terms(_ julianDay: Double) -> (declination: Double, equationOfTime: Double) {
        let century = (julianDay - 2_451_545) / 36_525
        let meanLongitude = (280.46646 + century * (36000.76983 + century * 0.0003032))
            .truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + century * (35999.05029 - 0.0001537 * century)
        let eccentricity = 0.016708634 - century * (0.000042037 + 0.0000001267 * century)
        let center = sin(radians(meanAnomaly)) * (1.914602 - century * (0.004817 + 0.000014 * century))
            + sin(radians(2 * meanAnomaly)) * (0.019993 - 0.000101 * century)
            + sin(radians(3 * meanAnomaly)) * 0.000289
        let node = radians(125.04 - 1934.136 * century)
        let apparentLongitude = meanLongitude + center - 0.00569 - 0.00478 * sin(node)
        let meanObliquity = 23 + (26 + (21.448 - century * (46.815 + century * (0.00059 - century * 0.001813))) / 60)
            / 60
        let obliquity = meanObliquity + 0.00256 * cos(node)
        let declination = degrees(asin(sin(radians(obliquity)) * sin(radians(apparentLongitude))))
        let y = pow(tan(radians(obliquity / 2)), 2)
        let l0 = radians(meanLongitude), m = radians(meanAnomaly)
        let equationOfTime = 4 * degrees(y * sin(2 * l0) - 2 * eccentricity * sin(m)
            + 4 * eccentricity * y * sin(m) * cos(2 * l0) - 0.5 * y * y * sin(4 * l0)
            - 1.25 * eccentricity * eccentricity * sin(2 * m))
        return (declination, equationOfTime)
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}

enum PrayerTimesTestCalendar {
    /// 00:00 UTC of `YYYY-MM-DD`.
    static func utcMidnight(_ date: String) -> Date {
        utc.date(from: components(date))!
    }

    /// `YYYY-MM-DD` plus `days`.
    static func localDate(_ date: String, adding days: Int) -> String {
        let day = utc.date(from: components(date))!
        return key(utc.date(byAdding: .day, value: days, to: day)!, in: utc)
    }

    /// The civil date of `instant` in `zone`, `YYYY-MM-DD`.
    static func localDate(of instant: Date, in zone: TimeZone) -> String {
        var calendar = utc
        calendar.timeZone = zone
        return key(instant, in: calendar)
    }

    /// Hours and minutes of `instant` on the wall clock of `zone`, as fractional hours.
    static func wallClockHours(of instant: Date, in zone: TimeZone) -> Double {
        var calendar = utc
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: instant)
        return Double(parts.hour!) + Double(parts.minute!) / 60 + Double(parts.second!) / 3600
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func components(_ date: String) -> DateComponents {
        let parts = date.split(separator: "-").map { Int($0)! }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    private static func key(_ instant: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
