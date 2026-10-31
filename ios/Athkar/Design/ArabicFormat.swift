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
    static func time(_ instant: Date, in zone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(locale: Locale(identifier: "ar-EG")).hour().minute()
        style.timeZone = zone
        return instant.formatted(style)
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

    /// A time left in whole minutes, worded to follow «بعد»: «دقيقة», «دقيقتين», «٣ دقائق», «١١ دقيقة», «ساعة»,
    /// «ساعتين و٥ دقائق», «٣ ساعات ودقيقة». `total` is at least 1.
    static func minutesLeft(_ total: Int) -> String {
        let hours = total / 60
        let minutes = total % 60
        let hourWords = counted(hours, one: "ساعة", two: "ساعتين", few: "ساعات", many: "ساعة")
        let minuteWords = counted(minutes, one: "دقيقة", two: "دقيقتين", few: "دقائق", many: "دقيقة")
        if hours == 0 { return minuteWords }
        if minutes == 0 { return hourWords }
        return hourWords + " و" + minuteWords
    }

    /// Minutes and seconds left, «١٤:٥٩», «٠:٠٥».
    static func countdown(seconds total: Int) -> String {
        let seconds = max(0, total)
        return "\(number(seconds / 60)):\(number(seconds % 60 / 10))\(number(seconds % 10))"
    }

    private static func counted(_ count: Int, one: String, two: String, few: String, many: String) -> String {
        switch count {
        case 1: one
        case 2: two
        case 3...10: "\(number(count)) \(few)"
        default: "\(number(count)) \(many)"
        }
    }
}
