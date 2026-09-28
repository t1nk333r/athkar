import AthkarCore
import SwiftUI

/// The home header's prayer row, in the title's place: the current prayer and its time, today's Hijri date in a box
/// (the day large, the month and year under it), and the next prayer with the time left. Tapping it opens أوقات الصلاة.
/// Without a location the date still shows and the next prayer's place asks for one.
struct HomePrayerRow: View {
    let prayer: PrayerTimesModel
    let open: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: open) {
            TimelineView(.everyMinute) { context in
                row(now: context.date)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.prayerRow")
    }

    private func row(now: Date) -> some View {
        let current = Self.current(prayer, now: now)
        let next = prayer.nextPrayer(now: now)
        let date = HijriDay(PrayerTimesModel.localDate(daysFromToday: 0, now: now, in: prayer.zone),
                            offset: prayer.settings.hijriOffset)
        return HStack(spacing: 8) {
            side(label: "الآن",
                 name: current.map { PrayerNames.name($0.prayer) } ?? "—",
                 detail: current.map { ArabicFormat.time($0.at, in: prayer.zone) },
                 dimmed: current == nil || current?.prayer == .sunrise, accent: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            dateBox(date)
            side(label: "القادمة",
                 name: next.map { PrayerNames.name($0.prayer) } ?? "حدّد موقعك",
                 detail: next.map { "بعد " + Self.left(from: now, to: $0.at) },
                 dimmed: false, accent: next == nil)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(current: current, next: next, now: now, date: date, zone: prayer.zone))
        .accessibilityHint("يفتح أوقات الصلاة")
    }

    private func side(label: String, name: String, detail: String?, dimmed: Bool, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            Text(name)
                .font((accent ? Font.footnote : .headline).weight(.heavy))
                .foregroundStyle(accent ? palette.accentStrong : dimmed ? palette.textSecondary : palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let detail {
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent || label == "القادمة" ? palette.accentStrong : palette.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
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
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.border))
        .accessibilityIdentifier("home.hijri")
    }

    // MARK: Times

    /// The last of today's times at or before `now` (sunrise included, a clamped Asr skipped); before Fajr, yesterday's
    /// Isha.
    static func current(_ prayer: PrayerTimesModel, now: Date) -> NextPrayer? {
        guard let today = prayer.schedule(dayOffset: 0, now: now) else { return nil }
        let order: [PrayerTime] = [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha]
        for time in order.reversed() where !(time == .asr && today.asrClamped) {
            if let at = today[time], at <= now { return NextPrayer(prayer: time, at: at) }
        }
        guard let isha = prayer.schedule(dayOffset: -1, now: now)?.isha else { return nil }
        return NextPrayer(prayer: .isha, at: isha)
    }

    /// «٤٥ د», «١ س ٢٠ د».
    static func left(from now: Date, to target: Date) -> String {
        let minutes = max(0, Int((target.timeIntervalSince(now) / 60).rounded(.up)))
        let hours = minutes / 60
        return hours == 0 ? "\(ArabicFormat.number(minutes)) د"
            : "\(ArabicFormat.number(hours)) س \(ArabicFormat.number(minutes % 60)) د"
    }

    private static func spoken(current: NextPrayer?, next: NextPrayer?, now: Date, date: HijriDay,
                               zone: TimeZone) -> String {
        var parts: [String] = []
        if let current { parts.append("الآن \(PrayerNames.name(current.prayer)) \(ArabicFormat.time(current.at, in: zone))") }
        parts.append("\(date.day) \(date.monthYear)")
        if let next {
            parts.append("القادمة \(PrayerNames.name(next.prayer)) بعد \(left(from: now, to: next.at))")
        } else {
            parts.append("حدّد موقعك لعرض المواقيت")
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
