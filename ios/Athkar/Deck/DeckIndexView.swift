import SwiftUI

/// The quick card index (spec §4, "Native quick index"): every card of the deck in its current order, with its
/// number, opening text (or surah and range), counter status and the current card marked. A row opens its card when
/// «السابق» and «التالي» could reach it (``DeckModel/canReach(_:)``); later cards behind an unread one stay visible
/// but disabled, under a note naming the card to read first.
struct DeckIndexView<Model: DeckModel>: View {
    let model: Model
    /// Called with a chosen card other than the current one, just before the sheet closes; the deck moves to it
    /// once the sheet is gone.
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        let rows = Array(model.cards.enumerated())
        let current = model.currentIndex
        // Reachability ends at the first card the lock keeps closed; the card before it has to be read first.
        let firstLocked = rows.indices.first { !model.canReach($0) }
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(rows[..<(firstLocked ?? rows.count)], id: \.element.id) { index, card in
                            row(index, card, current: current, lockHint: nil)
                        }
                        if let firstLocked {
                            let hint = lockHint(rows[firstLocked - 1].element)
                            lockNote(hint)
                            ForEach(rows[firstLocked...], id: \.element.id) { index, card in
                                row(index, card, current: current, lockHint: hint)
                            }
                        }
                    }
                    .padding()
                }
                .accessibilityIdentifier("deck.index.list")
                // Opens on the current card, without scrolling motion.
                .onAppear {
                    if let id = rows[safe: current]?.element.id { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .background(palette.background)
            .navigationTitle(model.definition.indexTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                        .accessibilityIdentifier("deck.index.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Choosing the current card only closes the index.
    private func row(_ index: Int, _ card: DeckCard, current: Int, lockHint: String?) -> some View {
        DeckIndexRow(card: card, position: model.positionLabel(index), isCurrent: index == current,
                     lockHint: lockHint) {
            if index != current { onSelect(card.id) }
            dismiss()
        }
    }

    /// «يُتاح بعد إكمال الذكر ٥»: the card «التالي» waits for, by its number.
    private func lockHint(_ card: DeckCard) -> String {
        "يُتاح بعد إكمال \(model.definition.cardNoun) \(ArabicFormat.number(card.number))"
    }

    private func lockNote(_ hint: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lock.fill").imageScale(.small).accessibilityHidden(true)
            Text(hint)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(palette.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("deck.index.lock")
    }
}

/// One card in the index, laid out like the reset picker's choices and coloured like the card it opens. VoiceOver
/// reads the card's counter label, never the encoded Quran text, and the deck position as its value.
private struct DeckIndexRow: View {
    let card: DeckCard
    let position: String
    let isCurrent: Bool
    /// Why the row is disabled; `nil` when the reader can open the card.
    let lockHint: String?
    let action: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.readingMetrics) private var metrics

    private var shape: RoundedRectangle { Corner.box }

    private var isDhikr: Bool {
        if case .dhikr = card.content { return true }
        return false
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                CardNumber(number: card.number)
                VStack(alignment: .leading, spacing: 8) {
                    opening
                    if card.isReview { reviewBadge } else { status }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if lockHint != nil {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(shape.fill(fill))
            .overlay { border }
            .overlay(alignment: .leading) {
                if isCurrent {
                    Capsule().fill(palette.accent).frame(width: 4.8).padding(.vertical, 12)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(lockHint != nil)
        .opacity(lockHint == nil ? 1 : 0.5)
        .accessibilityLabel(card.isReview ? "\(card.progressLabel)، بحاجة إلى مراجعة" : card.progressLabel)
        .accessibilityValue(position)
        .accessibilityHint(lockHint ?? "ينتقل إلى هذه البطاقة")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("deck.index.row.\(card.id)")
    }

    /// The card's text as the card sets it, cut to two lines by layout only; ruqyah and «سور» rows show surah and
    /// range.
    @ViewBuilder
    private var opening: some View {
        let size = 17 * metrics.typeScale
        switch card.content {
        case let .dhikr(item) where card.isReview:
            Text(item.reviewTitle ?? item.text)
                .font(ReadingFont.dhikr(size))
                .cssLineHeight(metrics.dhikrLineHeight, size: size, face: .system)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
        case let .dhikr(item):
            Group {
                if item.isMushafText { Text(DhikrCardBody.quranText(item.text, size: size)) } else { Text(item.text) }
            }
            .font(item.isMushafText ? ReadingFont.mushaf(size)
                  : item.isQuran ? ReadingFont.quran(size) : ReadingFont.dhikr(size))
            .cssLineHeight(item.isQuran ? metrics.quranLineHeight : metrics.dhikrLineHeight, size: size,
                           face: item.isMushafText ? .mushaf : item.isQuran ? .quran : .system)
            .foregroundStyle(palette.textPrimary)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
        case let .ruqyah(segment):
            surahAndRange(segment.surah, segment.range, size: size)
        case let .page(page, surah, _):
            surahAndRange(surah, page.range, size: size)
        }
    }

    private func surahAndRange(_ surah: String, _ range: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(surah)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text(range)
                .font(.footnote.weight(.bold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    /// The card's counter status: `count/target` left to right, or its phrase, with ✓ on a completed dhikr.
    private var status: some View {
        HStack(spacing: 5) {
            switch card.status {
            case .numeric:
                Text("\(ArabicFormat.number(card.count))/\(ArabicFormat.number(card.target))")
            case let .text(copy):
                Text(copy)
            }
            if card.isComplete, isDhikr {
                Text("✓").foregroundStyle(palette.completed)
            }
        }
        .environment(\.layoutDirection, card.status == .numeric ? .leftToRight : .rightToLeft)
        .font(.footnote.weight(.heavy))
        .foregroundStyle(card.isComplete ? palette.completed : palette.accentStrong)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Corner.box.fill(card.isComplete ? palette.completedSoft : palette.accentSoft))
    }

    private var reviewBadge: some View {
        Text("بحاجة إلى مراجعة")
            .font(.caption.weight(.heavy))
            .foregroundStyle(palette.warning)
            .padding(.horizontal, 10.4)
            .padding(.vertical, 4)
            .background(Corner.box.fill(palette.warningSoft))
    }

    /// As the card: a warning tint for review items, the completed tint once read.
    private var fill: Color {
        if card.isReview { return palette.warningSoft.mixed(0.55, with: palette.surface) }
        return card.isComplete ? palette.completedSoft.mixed(0.42, with: palette.surface) : palette.surfaceRaised
    }

    @ViewBuilder
    private var border: some View {
        if isCurrent {
            shape.strokeBorder(palette.accent, lineWidth: 2)
        } else if card.isReview {
            shape.strokeBorder(palette.warning.mixed(0.6, with: palette.border),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            shape.strokeBorder(card.isComplete ? palette.completed.mixed(0.48, with: palette.border) : palette.border)
        }
    }
}
