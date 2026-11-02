import AthkarCore
import SwiftUI
import WidgetKit

/// The lock-screen widgets (MOBILE_APP_PLAN.md §14, "1.1 widgets").
@main
struct AthkarWidgets: WidgetBundle {
    var body: some Widget {
        PrayerWidget()
    }
}

/// The prayer whose adhan sounded within the last half hour, then the next prayer (``PrayerWidgetSnapshot``). The
/// times are the app's (``PrayerWidgetStore``); without them the widget asks for the app to be opened.
struct PrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "prayer", provider: PrayerTimelineProvider()) { entry in
            PrayerWidgetView(entry: entry)
        }
        .configurationDisplayName("الصلاة")
        .description("الصلاة الحالية نصف ساعة بعد أذانها، ثم الصلاة القادمة.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct PrayerTimelineEntry: TimelineEntry {
    let date: Date
    let state: PrayerWidgetState?
    let zone: TimeZone
}

struct PrayerTimelineProvider: TimelineProvider {
    /// Entries in one timeline: about two days of prayers.
    static let entryLimit = 24

    func placeholder(in context: Context) -> PrayerTimelineEntry {
        Self.sample
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerTimelineEntry) -> Void) {
        let entry = Self.entries(from: Date(), limit: 1)[0]
        completion(context.isPreview && entry.state == nil ? Self.sample : entry)
    }

    /// Read again after the last change it holds, and at least an hour on; within 15 minutes when it has no times,
    /// which the app may have written since or the locked phone may not have let it read.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerTimelineEntry>) -> Void) {
        let now = Date()
        let entries = Self.entries(from: now, limit: Self.entryLimit)
        let last = entries.last?.date ?? now
        let soonest = now.addingTimeInterval(entries.count == 1 && entries[0].state == nil ? 15 * 60 : 60 * 60)
        completion(Timeline(entries: entries, policy: .after(max(last, soonest))))
    }

    /// At least one entry.
    private static func entries(from now: Date, limit: Int) -> [PrayerTimelineEntry] {
        guard let snapshot = PrayerWidgetStore.load() else {
            return [PrayerTimelineEntry(date: now, state: nil, zone: .current)]
        }
        let zone = TimeZone(identifier: snapshot.zone) ?? .current
        return snapshot.timeline(from: now, limit: limit).map {
            PrayerTimelineEntry(date: $0.date, state: $0.state, zone: zone)
        }
    }

    /// The widget gallery's example: Asr's adhan ten minutes ago.
    private static var sample: PrayerTimelineEntry {
        let now = Date()
        return PrayerTimelineEntry(date: now, state: PrayerWidgetState(
            phase: .current, prayer: .asr, adhan: now.addingTimeInterval(-10 * 60),
            iqama: now.addingTimeInterval(10 * 60)), zone: .current)
    }
}

struct PrayerWidgetView: View {
    let entry: PrayerTimelineEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar-EG"))
            .containerBackground(for: .widget) {
                if family == .accessoryCircular { AccessoryWidgetBackground() }
            }
            // «اليوم», where the prayer is recorded (spec/routes.md).
            .widgetURL(URL(string: "athkar://prayers"))
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        default: rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let state = entry.state {
                Text(state.phase == .current ? "الصلاة الحالية" : "الصلاة القادمة")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Self.name(state.prayer)) \(time(state.adhan))")
                    .font(.headline)
                    .widgetAccentable()
                switch state.phase {
                case .current:
                    if let iqama = state.iqama { Text("الإقامة \(time(iqama))") }
                case .next:
                    Text("بعد \(Text(timerInterval: entry.date...max(entry.date, state.adhan), countsDown: true))")
                        .monospacedDigit()
                }
            } else {
                Text("مواقيت الصلاة")
                    .font(.headline)
                    .widgetAccentable()
                Text("افتح التطبيق وحدّد موقعك لعرضها.")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var inline: some View {
        Group {
            if let state = entry.state {
                Text(state.phase == .current ? "\(Self.name(state.prayer)) الآن"
                                             : "\(Self.name(state.prayer)) \(time(state.adhan))")
            } else {
                Text("افتح التطبيق لعرض المواقيت")
            }
        }
    }

    private var circular: some View {
        Group {
            if let state = entry.state {
                VStack(spacing: 0) {
                    Text(state.phase == .current ? "الآن" : Self.name(state.prayer))
                        .font(.caption2)
                    Text(state.phase == .current ? Self.name(state.prayer) : time(state.adhan))
                        .font(.caption.bold())
                        .widgetAccentable()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(2)
            } else {
                Image(systemName: "moon.stars")
                    .font(.title3)
            }
        }
    }

    /// As the app writes it: «٥:٠٣ م» (ArabicFormat.time).
    private func time(_ instant: Date) -> String {
        var style = Date.FormatStyle(locale: Locale(identifier: "ar-EG")).hour().minute()
        style.timeZone = entry.zone
        return instant.formatted(style)
    }

    /// The app's names (PrayerNames.name).
    static func name(_ prayer: PrayerTime) -> String {
        switch prayer {
        case .fajr: "الفجر"
        case .sunrise: "الشروق"
        case .dhuhr: "الظهر"
        case .asr: "العصر"
        case .maghrib: "المغرب"
        case .isha: "العشاء"
        }
    }
}
