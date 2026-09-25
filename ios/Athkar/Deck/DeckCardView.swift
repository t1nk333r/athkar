import SwiftUI

/// One card: the PWAs' `.dhikr-card` / `.surah-card`. The whole card is the tap target (a button under the
/// content, as `.card-tap-target` is); the reset button, the target picker and «المصدر والتفاصيل» sit above it.
/// Text steps down through the PWA's fit steps until it fits the card, and scrolls only if none fits.
struct DeckCardView: View {
    let card: DeckCard
    let onTap: () -> Void
    let onReset: () -> Void
    let onTarget: @MainActor (Int) -> Void
    let onSource: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.readingMetrics) private var metrics
    @State private var isPressed = false

    private var isDhikr: Bool {
        if case .dhikr = card.content { return true }
        return false
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.viewportWidth <= 380 ? 22.4 : 28, style: .continuous)
    }

    var body: some View {
        ZStack {
            // A review card has no tap target and no footer (`cardMarkup` for `item.review`).
            if !card.isReview {
                Button(action: onTap) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(PressTrackingStyle(isPressed: $isPressed))
                .disabled(card.isComplete)
                .accessibilityLabel(card.tapLabel)
                .accessibilityIdentifier("deck.card.tap")
                // Read after the text and the counter, as the PWAs' `.card-tap-target` comes last in the card.
                .accessibilitySortPriority(-1)
            }

            VStack(spacing: 0) {
                if case let .ruqyah(segment) = card.content {
                    RuqyahCardHead(segment: segment)
                }
                switch card.content {
                case let .dhikr(item) where card.isReview:
                    ReviewCardBody(item: item, number: card.number)
                case let .dhikr(item):
                    DhikrCardBody(item: item, number: card.number, onTap: onTap, onSource: onSource)
                case let .ruqyah(segment):
                    RuqyahCardBody(segment: segment, onTap: onTap)
                }
                if !card.isReview {
                    footer
                }
            }
            .padding(padding)
            .environment(\.cardFill, fill)
        }
        .background(background)
        .overlay {
            shape.fill(palette.accent).opacity(isPressed ? 0.09 : 0).allowsHitTesting(false)
        }
        .clipShape(shape)
        .scaleEffect(isPressed ? 0.993 : 1)
        .animation(.easeOut(duration: 0.11), value: isPressed)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deck.card.\(card.id)")
    }

    private var padding: CGFloat {
        let vw = metrics.viewportWidth * 0.04
        return isDhikr ? min(max(18.4, vw), 28) : min(max(16.8, vw), 25.6)
    }

    /// `.dhikr-card.is-complete`, and `.dhikr-card.needs-review`: a dashed warning border on a warning tint.
    private var fill: Color {
        if card.isReview { return palette.warningSoft.mixed(0.55, with: palette.surface) }
        return card.isComplete ? palette.completedSoft.mixed(0.42, with: palette.surface) : palette.surface
    }

    private var background: some View {
        shape
            .fill(fill)
            .overlay {
                if card.isReview {
                    shape.strokeBorder(palette.warning.mixed(0.6, with: palette.border),
                                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else {
                    shape.strokeBorder(card.isComplete
                        ? palette.completed.mixed(0.48, with: palette.border) : palette.border)
                }
            }
            .overlay(alignment: .leading) {
                if isDhikr {
                    Capsule()
                        .fill(card.isComplete && !card.isReview ? palette.completed : palette.divider)
                        .frame(width: card.isComplete && !card.isReview ? 4.8 : 3.5)
                        .padding(.vertical, 17.6)
                }
            }
            .shadow(color: .black.opacity(0.06), radius: 11, y: 6)
    }

    // MARK: Footer (`.requirement-row`, `.card-foot`)

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(isDhikr ? palette.divider : palette.border).frame(height: 1)
            HStack(alignment: isDhikr ? .bottom : .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.requirement)
                        .font((isDhikr ? Font.footnote : .caption).weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                        .allowsHitTesting(false)
                    if let options = card.targetOptions {
                        targetPicker(options)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    counterStatus
                    resetButton
                }
            }
            .padding(.top, isDhikr ? 16 : 11)
        }
        .padding(.top, isDhikr ? 19 : 0)
    }

    private var counterStatus: some View {
        let complete = card.isComplete
        return HStack(spacing: 5) {
            switch card.status {
            case .numeric:
                Text("\(ArabicFormat.number(card.count))/\(ArabicFormat.number(card.target))")
            case let .text(copy):
                Text(copy)
            }
            if complete, isDhikr {
                Text("✓").foregroundStyle(palette.completed)
            }
        }
        .environment(\.layoutDirection, card.status == .numeric ? .leftToRight : .rightToLeft)
        .font((isDhikr ? Font.subheadline : .footnote).weight(.heavy))
        .foregroundStyle(complete ? palette.completed : palette.accentStrong)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, isDhikr ? 13 : 10)
        .frame(minWidth: isDhikr ? 85 : 54, minHeight: isDhikr ? 44 : 42)
        .background {
            Capsule().fill(isDhikr ? (complete ? palette.completedSoft : palette.accentSoft) : palette.surfaceRaised)
        }
        .overlay {
            Capsule().strokeBorder(complete
                ? palette.completed.mixed(0.55, with: isDhikr ? palette.border : palette.divider)
                : isDhikr ? palette.accent.mixed(0.45, with: palette.border) : palette.divider)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.progressLabel)
        .accessibilityIdentifier("deck.card.counter")
        .allowsHitTesting(false)
    }

    private var resetButton: some View {
        Button(action: onReset) {
            HStack(spacing: 4) {
                Text("↻").accessibilityHidden(true)
                Text("إعادة")
            }
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 10)
            .frame(minWidth: 43, minHeight: 44)
            .background(Capsule().fill(palette.surfaceRaised))
            .overlay(Capsule().strokeBorder(palette.border))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(card.count == 0)
        .opacity(card.count == 0 ? 0.36 : 1)
        .accessibilityLabel(card.resetLabel)
        .accessibilityIdentifier("deck.card.reset")
    }

    private func targetPicker(_ options: [Int]) -> some View {
        HStack(spacing: 7) {
            Text("الهدف")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .accessibilityHidden(true)
            Menu {
                Picker(selection: Binding(get: { card.target }, set: onTarget)) {
                    ForEach(options, id: \.self) { option in
                        Text(ArabicFormat.number(option)).tag(option)
                    }
                } label: {
                    EmptyView()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(ArabicFormat.number(card.target))
                    Image(systemName: "chevron.down").imageScale(.small)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 12)
                .frame(minWidth: 72, minHeight: 44)
                .background(Capsule().fill(palette.surfaceRaised))
                .overlay(Capsule().strokeBorder(palette.border))
                .contentShape(Capsule())
            }
            .accessibilityLabel(card.targetLabel)
            .accessibilityValue(ArabicFormat.number(card.target))
            .accessibilityIdentifier("deck.card.target")
        }
    }
}

