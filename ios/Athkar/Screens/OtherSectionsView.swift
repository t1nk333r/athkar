import AthkarCore
import SwiftUI

/// The أذكار screen's three tabs: الصباح, المساء and أخرى.
enum HomeTab: String, CaseIterable, Identifiable, Sendable {
    case morning, evening, other

    var id: String { rawValue }
}

/// The sections of the أخرى tab, in list order. Those not ``isAvailable`` yet are listed as «قريبًا».
enum OtherSection: String, CaseIterable, Identifiable, Sendable {
    case ruqyah, suwar, salawat, tasbih, sleep, afterPrayer, waking, prayerTimes, qibla, today, calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ruqyah: "رقية القرين"
        case .suwar: "سور"
        case .salawat: "الصلاة على النبي ﷺ"
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
        case .salawat, .tasbih, .sleep, .afterPrayer, .waking, .prayerTimes, .qibla, .today, .calendar: nil
        }
    }

    /// Whether the section opens yet; the rest are listed as «قريبًا».
    var isAvailable: Bool {
        deck != nil || [.salawat, .tasbih, .prayerTimes, .qibla, .today, .calendar].contains(self)
    }

    /// The list's two groups, in list order: what is read and counted, then what follows the prayer times.
    static let groups = [
        OtherSectionGroup(title: "أوراد", sections: [.ruqyah, .suwar, .salawat, .tasbih, .sleep, .afterPrayer, .waking]),
        OtherSectionGroup(title: "الصلاة", sections: [.prayerTimes, .qibla, .today, .calendar]),
    ]
}

struct OtherSectionGroup: Identifiable, Sendable {
    let title: String
    let sections: [OtherSection]

    var id: String { title }
}

/// How the أخرى list lays out its sections: one to a row, or two to a row.
enum OtherLayout: String, CaseIterable, Identifiable, Sendable {
    case list, grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "قائمة"
        case .grid: "شبكة"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }
}

/// The أخرى tab: its sections in two groups, each section its title and its progress today or what it shows next. The
/// list puts one section on a row with that line at the end; the grid puts two on a row with the line under the title.
struct OtherSectionsView: View {
    let app: AppModel

    @Environment(\.palette) private var palette
    @State private var transfer: TransferImportModel?

    var body: some View {
        // Redrawn every minute, so the next prayer and the Friday window follow the clock. Scrolls only when the rows
        // do not fit (large text): a scroll view holds back quick taps on its rows.
        TimelineView(.everyMinute) { _ in
            ViewThatFits(in: .vertical) {
                list
                ScrollView { list }
            }
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
                switch app.otherLayout {
                case .list: rows(group.sections)
                case .grid: grid(group.sections)
                }
            }
            if app.offersWebImport {
                importOffer.padding(.top, 20)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func rows(_ sections: [OtherSection]) -> some View {
        ForEach(Array(sections.enumerated()), id: \.element) { index, section in
            row(section)
            if index < sections.count - 1 { Rule() }
        }
    }

    /// Two sections to a row, in list order from the leading edge, with a rule between the two and between rows.
    @ViewBuilder
    private func grid(_ sections: [OtherSection]) -> some View {
        let pairs = stride(from: 0, to: sections.count, by: 2).map { Array(sections[$0..<min($0 + 2, sections.count)]) }
        ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
            HStack(spacing: 0) {
                tile(pair[0]).padding(.trailing, 12)
                Rectangle().fill(pair.count > 1 ? palette.border : .clear).frame(width: 1).accessibilityHidden(true)
                if pair.count > 1 {
                    tile(pair[1]).padding(.leading, 12)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            // The rule and both tiles take the taller tile's height.
            .fixedSize(horizontal: false, vertical: true)
            if index < pairs.count - 1 { Rule() }
        }
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
        let shown = shown(section)
        return sectionButton(section, shown) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(section.title)
                    .font(.body)
                    .foregroundStyle(shown.available ? palette.textPrimary : palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if shown.complete {
                    Text("✓").font(.body).foregroundStyle(palette.completed)
                }
                Spacer(minLength: 8)
                Text(shown.subtitle)
                    .font(.footnote)
                    .foregroundStyle(shown.complete ? palette.completed : palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    private func tile(_ section: OtherSection) -> some View {
        let shown = shown(section)
        return sectionButton(section, shown) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(section.title)
                        .font(.body)
                        .foregroundStyle(shown.available ? palette.textPrimary : palette.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if shown.complete {
                        Text("✓").font(.body).foregroundStyle(palette.completed)
                    }
                }
                Text(shown.subtitle)
                    .font(.footnote)
                    .foregroundStyle(shown.complete ? palette.completed : palette.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
    }

    /// What a row or tile shows of its section today.
    private struct Shown {
        let available: Bool
        let complete: Bool
        let subtitle: String
    }

    private func shown(_ section: OtherSection) -> Shown {
        let deck = section.deck.map(app.deck)
        return Shown(available: section.isAvailable, complete: deck?.isDayComplete == true,
                     subtitle: subtitle(section, deck: deck))
    }

    /// A row or tile that opens its section, spoken the same in either layout.
    private func sectionButton<Label: View>(_ section: OtherSection, _ shown: Shown,
                                            @ViewBuilder label: () -> Label) -> some View {
        Button {
            guard shown.available else { return }
            app.ensureCurrentDay()
            app.otherSection = section
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .disabled(!shown.available)
        .accessibilityLabel(section.title + (!shown.available ? "، قريبًا" : shown.complete ? "، مكتملة اليوم" : ""))
        .accessibilityValue(shown.available ? shown.subtitle : "")
        .accessibilityIdentifier("other.\(section.rawValue)")
    }

    /// The deck's summary, «ليلة الجمعة» or «يوم الجمعة», today's «مسبحة» total, the next prayer, today's recorded
    /// prayers, the month, or «قريبًا».
    private func subtitle(_ section: OtherSection, deck: (any DeckModel)?) -> String {
        if let deck { return deck.listSummary.copy }
        if section == .salawat { return SalawatView.fridayPhase(app: app)?.title ?? "صيغتان" }
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
