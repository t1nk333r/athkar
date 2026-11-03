import SwiftUI

/// «أيقونة التطبيق» in الإعدادات: the two home-screen icons side by side, the current one ringed in the accent. Tapping
/// the other one changes the icon at once; iOS then shows its own alert.
struct AppIconSection: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var current = AppIconChoice.letter
    @State private var isChanging = false
    @State private var failed = false

    var body: some View {
        PageSection("أيقونة التطبيق") {
            HStack(spacing: 32) {
                ForEach(AppIconChoice.allCases) { choice in
                    option(choice)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        } footer: {
            Text("في iOS 18 وما بعده تتبع الأيقونة مظهر الشاشة الرئيسية: فاتح أو داكن أو ملوّن.")
        }
        .onAppear { current = .current }
        .alert("تعذّر تغيير الأيقونة", isPresented: $failed) {
            Button("حسنًا", role: .cancel) {}
        }
    }

    private func option(_ choice: AppIconChoice) -> some View {
        let selected = choice == current
        return Button {
            guard !selected, !isChanging else { return }
            isChanging = true
            Task {
                failed = !(await choice.apply())
                current = .current
                isChanging = false
            }
        } label: {
            VStack(spacing: 8) {
                preview(choice)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                    .overlay {
                        // The tile is the page's own paper, so a rule gives it its edge.
                        RoundedRectangle(cornerRadius: 13.5, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    }
                    .padding(4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(palette.accent, lineWidth: 2)
                            .opacity(selected ? 1 : 0)
                    }
                Text(choice.title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? palette.textPrimary : palette.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("أيقونة \(choice.title)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("settings.appIcon.\(choice.rawValue)")
    }

    /// The icon in the page's light or dark colours. An asset image in a list row keeps the version it first drew when
    /// the theme changes with الإعدادات open, so the version is picked here from the colour scheme.
    private func preview(_ choice: AppIconChoice) -> Image {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        return UIImage(named: choice.preview, in: nil, compatibleWith: traits).map(Image.init(uiImage:))
            ?? Image(choice.preview)
    }
}
