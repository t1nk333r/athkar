import AthkarCore
import SwiftUI

/// The أذكار screen's three tabs: الصباح, المساء and أخرى.
enum HomeTab: String, CaseIterable, Identifiable, Sendable {
    case morning, evening, other

    var id: String { rawValue }
}

/// The sections of the أخرى tab, in list order. Those not ``isAvailable`` yet are listed as «قريبًا».
enum OtherSection: String, CaseIterable, Identifiable, Sendable {
    case ruqyah, suwar, tasbih, sleep, afterPrayer, waking, prayerTimes, qibla, today, calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ruqyah: "رقية القرين"
        case .suwar: "سور"
        case .tasbih: "مسبحة"
        case .sleep: "أذكار النوم"
        case .afterPrayer: "أذكار بعد الصلاة"
        case .waking: "أذكار الاستيقاظ"
        case .prayerTimes: "أوقات الصلاة"
        case .qibla: "القبلة"
        case .today: "اليوم"
        case .calendar: "التقويم"
        }
    }

    /// The deck the section opens, if it is a deck.
    var deck: DeckID? {
        switch self {
        case .ruqyah: .ruqyah
        case .suwar: .suwar
        case .tasbih, .sleep, .afterPrayer, .waking, .prayerTimes, .qibla, .today, .calendar: nil
        }
    }

    /// Whether the section opens yet; the rest are listed as «قريبًا».
    var isAvailable: Bool {
        deck != nil || [.tasbih, .prayerTimes, .qibla, .today, .calendar].contains(self)
    }

    /// The list's two groups, in list order: what is read and counted, then what follows the prayer times.
    static let groups = [
        OtherSectionGroup(title: "أوراد", sections: [.ruqyah, .suwar, .tasbih, .sleep, .afterPrayer, .waking]),
        OtherSectionGroup(title: "الصلاة", sections: [.prayerTimes, .qibla, .today, .calendar]),
    ]
}

struct OtherSectionGroup: Identifiable, Sendable {
    let title: String
    let sections: [OtherSection]

    var id: String { title }
}

/// The أخرى tab: its sections as a list in two groups, each row its title and, at the end, its progress today or what it
/// shows next.
struct OtherSectionsView: View {
    let app: AppModel

    @Environment(\.palette) private var palette
    @State private var transfer: TransferImportModel?

    var body: some View {
        // Scrolls only when the rows do not fit (large text): a scroll view holds back quick taps on its rows.
        ViewThatFits(in: .vertical) {
            list
            ScrollView { list }
        }
        .sheet(item: $transfer) { model in
            TransferImportView(model: model)
                .environment(\.palette, palette)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(OtherSection.groups) { group in
                Text(group.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 18)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(group.sections.enumerated()), id: \.element) { index, section in
                    row(section)
                    if index < group.sections.count - 1 { Rule() }
                }
            }
            if app.offersWebImport {
                importOffer.padding(.top, 20)
            }
        }
        .padding(.horizontal, 4)
    }

    /// The first-launch offer (spec/routes.md "First launch"): on a fresh install with no user data, below the
    /// sections, until it is used or closed. Nothing waits on it.
    private var importOffer: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                transfer = app.makeTransferImport()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("استيراد من تطبيق الويب")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("إن كنت تستخدم «أذكار المسلم» على الويب، انقل تقدّمك إلى هذا الجهاز.")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("other.importOffer")
            Button {
                app.closeImportOffer()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("إخفاء")
            .accessibilityIdentifier("other.importOffer.close")
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rule() }
    }

    private func row(_ section: OtherSection) -> some View {
        let deck = section.deck.map(app.deck)
        let available = section.isAvailable
        let complete = deck?.isDayComplete == true
        return Button {
            guard available else { return }
            app.ensureCurrentDay()
            app.otherSection = section
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(section.title)
                    .font(.body)
                    .foregroundStyle(available ? palette.textPrimary : palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if complete {
                    Text("✓").font(.body).foregroundStyle(palette.completed)
                }
                Spacer(minLength: 8)
                Text(subtitle(section, deck: deck))
                    .font(.footnote)
                    .foregroundStyle(complete ? palette.completed : palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityLabel(section.title + (!available ? "، قريبًا" : complete ? "، مكتملة اليوم" : ""))
        .accessibilityValue(available ? subtitle(section, deck: deck) : "")
        .accessibilityIdentifier("other.\(section.rawValue)")
    }

    /// The deck's summary, today's «مسبحة» total, the next prayer, today's recorded prayers, the month, or «قريبًا».
    private func subtitle(_ section: OtherSection, deck: (any DeckModel)?) -> String {
        if let deck { return deck.listSummary.copy }
        if section == .tasbih { return app.tasbih.totalText }
        if section == .today {
            let today = app.tracker.today
            let records = app.tracker.records(on: today).values
            let notApplicable = records.filter { $0.state == .notApplicable }.count
            return TrackerText.todaySubtitle(prayed: records.filter { $0.state == .prayed }.count,
                                             applicable: ObligatoryPrayer.allCases.count - notApplicable)
        }
        if section == .calendar { return TrackerText.month(String(app.tracker.today.prefix(7))) }
        if section == .qibla {
            guard let location = app.prayer.location else { return "حدّد موقعك" }
            let place = GeoCoordinates(latitude: location.latitude, longitude: location.longitude)
            return "\(QiblaView.degrees(Qibla.bearing(from: place))) من الشمال"
        }
        guard section == .prayerTimes else { return "قريبًا" }
        guard let next = app.prayer.nextPrayer() else {
            return app.prayer.location == nil ? "حدّد موقعك" : "لا مواقيت اليوم"
        }
        return "\(PrayerNames.name(next.prayer)) \(ArabicFormat.time(next.at, in: app.prayer.zone))"
    }
}
