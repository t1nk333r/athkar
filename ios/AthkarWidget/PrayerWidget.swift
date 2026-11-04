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

/// The prayer whose adhan sounded within the last half hour, then the next prayer (``PrayerWidgetSnapshot``), with a
/// live countdown to the next adhan, or to the current prayer's iqama until it is due. The times are the app's
/// (``PrayerWidgetStore``); without them the widget asks for the app to be opened.
struct PrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "prayer", provider: PrayerTimelineProvider()) { entry in
            PrayerWidgetView(entry: entry)
        }
        .configurationDisplayName("الصلاة")
        .description("تعرض الصلاة القادمة والوقت الباقي على أذانها، ثم الصلاة الحالية والوقت الباقي على إقامتها.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct PrayerTimelineEntry: TimelineEntry {
    let date: Date
    let state: PrayerWidgetState?
    let zone: TimeZone
}

struct PrayerTimelineProvider: TimelineProvider {
    /// Entries in one timeline: about two days of prayers, each with its adhan, iqama and the end of its window.
    static let entryLimit = 32

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
            iqama: now.addingTimeInterval(10 * 60), start: now.addingTimeInterval(-10 * 60)), zone: .current)
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
                // The countdown's ring has a track of its own.
                if family == .accessoryCircular && countdown == nil { AccessoryWidgetBackground() }
            }
            // «اليوم», where the prayer is recorded (spec/routes.md).
            .widgetURL(URL(string: "athkar://prayers"))
    }

    /// What the widget counts down to at the entry's date, as the app's counters do (``PrayerCountdown``): the next
    /// adhan, or the current prayer's iqama until it is due. `nil` once the iqama is due, and for a current prayer
    /// without one. The interval runs from when the widget began showing the prayer, which the ring drains from.
    private var countdown: Countdown? {
        guard let state = entry.state else { return nil }
        switch state.phase {
        case .next:
            return Countdown(event: .adhan, from: state.start, now: entry.date, to: state.adhan)
        case .current:
            guard let iqama = state.iqama, iqama > entry.date else { return nil }
            return Countdown(event: .iqama, from: state.start, now: entry.date, to: iqama)
        }
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
                if let countdown {
                    Text("\(countdown.event == .iqama ? "الإقامة " : "")بعد \(countdown.timer)")
                        .monospacedDigit()
                } else if let iqama = state.iqama {
                    Text("الإقامة \(time(iqama))")
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
                if let countdown {
                    // «العصر بعد ١:٢٣:٤٥», «إقامة العصر بعد ٩:٥٩».
                    Text("\(Self.title(countdown, state.prayer)) بعد \(countdown.timer)")
                        .monospacedDigit()
                } else {
                    Text("\(Self.name(state.prayer)) الآن")
                }
            } else {
                Text("افتح التطبيق لعرض المواقيت")
            }
        }
    }

    private var circular: some View {
        Group {
            if let state = entry.state, let countdown {
                // A ring that drains to the adhan or iqama, around the prayer and the time left.
                ProgressView(timerInterval: countdown.interval, countsDown: true) {
                    Text(Self.title(countdown, state.prayer))
                } currentValueLabel: {
                    VStack(spacing: 0) {
                        Text(countdown.event == .iqama ? "الإقامة" : Self.name(state.prayer))
                            .font(.caption2)
                        countdown.timer
                            .font(.caption.bold())
                            .monospacedDigit()
                    }
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                }
                .progressViewStyle(.circular)
                .widgetAccentable()
            } else if let state = entry.state {
                VStack(spacing: 0) {
                    Text("الآن")
                        .font(.caption2)
                    Text(Self.name(state.prayer))
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

    /// An adhan or iqama the widget counts down to, from when the widget began showing its prayer.
    struct Countdown {
        let event: PrayerCountdown.Event
        let interval: ClosedRange<Date>

        /// From `start`, or `now` when there is none; never later than `now` or than `target`.
        init(event: PrayerCountdown.Event, from start: Date?, now: Date, to target: Date) {
            self.event = event
            let from = min(start ?? now, now)
            interval = from...max(from, target)
        }

        /// The time left, ticking each second: «١:٢٣:٤٥», «٩:٥٩».
        var timer: Text {
            Text(timerInterval: interval, countsDown: true)
        }
    }

    /// As the app writes it: «٥:٠٣ م» (ArabicFormat.time).
    private func time(_ instant: Date) -> String {
        var style = Date.FormatStyle(locale: Locale(identifier: "ar-EG")).hour().minute()
        style.timeZone = entry.zone
        return instant.formatted(style)
    }

    /// «العصر» before its adhan, «إقامة العصر» before its iqama.
    static func title(_ countdown: Countdown, _ prayer: PrayerTime) -> String {
        switch countdown.event {
        case .adhan: name(prayer)
        case .iqama: "إقامة \(name(prayer))"
        }
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