/// Reports the tap target's pressed state to the card, which scales and tints as a whole (`:active`).
private struct PressTrackingStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in isPressed = pressed }
    }
}

/// Tries each fit step in turn and shows the first whose height fits; the last resort scrolls (the PWAs'
/// `overflow-y: auto`). The fallback is the only scroll view on a card, so `deck.card.overflow` marks a card that
/// did not fit.
private struct FittedBody<Candidate: View>: View {
    let steps: Int
    let alignment: Alignment
    let onTap: () -> Void
    @ViewBuilder let candidate: (Int) -> Candidate

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(0..<steps, id: \.self) { step in
                candidate(step)
            }
            OverflowScroll(onTap: onTap) {
                candidate(steps - 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// The scrolling fallback. While part of the content is still below the visible area it shows a fade over the
/// bottom edge and «المزيد» (which scrolls to the end); both go once the end is in view. The scroll indicator
/// flashes when the card appears, so a scrollable card never looks complete when it is not.
private struct OverflowScroll<Content: View>: View {
    let onTap: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.palette) private var palette
    @Environment(\.cardFill) private var fill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewportHeight: CGFloat = 0
    @State private var contentBottom: CGFloat = 0

    /// More than a point of content lies below the visible area.
    private var hasMoreBelow: Bool { viewportHeight > 0 && contentBottom - viewportHeight > 1 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    content
                    Color.clear.frame(height: 0).id(overflowSpace)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(overflowSpace)).maxY } action: {
                    contentBottom = $0
                }
            }
            .coordinateSpace(.named(overflowSpace))
            .accessibilityIdentifier("deck.card.overflow")
            .scrollIndicatorsFlash(onAppear: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .overlay(alignment: .bottom) {
                if hasMoreBelow {
                    more(proxy)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hasMoreBelow)
        }
    }

