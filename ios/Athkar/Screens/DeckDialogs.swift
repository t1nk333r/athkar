import SwiftUI

/// «مصدر الذكر ٢٠ وتفاصيله»: every detail of the item, the note (`noteIndex`) set apart by a rule.
struct SourceSheet: View {
    let number: Int
    let item: AdhkarItemContent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.readingMetrics) private var metrics

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(Array(item.details.enumerated()), id: \.offset) { offset, detail in
                        let isNote = offset == item.noteIndex
                        Text(detail)
                            .font(ReadingFont.detail(metrics.detailText))
                            .cssLineHeight(metrics.detailLineHeight, size: metrics.detailText, face: .system)
                            .foregroundStyle(palette.reference)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, isNote ? 12 : 0)
                            .overlay(alignment: .top) {
                                if isNote { Rule() }
                            }
                    }
                }
                .padding()
            }
            .background(palette.background)
            .navigationTitle("مصدر الذكر \(ArabicFormat.number(number)) وتفاصيله")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
            }
        }
    }
}

/// «ما الذي تريد إعادته؟»: the scoped reset picker shared by both PWAs.
struct ResetScopeSheet: View {
    let choose: (ResetScope) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ما الذي تريد إعادته؟")
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text("اختر نطاق الإعادة. لا يُرسل شيء خارج هذا الجهاز.")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 6)
                .padding(.bottom, 8)
            ForEach(ResetScope.allCases) { scope in
                if scope != ResetScope.allCases.first { Rule() }
                Button {
                    choose(scope)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scope.title).font(.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                        Text(scope.detail).font(.footnote).foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reset.\(scope)")
            }
            Button("إلغاء") { dismiss() }
                .buttonStyle(DialogButtonStyle(palette: palette))
                .accessibilityIdentifier("reset.cancel")
                .padding(.top, 12)
        }
        .padding(20)
        .fittedSheet(background: palette.background)
    }
}

/// The completion dialog: «اكتملت أذكار الصباح بحمد الله», «تمت الرقية بحمد الله», or a sura's. A completion without a
/// primary action shows its dismiss button alone.
struct CompletionSheet: View {
    let completion: DeckCompletion
    let primary: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 14) {
            Text("✓")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(palette.completed)
                .accessibilityHidden(true)
            Text(completion.title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("completion.title")
            Text(completion.message)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            if let time = completion.time {
                Text(time)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.completed)
                    .accessibilityIdentifier("completion.time")
            }
            HStack(spacing: 10) {
                Button(completion.dismissTitle) { dismiss() }
                    .buttonStyle(DialogButtonStyle(palette: palette))
                    .accessibilityIdentifier("completion.dismiss")
                if let title = completion.primaryTitle {
                    Button(title, action: primary)
                        .buttonStyle(DialogButtonStyle(palette: palette, primary: true))
                        .accessibilityIdentifier("completion.primary")
                }
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .fittedSheet(background: palette.background)
    }
}

/// `.dialog-button` (outlined) and `.dialog-button.primary` (filled with the accent).
struct DialogButtonStyle: ButtonStyle {
    let palette: Palette
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(primary ? palette.onAccent : palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Corner.box.fill(primary ? palette.accent : .clear))
            .overlay {
                if !primary { Corner.box.strokeBorder(palette.border) }
            }
            .contentShape(Corner.box)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct FittedSheet: ViewModifier {
    let background: Color
    @State private var height: CGFloat = 360

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(background)
            .presentationDetents([.height(height)])
    }
}

extension View {
    /// A sheet as tall as its content, like the PWAs' centred `<dialog>`s.
    func fittedSheet(background: Color) -> some View {
        modifier(FittedSheet(background: background))
    }
}
