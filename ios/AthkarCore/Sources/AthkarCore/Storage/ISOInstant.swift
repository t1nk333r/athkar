import Foundation

/// Instants as the PWAs write them: JS `Date.prototype.toISOString()`, e.g. `2026-09-22T17:38:40.481Z`.
///
/// This is the one textual instant format in the database and in the backup envelope (spec/schema.md).
/// Parsing accepts the envelope pattern `YYYY-MM-DDTHH:MM:SS(.fraction)?Z` and rejects values that are not
/// real UTC wall-clock times (`2026-02-30T…`, `T24:00`), as the PWA exporter's `backupInstant` does.
/// Fractions beyond milliseconds are truncated on parse. Formatting is `SessionCalendar.isoString`, the single
/// `toISOString()` implementation: it truncates to whole milliseconds like JavaScript and always writes three
/// fraction digits.
enum ISOInstant {
    static func format(_ date: Date) -> String {
        SessionCalendar.isoString(date)
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

    // Howard Hinnant's days_from_civil.
    static func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
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
