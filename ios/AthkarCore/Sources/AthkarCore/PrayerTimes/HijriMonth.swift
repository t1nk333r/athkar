import Foundation

/// The Umm al-Qura Hijri calendar the app shows its dates in, shifted by the user's offset
/// (``CalculationSettings/hijriOffset``), as «أوقات الصلاة» and the home row do.
enum HijriMonth {
    /// Whether the civil day `localDay` (days since 1970-01-01) is in Ramadan: its noon, moved by `offset` days,
    /// falls in the ninth month.
    static func isRamadan(localDay: Int64, offset: Int) -> Bool {
        let noon = Date(timeIntervalSince1970: Double(localDay + Int64(offset)) * 86_400 + 43_200)
        return ummAlQura.component(.month, from: noon) == 9
    }

    private static let ummAlQura: Calendar = {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
