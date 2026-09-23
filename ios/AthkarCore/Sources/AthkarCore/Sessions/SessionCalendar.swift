import Foundation

/// Local-date and instant formatting exactly as the PWA does it with JavaScript `Date`.
///
/// Instants are reduced to whole milliseconds first (JavaScript time values are integral milliseconds).
public enum SessionCalendar {
    /// `localDateKey(date)`: the civil date of `instant` in `timeZone`, `YYYY-MM-DD`.
    public static func localDate(of instant: Date, in timeZone: TimeZone) -> String {
        let offset = Int64(timeZone.secondsFromGMT(for: instant)) * 1000
        let day = CivilDay(epochDay: floorDivide(milliseconds(of: instant) + offset, dayMilliseconds))
        return day.key
    }

    /// `recentDates(days)`: the local dates of `now` and the `days - 1` days before it, newest first.
    public static func recentDates(_ days: Int, endingAt now: Date, in timeZone: TimeZone) -> [String] {
        let offset = Int64(timeZone.secondsFromGMT(for: now)) * 1000
        let today = floorDivide(milliseconds(of: now) + offset, dayMilliseconds)
        return (0..<max(0, days)).map { CivilDay(epochDay: today - Int64($0)).key }
    }

    /// `date.toISOString()`: `YYYY-MM-DDTHH:mm:ss.sssZ` in UTC (expanded `±YYYYYY` years outside 0…9999).
    public static func isoString(_ instant: Date) -> String {
        let milliseconds = milliseconds(of: instant)
        let epochDay = floorDivide(milliseconds, dayMilliseconds)
        let day = CivilDay(epochDay: epochDay)
        let inDay = milliseconds - epochDay * dayMilliseconds
        let year = (0...9999).contains(day.year)
            ? pad(day.year, 4)
            : (day.year < 0 ? "-" : "+") + pad(abs(day.year), 6)
        return "\(year)-\(pad(day.month, 2))-\(pad(day.day, 2))T"
            + "\(pad(inDay / 3_600_000, 2)):\(pad(inDay / 60_000 % 60, 2)):\(pad(inDay / 1000 % 60, 2))"
            + ".\(pad(inDay % 1000, 3))Z"
    }

    // MARK: - Private

    private static let dayMilliseconds: Int64 = 86_400_000

    /// Whole milliseconds since the epoch, truncated like `Date.now()`. Values within a microsecond of a
    /// whole millisecond snap to it, so a `Date` built from integral milliseconds never loses one to
    /// floating-point error.
    private static func milliseconds(of instant: Date) -> Int64 {
        let scaled = instant.timeIntervalSince1970 * 1000
        let nearest = scaled.rounded()
        return Int64(abs(scaled - nearest) < 0.001 ? nearest : scaled.rounded(.down))
    }

    private static func floorDivide(_ value: Int64, _ divisor: Int64) -> Int64 {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }

    private static func pad<Number: BinaryInteger>(_ value: Number, _ width: Int) -> String {
        let digits = String(value)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }

    /// Proleptic Gregorian civil date from days since 1970-01-01 (H. Hinnant's `civil_from_days`).
    private struct CivilDay {
        let year: Int64
        let month: Int64
        let day: Int64

        init(epochDay: Int64) {
            let shifted = epochDay + 719_468
            let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
            let dayOfEra = shifted - era * 146_097
            let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
            let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
            let monthIndex = (5 * dayOfYear + 2) / 153
            day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
            month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
            year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        }

        /// `localDateKey` pads month and day but not the year (`String(date.getFullYear())`).
        var key: String {
            "\(year)-\(SessionCalendar.pad(month, 2))-\(SessionCalendar.pad(day, 2))"
        }
    }
}
