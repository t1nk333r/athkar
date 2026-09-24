import Foundation

/// Number, time and count wording as the PWAs produce them with `Intl` in the `ar-EG` locale.
enum ArabicFormat {
    /// `Intl.NumberFormat("ar-EG", { useGrouping: false })`: Arabic-Indic digits, no grouping.
    static func number(_ value: Int) -> String {
        String(String(value).unicodeScalars.map { scalar -> Character in
            guard let digit = scalar.properties.numericType == .decimal ? scalar.properties.numericValue : nil
            else { return Character(scalar) }
            return Character(Unicode.Scalar(0x0660 + UInt32(digit))!)
        })
    }

    /// `Intl.DateTimeFormat("ar-EG", { hour: "numeric", minute: "2-digit" })`, e.g. «٥:٠٣ م».
    static func time(_ instant: Date) -> String {
        instant.formatted(Date.FormatStyle(locale: Locale(identifier: "ar-EG")).hour().minute())
    }

    /// `dayCountLabel(count)` in both PWAs.
    static func dayCount(_ count: Int) -> String {
        switch count {
        case 1: "يوم واحد"
        case 2: "يومين"
        case ...10: "\(number(count)) أيام"
        default: "\(number(count)) يومًا"
        }
    }
}
