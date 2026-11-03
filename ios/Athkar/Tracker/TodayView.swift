import AthkarCore
import SwiftUI

/// «اليوم» in أخرى (MOBILE_APP_PLAN.md §5): the Gregorian and Hijri date, the next prayer with its countdown, the five
/// prayers to record, and the morning and evening adhkar with a way into each.
struct TodayView: View {
    let app: AppModel

    @Environment(\.palette) private var palette

    var body: some View {
        TimelineView(.everyMinute) { _ in
            content(today: app.tracker.today)
        }
        .overlay(alignment: .bottom) {
            TrackerUndoBar(tracker: app.tracker)
                .padding(.bottom, 4)
                .animation(.easeOut(duration: 0.2), value: app.tracker.lastChange)
        }
    }

    private func content(today: String) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                dateCard(today)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    nextPrayer(now: context.date)
                }
                sectionTitle("صلوات اليوم")
                TrackerPrayerList(tracker: app.tracker, date: today, schedule: app.prayer.schedule(on: today))
                sectionTitle("الأذكار")
                adhkar
                Button {
                    app.otherSection = .calendar
                } label: {
                    Label("التقويم", systemImage: "calendar")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("today.calendar")
            }
            .padding(.top, 8)
            // Room for the undo bar over the last row.
            .padding(.bottom, 64)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func dateCard(_ today: String) -> some View {
        VStack(spacing: 2) {
            Text(PrayerDates.gregorian(today))
                .font(.headline.weight(.bold))
                .foregroundStyle(palette.textPrimary)
                .accessibilityIdentifier("today.date")
            Text(PrayerDates.hijri(today, offset: app.prayer.settings.hijriOffset))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("today.hijri")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .card(palette)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func nextPrayer(now: Date) -> some View {
        if let next = app.prayer.countdown(now: now) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(PrayerNames.counting(to: next))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(ArabicFormat.time(next.at, in: app.prayer.zone))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 8)
                Text("بعد " + PrayerDates.remaining(from: now, to: next.at))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(palette.accentStrong)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .card(palette)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today.next")
        } else {
            Button {
                app.otherSection = .prayerTimes
            } label: {
                HStack {
                    Text(app.prayer.location == nil ? "حدّد موقعك لعرض مواقيت الصلاة" : "لا مواقيت اليوم")
                    Spacer(minLength: 0)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.accentStrong)
                .padding(.horizontal, 4)
                .frame(minHeight: 48)
                .card(palette)
                .contentShape(Corner.box)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.next")
        }
    }

    private var adhkar: some View {
        VStack(spacing: 0) {
            adhkarRow(.morning)
            Rule()
            adhkarRow(.evening)
        }
        .card(palette)
    }

    private func adhkarRow(_ deck: DeckID) -> some View {
        let model = app.deck(deck)
        let complete = model.isDayComplete
        let title = deck == .morning ? DeckDefinition.morning.title : DeckDefinition.evening.title
        return Button {
            app.ensureCurrentDay()
            app.selection = deck
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Text(complete ? "✓ مكتملة" : model.listSummary.copy)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(complete ? palette.completed : palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(complete ? "مكتملة اليوم" : model.listSummary.copy)
        .accessibilityHint("يفتح الأذكار")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("today.adhkar.\(deck.rawValue)")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
