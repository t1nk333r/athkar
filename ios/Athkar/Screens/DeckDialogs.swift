import SwiftUI

/// «المصدر والتفاصيل — الذكر ٢٠»: every detail of the item, the note (`noteIndex`) set apart.
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
                            .cssLineHeight(metrics.detailLineHeight, size: metrics.detailText, quran: false)
                            .foregroundStyle(palette.reference)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(isNote ? 14 : 0)
                            .background {
                                if isNote {
                                    RoundedRectangle(cornerRadius: 8).fill(palette.accentSoft.opacity(0.45))
                                        .overlay(alignment: .leading) {
                                            Rectangle().fill(palette.divider).frame(width: 3.2)
                                        }
                                }
                            }
                    }
                }
                .padding()
            }
            .background(palette.background)
            .navigationTitle("المصدر والتفاصيل — الذكر \(ArabicFormat.number(number))")
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
        VStack(alignment: .leading, spacing: 14) {
            Text("ما الذي تريد إعادته؟")
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text("اختر نطاق الإعادة. لا يُرسل شيء خارج هذا الجهاز.")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
            ForEach(ResetScope.allCases) { scope in
                Button {
                    choose(scope)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scope.title).font(.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                        Text(scope.detail).font(.footnote).foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(palette.surfaceRaised))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.border))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("reset.\(scope)")
            }
            Button("إلغاء") { dismiss() }
                .buttonStyle(DialogButtonStyle(palette: palette))
                .accessibilityIdentifier("reset.cancel")
        }
        .padding(20)
        .fittedSheet(background: palette.background)
    }
}

/// The completion dialog: «اكتملت أذكار الصباح بحمد الله» or «تمت الرقية بحمد الله».
struct CompletionSheet: View {
    let completion: DeckCompletion
    let primary: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 14) {
            Text("✓")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(palette.completed)
                .frame(width: 51, height: 51)
                .background(Circle().fill(palette.completedSoft))
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
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(palette.completed)
                    .accessibilityIdentifier("completion.time")
            }
            HStack(spacing: 10) {
                Button(completion.dismissTitle) { dismiss() }
                    .buttonStyle(DialogButtonStyle(palette: palette))
                    .accessibilityIdentifier("completion.dismiss")
                Button(completion.primaryTitle, action: primary)
                    .buttonStyle(DialogButtonStyle(palette: palette, primary: true))
                    .accessibilityIdentifier("completion.primary")
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .fittedSheet(background: palette.background)
    }
}

/// `.dialog-button` and `.dialog-button.primary`.
struct DialogButtonStyle: ButtonStyle {
    let palette: Palette
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.heavy))
            .multilineTextAlignment(.center)
            .foregroundStyle(primary ? palette.accentStrong : palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14.4).fill(primary ? palette.accentSoft : palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 14.4).strokeBorder(
                primary ? palette.accent.mixed(0.55, with: palette.border) : palette.border))
            .contentShape(RoundedRectangle(cornerRadius: 14.4))
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