    private func more(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [fill.opacity(0), fill], startPoint: .top, endPoint: .bottom)
                .frame(height: 36)
                .allowsHitTesting(false)
            Button {
                if reduceMotion {
                    proxy.scrollTo(overflowSpace, anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(overflowSpace, anchor: .bottom) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("المزيد")
                    Image(systemName: "chevron.down").imageScale(.small)
                }
                .font(.caption.weight(.heavy))
                .foregroundStyle(palette.accentStrong)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(palette.accentSoft))
                .overlay(Capsule().strokeBorder(palette.accent.mixed(0.45, with: palette.border)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
            .background(fill)
            .accessibilityHint("يعرض بقية البطاقة")
            .accessibilityIdentifier("deck.card.more")
        }
    }
}

/// Coordinate space and scroll anchor of the overflow scroll view.
private let overflowSpace = "deck.card.overflow"

private extension EnvironmentValues {
    /// The card's background colour, which the overflow fade blends into.
    @Entry var cardFill: Color = .clear
}

// MARK: - Adhkar card body (`.card-content`)

private struct DhikrCardBody: View {
    let item: AdhkarItemContent
    let number: Int
    let onTap: () -> Void
    let onSource: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.readingMetrics) private var metrics

    var body: some View {
        let bodies = metrics.adhkarBodies(quran: item.isQuran)
        FittedBody(steps: bodies.count, alignment: .top, onTap: onTap) { step in
            content(bodies[step], step: step)
        }
    }

