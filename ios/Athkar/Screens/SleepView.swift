import AthkarCore
import SwiftUI

/// «أذكار النوم» in أخرى, the PWA's sleep tab (`renderSleepPanel`): each item of the sleep pack under its title, in
/// pack order. Quran passages are set in the mushaf face, a passage that opens a sura under the basmala; al-Mulk comes
/// from the «سور» pack. A repeated item names its count. Nothing is counted.
struct SleepView: View {
    let content: SleepContent

    @Environment(\.palette) private var palette
    @Environment(\.readingMetrics) private var metrics

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(content.items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                        .padding(.top, index == 0 ? 0 : 18)
                        .overlay(alignment: .top) { if index > 0 { Rule() } }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 24)
            .padding(.horizontal, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func row(_ item: SleepContent.Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = item.title {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.accentStrong)
                    .accessibilityAddTraits(.isHeader)
            }
            if let prefix = item.prefix { detail(prefix) }
            ForEach(Array((item.quran ?? []).enumerated()), id: \.offset) { _, passage in
                quran(passage)
            }
            if let text = item.text {
                Text(text)
                    .font(ReadingFont.dhikr(metrics.dhikrText))
                    .cssLineHeight(metrics.dhikrLineHeight, size: metrics.dhikrText, face: .system)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let steps = item.steps {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { number, step in
                        Text("\(ArabicFormat.number(number + 1)). \(step)")
                            .font(ReadingFont.dhikr(metrics.dhikrText))
                            .cssLineHeight(metrics.dhikrLineHeight, size: metrics.dhikrText, face: .system)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let countLabel = item.countLabel {
                Text(countLabel)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(palette.accentStrong)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(palette.accentSoft, in: Capsule())
            }
            if let note = item.note { detail(note.text) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sleep.\(item.id)")
    }

    private func quran(_ passage: SleepContent.Passage) -> some View {
        VStack(spacing: 4) {
            if passage.basmala, !content.basmala.isEmpty {
                Text(MushafEncoding.kfgqpc(content.basmala))
                    .font(ReadingFont.mushaf(metrics.quranPrefix))
                    .cssLineHeight(1.7, size: metrics.quranPrefix, face: .mushaf)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
            }
            Text(DhikrCardBody.quranText(passage.text, size: metrics.quranText))
                .font(ReadingFont.mushaf(metrics.quranText))
                .cssLineHeight(metrics.quranLineHeight, size: metrics.quranText, face: .mushaf)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(passage.citation)
                .font(ReadingFont.detail(metrics.detailText))
                .foregroundStyle(palette.reference)
        }
        .frame(maxWidth: .infinity)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(ReadingFont.detail(metrics.detailText))
            .cssLineHeight(metrics.detailLineHeight, size: metrics.detailText, face: .system)
            .foregroundStyle(palette.reference)
            .fixedSize(horizontal: false, vertical: true)
    }
}
