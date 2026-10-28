import SwiftUI

/// The chips that pick a deck's section (the ruqyah PWA's `.sura-picker`): one per sura, in pack order from the
/// right, the selected one raised, and «✓» on each sura complete today. The chips switch suras at any time; the
/// «التالي» lock applies only within a sura.
struct SectionChips: View {
    let model: any DeckModel

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4.8) {
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
                    .background(Capsule().fill(selected ? palette.accentSoft : palette.surfaceRaised))
                    .overlay(Capsule().strokeBorder(selected ? palette.accent.opacity(0.55) : palette.border))
                    .contentShape(Capsule())
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