    private func content(_ size: ReadingMetrics.AdhkarBody, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CardNumber(number: number)
            if let prefix = item.prefix {
                Text(prefix)
                    .font(item.isQuran ? ReadingFont.quran(metrics.quranPrefix) : .system(size: metrics.quranPrefix,
                                                                                         weight: .heavy))
                    .cssLineHeight(1.7, size: metrics.quranPrefix, quran: item.isQuran)
                    .foregroundStyle(palette.accentStrong)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 13.6)
                    .allowsHitTesting(false)
            }
            Text(item.text)
                .font(item.isQuran ? ReadingFont.quran(size.text) : ReadingFont.dhikr(size.text))
                .cssLineHeight(size.textLineHeight, size: size.text, quran: item.isQuran)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
                .accessibilityIdentifier("deck.card.text.fit-\(step)")
            if !item.visibleDetails.isEmpty || item.hasExtendedDetails {
                VStack(alignment: .leading, spacing: size.detailsGap) {
                    ForEach(Array(item.visibleDetails.enumerated()), id: \.offset) { _, detail in
                        Text(detail)
                            .font(ReadingFont.detail(size.detail))
                            .cssLineHeight(size.detailLineHeight, size: size.detail, quran: false)
                            .foregroundStyle(palette.reference)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("deck.card.detail")
                    }
                    if item.hasExtendedDetails {
                        Button(action: onSource) {
                            Text("المصدر والتفاصيل")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(palette.reference)
                                .underline()
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("deck.card.source")
                    }
                }
                .padding(.top, size.detailsTop)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A review item (`.dhikr-card.needs-review`): its number with the badge «بحاجة إلى مراجعة», then `reviewTitle` set
/// as the text and `reviewCopy` in the warning colour. It is never fitted, so it scrolls when it must.
private struct ReviewCardBody: View {
    let item: AdhkarItemContent
    let number: Int

    @Environment(\.palette) private var palette
    @Environment(\.readingMetrics) private var metrics

    var body: some View {
        FittedBody(steps: 1, alignment: .top, onTap: {}) { _ in
            content
        }
    }

    private var content: some View {
        let copySize = 16 * metrics.typeScale
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7.2) {
                CardNumber(number: number)
                Text("بحاجة إلى مراجعة")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(palette.warning)
                    .padding(.horizontal, 10.4)
                    .padding(.vertical, 4)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(palette.warningSoft))
                    .accessibilityIdentifier("deck.card.review.badge")
            }
            Text(item.reviewTitle ?? item.text)
                .font(ReadingFont.dhikr(metrics.dhikrText))
                .cssLineHeight(metrics.dhikrLineHeight, size: metrics.dhikrText, quran: false)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("deck.card.review.title")
            if let copy = item.reviewCopy {
                Text(copy)
                    .font(.system(size: copySize, weight: .bold))
                    .cssLineHeight(1.8, size: copySize, quran: false)
                    .foregroundStyle(palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("deck.card.review.copy")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}

/// `.card-index`: the item's number over a short rule; hidden from VoiceOver, which hears it in the labels.
private struct CardNumber: View {
    let number: Int
    @Environment(\.palette) private var palette

    var body: some View {
        Text(ArabicFormat.number(number))
            .font(.caption.weight(.heavy))
            .foregroundStyle(palette.textSecondary)
            .frame(minWidth: 27)
            .padding(.bottom, 5)
            .overlay(alignment: .bottom) {
                Capsule().fill(palette.divider).frame(width: 19, height: 2)
            }
            .padding(.bottom, 8)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

// MARK: - Ruqyah card (`.card-head`, `.card-body`)

private struct RuqyahCardHead: View {
    let segment: RuqyahSegmentContent
    @Environment(\.palette) private var palette
    @Environment(\.readingMetrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(segment.surah)
                    .font(.system(size: metrics.ruqyahSurah, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text(segment.range)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.bottom, 9.6)
            Rectangle().fill(palette.border).frame(height: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct RuqyahCardBody: View {
    let segment: RuqyahSegmentContent
    let onTap: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.readingMetrics) private var metrics

    /// Printed as in the ruqyah PWA (`segmentMarkup`), which does not take it from the pack.
    private static let basmala = "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ"

    var body: some View {
        let steps = ReadingMetrics.ruqyahSteps
        FittedBody(steps: steps.count, alignment: .center, onTap: onTap) { index in
            content(steps[index], step: index)
        }
    }

    private func content(_ step: ReadingMetrics.RuqyahStep, step index: Int) -> some View {
        let size = metrics.ruqyahText * step.scale
        let lineHeight = metrics.ruqyahLineHeight - step.lead
        return VStack(spacing: 0) {
            if segment.basmala {
                let basmalaSize = size * 0.92
                Text(Self.basmala)
                    .font(ReadingFont.quran(basmalaSize))
                    .cssLineHeight(lineHeight, size: basmalaSize, quran: true)
                    .foregroundStyle(palette.accentStrong)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, index == 0 ? 11.2 : 8)
            }
            Text(ayat(size: size))
                .font(ReadingFont.quran(size))
                .cssLineHeight(lineHeight, size: size, quran: true)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("deck.card.text.fit-\(index)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13.6)
        .allowsHitTesting(false)
    }

    /// Each ayah followed by its number in ornate parentheses at 0.78em in the accent colour.
    private func ayat(size: CGFloat) -> AttributedString {
        var result = AttributedString()
        for (offset, ayah) in segment.ayahs.enumerated() {
            if offset > 0 { result += AttributedString(" ") }
            result += AttributedString(ayah.text + " ")
            var marker = AttributedString("﴿\(ArabicFormat.number(ayah.number))﴾")
            marker.font = ReadingFont.quran(size * 0.78)
            marker.foregroundColor = palette.accentStrong
            result += marker
        }
        return result
    }
}
