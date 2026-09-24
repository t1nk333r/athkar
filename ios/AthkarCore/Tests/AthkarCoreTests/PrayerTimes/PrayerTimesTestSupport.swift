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

enum PrayerTimesTestCalendar {
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
