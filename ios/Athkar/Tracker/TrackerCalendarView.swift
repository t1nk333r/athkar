import AthkarCore
import SwiftUI

/// «التقويم» in أخرى: a month of days, each with its prayers as a plain count and marks for the morning and evening
/// adhkar and the ruqyah completed that day. Nothing scores a day, and a day without records looks like any other.
/// A past day opens with the same controls as «اليوم»; days after today are read-only.
struct TrackerCalendarView: View {
    let app: AppModel

    @Environment(\.palette) private var palette
    /// The month on screen (`YYYY-MM`), or `nil` for the current one.
    @State private var shownMonth: String?
    @State private var openDay: CalendarDay?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let today = app.tracker.today
        let current = String(today.prefix(7))
        let month = shownMonth ?? current
        ScrollView {
            VStack(spacing: 10) {
                header(month, current: current)
                if let summary = app.tracker.month(month) {
                    grid(summary, today: today)
                    legend
                    totals(summary.totals)
                }
            }
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(item: $openDay) { day in
            TrackerDaySheet(app: app, date: day.date)
                .environment(\.palette, palette)
        }
    }

    // MARK: Month

    private func header(_ month: String, current: String) -> some View {
        HStack(spacing: 8) {
            monthButton("الشهر السابق", systemImage: "chevron.backward", identifier: "calendar.previous",
                        target: LocalDate.month(-1, from: month))
            Text(TrackerText.month(month))
                .font(.headline.weight(.heavy))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("calendar.month")
            monthButton("الشهر التالي", systemImage: "chevron.forward", identifier: "calendar.next",
                        target: month < current ? LocalDate.month(1, from: month) : nil)
        }
        .padding(8)
        .card(palette)
    }

    private func monthButton(_ label: String, systemImage: String, identifier: String,
                             target: String?) -> some View {
        Button {
            if let target { shownMonth = target }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.textSecondary)
        .disabled(target == nil)
        .opacity(target == nil ? 0.4 : 1)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func grid(_ summary: PrayerCalendarMonth, today: String) -> some View {
        // Saturday first: Saturday (7) is column 0, Sunday (1) column 1, … Friday (6) column 6.
        let leading = (summary.days.first?.weekday ?? 7) % 7
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(TrackerText.weekdays, id: \.letter) { weekday in
                Text(weekday.letter)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .accessibilityLabel(weekday.name)
            }
            ForEach(0..<leading, id: \.self) { index in
                Color.clear.frame(height: 1).accessibilityHidden(true).id("blank-\(index)")
            }
            ForEach(summary.days, id: \.date) { day in
                cell(day, isToday: day.date == today)
            }
        }
        .padding(8)
        .card(palette)
    }

    private func cell(_ day: PrayerDaySummary, isToday: Bool) -> some View {
        Button {
            openDay = CalendarDay(date: day.date)
        } label: {
            VStack(spacing: 2) {
                Text(TrackerText.dayNumber(day.date))
                    .font(.subheadline.weight(isToday ? .heavy : .semibold))
                    .foregroundStyle(isToday ? palette.accentStrong : palette.textPrimary)
                Text(day.hasPrayerRecords ? "\(ArabicFormat.number(day.prayed))/\(ArabicFormat.number(day.applicable))"
                                          : " ")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                HStack(spacing: 1) {
                    marker("sun.max.fill", shown: day.morning)
                    marker("moon.fill", shown: day.evening)
                    marker("shield.fill", shown: day.ruqyah)
                }
                .font(.system(size: 8))
                .foregroundStyle(palette.accent)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Corner.box.fill(isToday ? palette.accentSoft : Color.clear))
            .overlay(Corner.box.strokeBorder(isToday ? palette.accent : Color.clear))
            .contentShape(Corner.box)
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture)
        .opacity(day.isFuture ? 0.4 : 1)
        .accessibilityLabel(PrayerDates.gregorian(day.date) + (isToday ? "، اليوم" : ""))
        .accessibilityValue(TrackerText.dayDescription(day))
        .accessibilityIdentifier("calendar.day.\(day.date)")
    }

    /// A completion's mark; an empty slot otherwise, so a day without it looks like any other.
    private func marker(_ systemImage: String, shown: Bool) -> some View {
        Image(systemName: systemImage).opacity(shown ? 1 : 0)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label("أذكار الصباح", systemImage: "sun.max.fill")
            Label("أذكار المساء", systemImage: "moon.fill")
            Label("الرقية", systemImage: "shield.fill")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(palette.textSecondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("العلامات تحت كل يوم: أذكار الصباح، أذكار المساء، الرقية")
    }

    private func totals(_ totals: PrayerMonthTotals) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("هذا الشهر")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(palette.textPrimary)
            ForEach(TrackerText.totals(totals), id: \.self) { line in
                Text(line)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(palette.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .card(palette)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("calendar.totals")
    }
}

private struct CalendarDay: Identifiable {
    let date: String
    var id: String { date }
}

/// A day of the calendar: its five prayers with the controls of «اليوم», what was completed that day, and «مسح اليوم»
/// with its confirmation.
struct TrackerDaySheet: View {
    let app: AppModel
    let date: String

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsClear = false

    var body: some View {
        let tracker = app.tracker
        let summary = tracker.month(String(date.prefix(7)))?.days.first { $0.date == date }
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text(PrayerDates.hijri(date, offset: app.prayer.settings.hijriOffset))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity)
                    TrackerPrayerList(tracker: tracker, date: date, schedule: app.prayer.schedule(on: date))
                    if let summary {
                        completions(summary)
                    }
                    if summary?.hasPrayerRecords == true, tracker.isEditable(date) {
                        Button(role: .destructive) {
                            confirmsClear = true
                        } label: {
                            Label("مسح اليوم", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.heavy))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityIdentifier("calendar.clearDay")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 64)
            }
            .background(palette.background)
            .overlay(alignment: .bottom) {
                TrackerUndoBar(tracker: tracker)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            .navigationTitle(PrayerDates.gregorian(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                        .accessibilityIdentifier("calendar.dayDone")
                }
            }
            .alert("مسح تسجيلات هذا اليوم؟", isPresented: $confirmsClear) {
                Button("مسح", role: .destructive) { tracker.clearDay(date) }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("تعود صلوات هذا اليوم إلى «لم تُسجَّل». لا يتأثر ما أكملته من الأذكار.")
            }
        }
        .onDisappear { tracker.dismissUndo() }
    }

    private func completions(_ day: PrayerDaySummary) -> some View {
        let done = [(day.morning, "أذكار الصباح"), (day.evening, "أذكار المساء"), (day.ruqyah, "الرقية")]
            .filter { $0.0 }.map { $0.1 }
        return Text(done.isEmpty ? "لا تسجيل للأذكار في هذا اليوم"
                                 : "أُكملت في هذا اليوم: " + done.joined(separator: "، "))
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .card(palette)
            .accessibilityIdentifier("calendar.completions")
    }
}
