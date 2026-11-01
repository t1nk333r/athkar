import Foundation

/// Civil-date arithmetic on `YYYY-MM-DD` keys (spec/schema.md, "Local dates"), in the proleptic Gregorian calendar
/// and independent of any zone: adding a day is a calendar day, never 24 hours.
extension LocalDate {
    /// Days since 1970-01-01, or `nil` unless `date` is exactly `YYYY-MM-DD` naming a real calendar day.
    public static func epochDay(_ date: String) -> Int64? {
        let bytes = Array(date.utf8)
        return bytes.count == 10 ? days(fromDateBytes: bytes[0..<10]) : nil
    }

    /// The `YYYY-MM-DD` key of a day since 1970-01-01 (years 0…9999).
    public static func string(epochDay: Int64) -> String {
        // Howard Hinnant's civil_from_days.
        let shifted = epochDay + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    /// `date` moved by whole calendar days, or `nil` when `date` is not a calendar day.
    public static func adding(_ days: Int, to date: String) -> String? {
        epochDay(date).map { string(epochDay: $0 + Int64(days)) }
    }

    /// 1 Sunday … 7 Saturday, as `Calendar` numbers weekdays; `nil` when `date` is not a calendar day.
    public static func weekday(_ date: String) -> Int? {
        // 1970-01-01 was a Thursday (5).
        epochDay(date).map { Int((($0 + 4) % 7 + 7) % 7) + 1 }
    }

    public static func isFriday(_ date: String) -> Bool { weekday(date) == 6 }

    /// Every day of `month` (`YYYY-MM`), in order; `nil` unless `month` names a real month.
    public static func days(inMonth month: String) -> [String]? {
        guard let first = epochDay(month + "-01"), let next = self.month(1, from: month),
              let end = epochDay(next + "-01")
        else { return nil }
        return (first..<end).map { string(epochDay: $0) }
    }

    /// The month (`YYYY-MM`) `months` months from `month`, or `nil` unless `month` names a real month.
    public static func month(_ months: Int, from month: String) -> String? {
        let bytes = Array(month.utf8)
        guard bytes.count == 7, epochDay(month + "-01") != nil,
              let year = digits(bytes[0..<4]), let number = digits(bytes[5..<7])
        else { return nil }
        let index = year * 12 + number - 1 + Int64(months)
        let shiftedYear = index >= 0 ? index / 12 : (index - 11) / 12
        return "\(pad(shiftedYear, 4))-\(pad(index - shiftedYear * 12 + 1, 2))"
    }

    private static func pad(_ value: Int64, _ width: Int) -> String {
        let digits = String(value)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }
}
