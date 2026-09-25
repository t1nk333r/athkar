import SwiftUI

/// The أذكار screen's three tabs: الصباح, المساء and أخرى.
enum HomeTab: String, CaseIterable, Identifiable, Sendable {
    case morning, evening, other

    var id: String { rawValue }
}

/// The sections of the أخرى tab, in list order. Only those with a ``deck`` open yet; the rest are listed as «قريبًا».
enum OtherSection: String, CaseIterable, Identifiable, Sendable {
    case ruqyah, sleep, afterPrayer, waking, prayerTimes, qibla

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ruqyah: "رقية القرين"
        case .sleep: "أذكار النوم"
        case .afterPrayer: "أذكار بعد الصلاة"
        case .waking: "أذكار الاستيقاظ"
        case .prayerTimes: "أوقات الصلاة"
        case .qibla: "القبلة"
        }
    }

    var icon: String {
        switch self {
        case .ruqyah: "shield"
        case .sleep: "bed.double"
        case .afterPrayer: "hands.and.sparkles"
        case .waking: "sunrise"
        case .prayerTimes: "clock"
        case .qibla: "location.north.line"
        }
    }

    /// The deck the section opens, or `nil` while it is not built yet.
    var deck: DeckID? {
        switch self {
        case .ruqyah: .ruqyah
        case .sleep, .afterPrayer, .waking, .prayerTimes, .qibla: nil
        }
    }
}

/// The أخرى tab's list: one row per section, with its progress today where it has a deck.
struct OtherSectionsView: View {
    let app: AppModel

    @Environment(\.palette) private var palette

    var body: some View {
        // Scrolls only when the rows do not fit (large text): a scroll view holds back quick taps on its rows.
        ViewThatFits(in: .vertical) {
            list
            ScrollView { list }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(OtherSection.allCases.enumerated()), id: \.element) { index, section in
                if index > 0 {
                    Divider().overlay(palette.border)
                }
                row(section)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14.4, style: .continuous).fill(palette.surface.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 14.4, style: .continuous).strokeBorder(palette.border))
        .padding(.top, 8)
    }

    private func row(_ section: OtherSection) -> some View {
        let deck = section.deck.map(app.deck)
        return Button {
            guard section.deck != nil else { return }
            app.ensureCurrentDay()
            app.otherSection = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(deck == nil ? palette.textSecondary : palette.accentStrong)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.body.weight(.heavy))
                        .foregroundStyle(deck == nil ? palette.textSecondary : palette.textPrimary)
                    Text(deck?.summary.copy ?? "قريبًا")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(deck?.isComplete == true ? palette.completed : palette.textSecondary)
                }
                Spacer(minLength: 0)
                if deck?.isComplete == true {
                    Text("✓").font(.body.weight(.heavy)).foregroundStyle(palette.completed)
                }
                if deck != nil {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(deck == nil)
        .opacity(deck == nil ? 0.55 : 1)
        .accessibilityLabel(section.title + (deck.map { $0.isComplete ? "، مكتملة اليوم" : "" } ?? "، قريبًا"))
        .accessibilityValue(deck?.summary.copy ?? "")
        .accessibilityIdentifier("other.\(section.rawValue)")
    }
}
