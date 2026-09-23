import Foundation

/// Instants as the PWAs write them: JS `Date.prototype.toISOString()`, e.g. `2026-09-22T17:38:40.481Z`.
///
/// This is the one textual instant format in the database and in the backup envelope (spec/schema.md).
/// Parsing accepts the envelope pattern `YYYY-MM-DDTHH:MM:SS(.fraction)?Z` and rejects values that are not
/// real UTC wall-clock times (`2026-02-30T…`, `T24:00`), as the PWA exporter's `backupInstant` does.
/// Fractions beyond milliseconds are truncated; formatting always writes exactly three fraction digits.
enum ISOInstant {
    static func format(_ date: Date) -> String {
        let milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let (seconds, millisecond) = floorDivide(milliseconds, 1000)
        let (days, secondOfDay) = floorDivide(seconds, 86_400)
        let (year, month, day) = LocalDate.civil(fromDays: days)
        let hour = secondOfDay / 3600
        let minute = secondOfDay % 3600 / 60
        let second = secondOfDay % 60
        return LocalDate.format(year: year, month: month, day: day)
            + "T" + pad(hour, 2) + ":" + pad(minute, 2) + ":" + pad(second, 2)
            + "." + pad(millisecond, 3) + "Z"
    }

    static func parse(_ text: String) -> Date? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 20, bytes[10] == UInt8(ascii: "T"), bytes[13] == UInt8(ascii: ":"),
              bytes[16] == UInt8(ascii: ":"), bytes.last == UInt8(ascii: "Z"),
              let days = LocalDate.days(fromDateBytes: bytes[0..<10]),
              let hour = LocalDate.digits(bytes[11..<13]), hour < 24,
              let minute = LocalDate.digits(bytes[14..<16]), minute < 60,
              let second = LocalDate.digits(bytes[17..<19]), second < 60
        else { return nil }

        var millisecond: Int64 = 0
        let tail = bytes[19..<(bytes.count - 1)]
        if !tail.isEmpty {
            let fraction = tail.dropFirst()
            guard tail.first == UInt8(ascii: "."), !fraction.isEmpty,
                  fraction.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") })
            else { return nil }
            let firstThree = fraction.prefix(3)
            millisecond = LocalDate.digits(firstThree)! * [100, 10, 1][firstThree.count - 1]
        }
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second
        return Date(timeIntervalSince1970: Double(seconds * 1000 + millisecond) / 1000)
    }

    private static func floorDivide(_ value: Int64, _ divisor: Int64) -> (Int64, Int64) {
        let remainder = value % divisor
        return remainder < 0 ? (value / divisor - 1, remainder + divisor) : (value / divisor, remainder)
    }

    fileprivate static func pad(_ value: Int64, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

/// Local civil dates as `YYYY-MM-DD` strings (the PWAs' `localDateKey`), validated as real calendar days.
enum LocalDate {
    static func isValid(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        return bytes.count == 10 && days(fromDateBytes: bytes[0..<10]) != nil
    }

    /// Days since 1970-01-01 for `YYYY-MM-DD`, or `nil` if the bytes are not a real proleptic Gregorian date.
    static func days(fromDateBytes bytes: ArraySlice<UInt8>) -> Int64? {
        let start = bytes.startIndex
        guard bytes.count == 10, bytes[start + 4] == UInt8(ascii: "-"), bytes[start + 7] == UInt8(ascii: "-"),
              let year = digits(bytes[start..<(start + 4)]),
              let month = digits(bytes[(start + 5)..<(start + 7)]),
              let day = digits(bytes[(start + 8)..<(start + 10)]),
              (1...12).contains(month), day >= 1, day <= daysInMonth(year: year, month: month)
        else { return nil }
        return daysFromCivil(year: year, month: month, day: day)
    }

    static func format(year: Int64, month: Int64, day: Int64) -> String {
        ISOInstant.pad(year, 4) + "-" + ISOInstant.pad(month, 2) + "-" + ISOInstant.pad(day, 2)
    }

    // Howard Hinnant's days_from_civil / civil_from_days.
    static func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func civil(fromDays days: Int64) -> (year: Int64, month: Int64, day: Int64) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    private static func daysInMonth(year: Int64, month: Int64) -> Int64 {
        switch month {
        case 2: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Decimal value of a short run of ASCII digits; `nil` if empty or any byte is not a digit.
    static func digits(_ bytes: ArraySlice<UInt8>) -> Int64? {
        guard !bytes.isEmpty else { return nil }
        var value: Int64 = 0
        for byte in bytes {
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            value = value * 10 + Int64(byte - UInt8(ascii: "0"))
        }
        return value
    }
}
