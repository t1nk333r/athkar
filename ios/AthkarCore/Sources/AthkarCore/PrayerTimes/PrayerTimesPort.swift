import Foundation

/// A position in degrees: latitude −90…90, longitude −180…180 (east positive).
public struct GeoCoordinates: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// The six daily times, in order. `ReminderRule.PrayerKey` is the subset a reminder can be relative to (no sunrise);
/// the raw values match.
public enum PrayerTime: String, Codable, Sendable, CaseIterable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha
}

/// One civil day's times as UTC instants, with the zone whose `localDate` they belong to.
/// A time is `nil` when it cannot be computed for that place and day (polar day or night).
public struct PrayerSchedule: Equatable, Sendable {
    /// `YYYY-MM-DD` in `zone`.
    public let localDate: String
    public let zone: TimeZone
    public let fajr: Date?
    public let sunrise: Date?
    public let dhuhr: Date?
    public let asr: Date?
    public let maghrib: Date?
    public let isha: Date?

    public init(localDate: String, zone: TimeZone, fajr: Date?, sunrise: Date?, dhuhr: Date?, asr: Date?,
                maghrib: Date?, isha: Date?) {
        self.localDate = localDate
        self.zone = zone
        self.fajr = fajr
        self.sunrise = sunrise
        self.dhuhr = dhuhr
        self.asr = asr
        self.maghrib = maghrib
        self.isha = isha
    }

    public subscript(time: PrayerTime) -> Date? {
        switch time {
        case .fajr: fajr
        case .sunrise: sunrise
        case .dhuhr: dhuhr
        case .asr: asr
        case .maghrib: maghrib
        case .isha: isha
        }
    }
}

public enum PrayerTimesError: Error, Equatable, Sendable {
    /// Not a `YYYY-MM-DD` calendar date.
    case invalidLocalDate(String)
    /// Latitude outside −90…90, longitude outside −180…180, or not finite.
    case invalidCoordinates(GeoCoordinates)
}

/// The one way the app obtains prayer times (NATIVE_APP_PLAN.md §7.1). Views and the reminder planner depend on
/// this protocol, never on the calculation library.
public protocol PrayerTimesPort: Sendable {
    /// The times of the civil day `localDate` (`YYYY-MM-DD`) in `zone`, at `coordinates`.
    func schedule(on localDate: String, at coordinates: GeoCoordinates, in zone: TimeZone,
                  settings: CalculationSettings) throws(PrayerTimesError) -> PrayerSchedule
}
