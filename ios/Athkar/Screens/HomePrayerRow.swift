import AthkarCore
import SwiftUI

/// The home header's prayer row, in the title's place: the next adhan with the time left («أذان الظهر» over «بعد ٣
/// دقائق», a seconds countdown in its last ``countdownWindow``), today's Hijri date in a box (the day large, the month
/// and year under it), and during «أوقات النهي عن الصلاة» (``ProhibitedTime``) a notice under them. Tapping it opens
/// أوقات الصلاة. Without a location the date still shows and the adhan's place asks for one.
struct HomePrayerRow: View {
    let prayer: PrayerTimesModel
    let open: () -> Void

    @Environment(\.palette) private var palette

    /// How long before an adhan the time left becomes a seconds countdown.
    static let countdownWindow: TimeInterval = 15 * 60

    var body: some View {
        Button(action: open) {
            TimelineView(.everyMinute) { minute in
                // Seconds tick only near an adhan. The minute tick can start them up to a minute early; the text
                // switches to the countdown at exactly ``countdownWindow``.
                if Self.countsDown(to: prayer.nextPrayer(now: minute.date), now: minute.date, slack: 60) {
                    TimelineView(.periodic(from: minute.date, by: 1)) { second in
                        row(now: second.date)
                    }
                } else {
                    row(now: minute.date)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.prayerRow")
    }

    private func row(now: Date) -> some View {
        let next = prayer.nextPrayer(now: now)
        let notice = prayer.schedule(dayOffset: 0, now: now).flatMap { ProhibitedTime.current(at: now, today: $0) }
        let date = HijriDay(PrayerTimesModel.localDate(daysFromToday: 0, now: now, in: prayer.zone),
                            offset: prayer.settings.hijriOffset)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                adhan(next, now: now)
                    .frame(maxWidth: .infinity, alignment: .leading)
                dateBox(date)
            }
            if let notice {
                noticeLine(notice)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(next: next, notice: notice, now: now, date: date, zone: prayer.zone))
        .accessibilityHint("يفتح أوقات الصلاة")
    }

    private func adhan(_ next: NextPrayer?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(next.map { Self.adhanName($0) } ?? "أوقات الصلاة")
                .font(.headline.weight(.heavy))
                .foregroundStyle(next == nil ? palette.textSecondary : palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(next.map { "بعد " + Self.left(from: now, to: $0.at) } ?? "حدّد موقعك")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accentStrong)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func noticeLine(_ notice: ProhibitedTime) -> some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(palette.warning)
                .frame(width: 3, height: 16)
            Text("وقت نهي عن الصلاة")
                .font(.caption.weight(.heavy))
                .foregroundStyle(palette.warning)
            Text(Self.until(notice, zone: prayer.zone))
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func dateBox(_ date: HijriDay) -> some View {
        VStack(spacing: 0) {
            Text(date.day)
                .font(.title2.weight(.heavy))
                .foregroundStyle(palette.textPrimary)
            Text(date.monthYear)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(minWidth: 72)
        .background(Corner.box.fill(palette.surfaceRaised))
        .overlay(Corner.box.strokeBorder(palette.border))
        .accessibilityIdentifier("home.hijri")
    }

    // MARK: Wording

    /// «أذان الظهر». The next time is always one of the five prayers, never sunrise.
    static func adhanName(_ next: NextPrayer) -> String {
        "أذان \(PrayerNames.name(next.prayer))"
    }

    /// Whether the time left to `next` is within ``countdownWindow`` (plus `slack`).
    static func countsDown(to next: NextPrayer?, now: Date, slack: TimeInterval = 0) -> Bool {
        guard let next else { return false }
        return next.at.timeIntervalSince(now) <= countdownWindow + slack
    }

    /// What follows «بعد»: «٣ دقائق», «ساعة و٢٠ دقيقة»; in the last ``countdownWindow``, «١٤:٥٩». Both round up, so it
    /// never reads zero before the adhan.
    static func left(from now: Date, to target: Date) -> String {
        let seconds = max(0, Int(target.timeIntervalSince(now).rounded(.up)))
        if TimeInterval(seconds) <= countdownWindow { return ArabicFormat.countdown(seconds: seconds) }
        return ArabicFormat.minutesLeft((seconds + 59) / 60)
    }

    /// The notice's end: «حتى نحو ٥:٥٠ ص» (the sun's rise is an estimate) or «حتى المغرب ٦:٠٠ م».
    static func until(_ notice: ProhibitedTime, zone: TimeZone) -> String {
        let time = ArabicFormat.time(notice.end, in: zone)
        return switch notice.kind {
        case .afterFajr: "حتى نحو \(time)"
        case .afterAsr: "حتى المغرب \(time)"
        }
    }

    /// The rule in full, for VoiceOver.
    static func rule(_ notice: ProhibitedTime, zone: TimeZone) -> String {
        let time = ArabicFormat.time(notice.end, in: zone)
        return switch notice.kind {
        case .afterFajr: "من صلاة الفجر حتى ارتفاع الشمس، نحو \(time)"
        case .afterAsr: "من صلاة العصر حتى أذان المغرب \(time)"
        }
    }

    /// In whole minutes even while the countdown runs, so the label does not change every second.
    private static func spoken(next: NextPrayer?, notice: ProhibitedTime?, now: Date, date: HijriDay,
                               zone: TimeZone) -> String {
        var parts: [String] = []
        if let next {
            let minutes = max(1, Int((next.at.timeIntervalSince(now) / 60).rounded(.up)))
            parts.append("\(adhanName(next)) بعد \(ArabicFormat.minutesLeft(minutes))")
        } else {
            parts.append("حدّد موقعك لعرض المواقيت")
        }
        parts.append("\(date.day) \(date.monthYear)")
        if let notice {
            parts.append("وقت نهي عن الصلاة \(rule(notice, zone: zone))")
        }
        return parts.joined(separator: "، ")
    }
}

/// Today's Umm al-Qura date, shifted by the user's offset: «٦» and «ربيع الآخر ١٤٤٨».
struct HijriDay {
    let day: String
    let monthYear: String

    init(_ localDate: String, offset: Int) {
        let utc = TimeZone(identifier: "UTC")!
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = utc
        let parts = localDate.split(separator: "-").compactMap { Int($0) }
        let noon = parts.count == 3
            ? gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date()
            : Date()
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = utc
        let date = hijri.date(byAdding: .day, value: offset, to: noon) ?? noon
        let locale = Locale(identifier: "ar-EG")
        var dayStyle = Date.FormatStyle(locale: locale, calendar: hijri).day()
        dayStyle.timeZone = utc
        var restStyle = Date.FormatStyle(locale: locale, calendar: hijri).month(.wide).year()
        restStyle.timeZone = utc
        day = date.formatted(dayStyle)
        monthYear = date.formatted(restStyle).replacingOccurrences(of: " هـ", with: "")
    }
}
