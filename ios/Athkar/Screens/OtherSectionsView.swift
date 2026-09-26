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

    /// The deck the section opens, if it is a deck.
    var deck: DeckID? {
        switch self {
        case .ruqyah: .ruqyah
        case .sleep, .afterPrayer, .waking, .prayerTimes, .qibla: nil
        }
    }

    /// Whether the section opens yet; the rest are listed as «قريبًا».
    var isAvailable: Bool { deck != nil || self == .prayerTimes }
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
        let available = section.isAvailable
        return Button {
            guard available else { return }
            app.ensureCurrentDay()
            app.otherSection = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(available ? palette.accentStrong : palette.textSecondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.body.weight(.heavy))
                        .foregroundStyle(available ? palette.textPrimary : palette.textSecondary)
                    Text(subtitle(section, deck: deck))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(deck?.isComplete == true ? palette.completed : palette.textSecondary)
                }
                Spacer(minLength: 0)
                if deck?.isComplete == true {
                    Text("✓").font(.body.weight(.heavy)).foregroundStyle(palette.completed)
                }
                if available {
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
        .disabled(!available)
        .opacity(available ? 1 : 0.55)
        .accessibilityLabel(section.title + (!available ? "، قريبًا" : deck?.isComplete == true ? "، مكتملة اليوم" : ""))
        .accessibilityValue(available ? subtitle(section, deck: deck) : "")
        .accessibilityIdentifier("other.\(section.rawValue)")
    }

    /// The deck's summary, the next prayer, or «قريبًا».
    private func subtitle(_ section: OtherSection, deck: (any DeckModel)?) -> String {
        if let deck { return deck.summary.copy }
        guard section == .prayerTimes else { return "قريبًا" }
        guard let next = app.prayer.nextPrayer() else {
            return app.prayer.location == nil ? "حدّد موقعك لعرض المواقيت" : "لا مواقيت لهذا اليوم في موقعك"
        }
        return "\(PrayerNames.name(next.prayer)) \(ArabicFormat.time(next.at, in: app.prayer.zone))"
    }
}
