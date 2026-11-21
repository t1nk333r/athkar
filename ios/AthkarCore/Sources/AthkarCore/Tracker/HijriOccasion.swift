import Foundation

/// A civil day's date in the Umm al-Qura Hijri calendar, shifted by the user's offset
/// (``CalculationSettings/hijriOffset``), as «أوقات الصلاة» and the home row show it.
public struct HijriDate: Equatable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The Hijri date of `localDate` (`YYYY-MM-DD`): its noon, moved by `offset` days. `nil` for a string that is not
    /// a real day.
    public static func of(_ localDate: String, offset: Int) -> HijriDate? {
        guard let epochDay = LocalDate.epochDay(localDate) else { return nil }
        let noon = Date(timeIntervalSince1970: Double(epochDay + Int64(offset)) * 86_400 + 43_200)
        let parts = ummAlQura.dateComponents([.year, .month, .day], from: noon)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return HijriDate(year: year, month: month, day: day)
    }

    private static let ummAlQura: Calendar = {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}

/// The days the calendar marks: Ramadan, the two Eids, the days of Hajj and the first day of the Hijri year. Nothing
/// else is marked, so no day the Sunnah does not single out (no Mawlid, Isra and Mi'raj or mid-Sha'ban).
public enum HijriOccasion: String, CaseIterable, Sendable {
    /// 1 Muharram.
    case newYear
    /// Every day of Ramadan.
    case ramadan
    /// 1 Shawwal.
    case eidAlFitr
    /// 8 Dhu al-Hijjah.
    case tarwiyah
    /// 9 Dhu al-Hijjah.
    case arafah
    /// 10 Dhu al-Hijjah.
    case eidAlAdha
    /// 11–13 Dhu al-Hijjah.
    case tashriq

    public static func of(_ date: HijriDate) -> HijriOccasion? {
        switch (date.month, date.day) {
        case (1, 1): .newYear
        case (9, _): .ramadan
        case (10, 1): .eidAlFitr
        case (12, 8): .tarwiyah
        case (12, 9): .arafah
        case (12, 10): .eidAlAdha
        case (12, 11...13): .tashriq
        default: nil
        }
    }

    public var title: String {
        switch self {
        case .newYear: "بداية السنة الهجرية"
        case .ramadan: "رمضان"
        case .eidAlFitr: "عيد الفطر"
        case .tarwiyah: "يوم التروية"
        case .arafah: "يوم عرفة"
        case .eidAlAdha: "عيد الأضحى"
        case .tashriq: "أيام التشريق"
        }
    }

    /// Whether it is a day of Hajj (8–13 Dhu al-Hijjah).
    public var isHajj: Bool { [.tarwiyah, .arafah, .eidAlAdha, .tashriq].contains(self) }
}
