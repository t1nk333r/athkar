import SwiftUI

/// The chips that pick a deck's section (the ruqyah PWA's `.sura-picker`): one per sura, in pack order from the
/// right, the selected one raised, and «✓» on each sura complete today. The chips switch suras at any time; the
/// «التالي» lock applies only within a sura.
struct SectionChips: View {
    let model: any DeckModel

    @Environment(\.palette) private var palette

    var body: some View {
        ChipRow(spacing: 4.8, growsFromContent: model.definition.chipsGrowFromContent) {
            ForEach(model.sections) { section in
                let selected = section.id == model.selectedSectionID
                Button {
                    model.selectSection(section.id)
                } label: {
                    HStack(spacing: 4) {
                        Text(section.title)
                        if section.isComplete {
                            Text("✓").foregroundStyle(palette.completed)
                        }
                    }
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(selected ? palette.accentStrong : palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6.4)
                    .frame(maxWidth: .infinity, minHeight: 36.8)
                    .background(Corner.box.fill(selected ? palette.accentSoft : palette.surfaceRaised))
                    .overlay(Corner.box.strokeBorder(selected ? palette.accent.opacity(0.55) : palette.border))
                    .contentShape(Corner.box)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.accessibilityLabel)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("deck.section.\(section.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("اختيار السورة")
        .accessibilityIdentifier("deck.sections")
    }
}

/// One row of chips, as CSS flexbox lays out `.sura-chip`: each chip's share starts from a basis, its content's width
/// (`flex: 1 1 auto`) or nothing (`flex: 1 1 0`), and the chips share the rest of the row equally. A row too narrow
/// for the bases shrinks each chip in proportion to its basis. Placement runs left to right; SwiftUI mirrors it in a
/// right-to-left layout.
struct ChipRow: Layout {
    var spacing: CGFloat
    var growsFromContent: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(in: proposal.width, subviews: subviews)
        let height = zip(subviews, widths).map { subview, width in
            subview.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height
        }.max() ?? 0
        return CGSize(width: widths.reduce(0, +) + gaps(subviews), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(in: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func gaps(_ subviews: Subviews) -> CGFloat {
        spacing * CGFloat(max(0, subviews.count - 1))
    }

    /// Each chip's width in a row `available` wide; with no finite width proposed, each chip's content width.
    private func widths(in available: CGFloat?, subviews: Subviews) -> [CGFloat] {
        let content = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard let available, available.isFinite, !subviews.isEmpty else { return content }
        let bases = growsFromContent ? content : content.map { _ in 0 }
        let total = bases.reduce(0, +)
        let free = available - gaps(subviews) - total
        if free >= 0 || total == 0 {
            return bases.map { max(0, $0 + free / CGFloat(bases.count)) }
        }
        return bases.map { $0 + free * $0 / total }
    }
}
