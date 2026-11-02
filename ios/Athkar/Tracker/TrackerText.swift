import AthkarCore
import Foundation

/// The tracker's wording. Neutral throughout: a prayer is recorded or not yet recorded, never missed, and no count is
/// a score.
enum TrackerText {
    static func prayer(_ prayer: ObligatoryPrayer) -> String {
        switch prayer {
        case .fajr: "الفجر"
        case .dhuhr: "الظهر"
        case .asr: "العصر"
        case .maghrib: "المغرب"
        case .isha: "العشاء"
        }
    }

    /// The slot's name: a Friday's Dhuhr names Jumu'ah once the user chose it, and both until they say.
    static func slot(_ occurrence: PrayerOccurrence, entry: PrayerEntry) -> String {
        guard occurrence.isFridayDhuhr else { return prayer(occurrence.prayer) }
        switch entry.noon {
        case .jumuah: return noon(.jumuah)
        case .dhuhr: return noon(.dhuhr)
        case nil: return "الظهر أو الجمعة"
        }
    }

    static func state(_ state: PrayerRecordState) -> String {
        switch state {
        case .unrecorded: "لم تُسجَّل"
        case .prayed: "صلّيتُها"
        case .notApplicable: "لا تنطبق"
        }
    }

    static func timing(_ timing: PrayerTiming?) -> String {
        switch timing {
        case nil: "بلا تحديد"
        case .onTime: "في وقتها"
        case .late: "متأخرة"
        case .madeUp: "قضاء"
        }
    }

    static func noon(_ noon: NoonPrayer) -> String {
        switch noon {
        case .dhuhr: "الظهر"
        case .jumuah: "الجمعة"
        }
    }

    /// A row's state as read aloud and shown under its name: the state, then the timing or the noon choice if any.
    static func summary(_ entry: PrayerEntry) -> String {
        var parts = [state(entry.state)]
        if let timing = entry.timing { parts.append(self.timing(timing)) }
        return parts.joined(separator: "، ")
    }

    /// The undo bar after a change: «الفجر: صلّيتُها».
    static func change(_ occurrence: PrayerOccurrence, entry: PrayerEntry) -> String {
        "\(slot(occurrence, entry: entry)): \(state(entry.state))"
    }

    /// A day's prayers as plain counts, «٣ من ٥»: recorded as prayed out of those that apply.
    static func count(prayed: Int, applicable: Int) -> String {
        "\(ArabicFormat.number(prayed)) من \(ArabicFormat.number(applicable))"
    }

    /// The أخرى grid's line for «اليوم».
    static func todaySubtitle(prayed: Int, applicable: Int) -> String {
        "الصلوات: " + count(prayed: prayed, applicable: applicable)
    }

    /// The weekday letters of the calendar's header, Saturday first, with their full names for VoiceOver.
    static let weekdays: [(letter: String, name: String)] = [
        ("س", "السبت"), ("ح", "الأحد"), ("ن", "الاثنين"), ("ث", "الثلاثاء"), ("ر", "الأربعاء"), ("خ", "الخميس"),
        ("ج", "الجمعة"),
    ]

    /// «نوفمبر ٢٠٢٦».
    static func month(_ month: String) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return month }
        let names = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر",
                     "نوفمبر", "ديسمبر"]
        return "\(names[parts[1] - 1]) \(ArabicFormat.number(parts[0]))"
    }

    /// The day number of a `YYYY-MM-DD` date, «٣٠».
    static func dayNumber(_ date: String) -> String {
        ArabicFormat.number(Int(date.suffix(2)) ?? 0)
    }

    /// What VoiceOver reads for a calendar day: its counts and completions, never a judgement.
    static func dayDescription(_ day: PrayerDaySummary) -> String {
        if day.isFuture { return "لم يأتِ بعد" }
        var parts: [String] = []
        if day.hasPrayerRecords {
            parts.append("الصلوات المسجّلة: " + count(prayed: day.prayed, applicable: day.applicable))
        } else {
            parts.append("لا تسجيل للصلوات")
        }
        if day.morning { parts.append("أذكار الصباح") }
        if day.evening { parts.append("أذكار المساء") }
        if day.ruqyah { parts.append("الرقية") }
        return parts.joined(separator: "، ")
    }

    /// The month's plain totals.
    static func totals(_ totals: PrayerMonthTotals) -> [String] {
        ["الصلوات المسجّلة: " + ArabicFormat.number(totals.prayed),
         "أذكار الصباح: " + ArabicFormat.dayCount(totals.morning),
         "أذكار المساء: " + ArabicFormat.dayCount(totals.evening),
         "الرقية: " + ArabicFormat.dayCount(totals.ruqyah)]
    }
}
