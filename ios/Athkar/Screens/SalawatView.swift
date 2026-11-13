import AthkarCore
import SwiftUI

/// «الصلاة على النبي ﷺ» in أخرى, the PWA's salawat tab (`renderSalawatPanel`): al-Ahzab 56 in the mushaf face, the
/// Friday virtue, then each salawat under its title with its note. From Thursday's Maghrib to Friday's it names the
/// time (spec/night/night.md). Nothing is counted.
struct SalawatView: View {
    let app: AppModel

    @Environment(\.palette) private var palette
    @Environment(\.readingMetrics) private var metrics

    /// «ليلة الجمعة» or «يوم الجمعة» now, on the prayer times' Maghrib and Fajr.
    static func fridayPhase(app: AppModel, now: Date = Date()) -> FridayPhase? {
        FridayPhase.at(now, in: app.prayer.zone) { app.prayer.nightTimes(on: $0) }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            ScrollView {
                content(phase: Self.fridayPhase(app: app, now: context.date))
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func content(phase: FridayPhase?) -> some View {
        let salawat = app.salawat
        return VStack(alignment: .leading, spacing: 20) {
            if let phase {
                Text(phase.title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(palette.accentStrong)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(palette.accentSoft, in: Capsule())
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("salawat.friday")
            }
            VStack(spacing: 4) {
                Text(DhikrCardBody.quranText(salawat.quran.text, size: metrics.quranText))
                    .font(ReadingFont.mushaf(metrics.quranText))
                    .cssLineHeight(metrics.quranLineHeight, size: metrics.quranText, face: .mushaf)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("salawat.quran")
                Text(salawat.quran.citation)
                    .font(ReadingFont.detail(metrics.detailText))
                    .foregroundStyle(palette.reference)
            }
            .frame(maxWidth: .infinity)
            note(salawat.virtue)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("salawat.virtue")
            ForEach(salawat.items) { item in
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.accentStrong)
                        .accessibilityAddTraits(.isHeader)
                    Text(item.text)
                        .font(ReadingFont.dhikr(metrics.dhikrText))
                        .cssLineHeight(metrics.dhikrLineHeight, size: metrics.dhikrText, face: .system)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let itemNote = item.note { note(itemNote) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 18)
                .overlay(alignment: .top) { Rule() }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("salawat.\(item.id)")
            }
        }
    }

    private func note(_ note: SalawatContent.Note) -> some View {
        Text(note.text)
            .font(ReadingFont.detail(metrics.detailText))
            .cssLineHeight(metrics.detailLineHeight, size: metrics.detailText, face: .system)
            .foregroundStyle(palette.reference)
            .fixedSize(horizontal: false, vertical: true)
    }
}
