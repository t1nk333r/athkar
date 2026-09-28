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

    /// The title's colour in the grid, one per section as in the adhkar apps the layout follows.
    var tint: Color {
        switch self {
        case .ruqyah: .teal
        case .sleep: .purple
        case .afterPrayer: .blue
        case .waking: .orange
        case .prayerTimes: .indigo
        case .qibla: .green
        }
    }

    /// Whether the section opens yet; the rest are listed as «قريبًا».
    var isAvailable: Bool { deck != nil || self == .prayerTimes }
}

/// The أخرى tab: a two-column grid of its sections, each title in its own colour, with its progress today where it
/// has a deck.
struct OtherSectionsView: View {
    let app: AppModel

    @Environment(\.palette) private var palette

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        // Scrolls only when the cells do not fit (large text): a scroll view holds back quick taps on its cells.
        ViewThatFits(in: .vertical) {
            grid
            ScrollView { grid }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(OtherSection.allCases) { section in
                cell(section)
            }
        }
        .padding(.top, 8)
    }

    private func cell(_ section: OtherSection) -> some View {
        let deck = section.deck.map(app.deck)
        let available = section.isAvailable
        let complete = deck?.isComplete == true
        return Button {
            guard available else { return }
            app.ensureCurrentDay()
            app.otherSection = section
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: section.icon)
                        .font(.footnote.weight(.bold))
                    Text(section.title)
                        .font(.subheadline.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    if complete {
                        Text("✓").font(.subheadline.weight(.heavy)).foregroundStyle(palette.completed)
                    }
                }
                .foregroundStyle(available ? section.tint : palette.textSecondary)
                Text(subtitle(section, deck: deck))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(complete ? palette.completed : palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14.4, style: .continuous).fill(palette.surface.opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: 14.4, style: .continuous).strokeBorder(palette.border))
            .contentShape(RoundedRectangle(cornerRadius: 14.4, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.55)
        .accessibilityLabel(section.title + (!available ? "، قريبًا" : complete ? "، مكتملة اليوم" : ""))
        .accessibilityValue(available ? subtitle(section, deck: deck) : "")
        .accessibilityIdentifier("other.\(section.rawValue)")
    }

    /// The deck's summary, the next prayer, or «قريبًا».
    private func subtitle(_ section: OtherSection, deck: (any DeckModel)?) -> String {
        if let deck { return deck.summary.copy }
        guard section == .prayerTimes else { return "قريبًا" }
        guard let next = app.prayer.nextPrayer() else {
            return app.prayer.location == nil ? "حدّد موقعك" : "لا مواقيت اليوم"
        }
        return "\(PrayerNames.name(next.prayer)) \(ArabicFormat.time(next.at, in: app.prayer.zone))"
    }
}
