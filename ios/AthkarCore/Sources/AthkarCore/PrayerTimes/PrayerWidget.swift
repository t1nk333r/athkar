import Foundation

/// What the lock-screen widget reads (MOBILE_APP_PLAN.md §14, "1.1 widgets"): the five adhan and iqama times of the
/// coming days, as the app computed them. It holds no location, history or settings, so the widget needs neither the
/// database nor the calculation.
public struct PrayerWidgetSnapshot: Codable, Equatable, Sendable {
    public struct Prayer: Codable, Equatable, Sendable {
        public let prayer: PrayerTime
        public let adhan: Date
        public let iqama: Date?

        public init(prayer: PrayerTime, adhan: Date, iqama: Date?) {
            self.prayer = prayer
            self.adhan = adhan
            self.iqama = iqama
        }
    }

    /// A widget reads only the format it was built for; any other shows as no snapshot.
    public static let currentFormat = 1
    /// Days the app writes, today included; the day before today is written too, for an Isha still within its
    /// window after midnight.
    public static let days = 30
    /// How long a prayer stays on the widget after its adhan, before the next one replaces it.
    public static let currentWindow: TimeInterval = 30 * 60

    public let format: Int
    /// The time zone the times are shown in.
    public let zone: String
    /// The five prayers of each day, by adhan.
    public let prayers: [Prayer]

    public init(zone: String, prayers: [Prayer]) {
        format = Self.currentFormat
        self.zone = zone
        self.prayers = prayers.sorted { $0.adhan < $1.adhan }
    }

    /// The prayers of `schedules` with their iqama under `delays`. A time a schedule could not compute is left out,
    /// and so is a clamped Asr, as in ``NextPrayer``.
    public init(zone: TimeZone, schedules: [PrayerSchedule], delays: IqamaDelays) {
        self.init(zone: zone.identifier, prayers: schedules.flatMap { schedule in
            NextPrayer.prayers.compactMap { prayer in
                guard !(prayer == .asr && schedule.asrClamped), let adhan = schedule[prayer] else { return nil }
                return Prayer(prayer: prayer, adhan: adhan, iqama: delays.iqama(of: prayer, in: schedule))
            }
        })
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    /// `nil` for unreadable data or another format.
    public static func decoded(from data: Data) -> PrayerWidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(Self.self, from: data), snapshot.format == currentFormat else {
            return nil
        }
        return snapshot
    }

    /// At `instant`: the prayer whose adhan sounded less than ``currentWindow`` ago, the latest if two did, else the
    /// next adhan. `nil` when the snapshot has no adhan left.
    public func state(at instant: Date) -> PrayerWidgetState? {
        if let current = prayers.last(where: { $0.adhan <= instant }),
           instant < current.adhan.addingTimeInterval(Self.currentWindow) {
            return PrayerWidgetState(phase: .current, prayer: current)
        }
        return prayers.first { $0.adhan > instant }.map { PrayerWidgetState(phase: .next, prayer: $0) }
    }

    /// The widget's timeline from `now`: the state at `now`, then one entry at each instant the state changes, an
    /// adhan or the end of a window, up to `limit` entries. When the snapshot runs out, its last entry has no state.
    public func timeline(from now: Date, limit: Int) -> [PrayerWidgetEntry] {
        var entries = [PrayerWidgetEntry(date: now, state: state(at: now))]
        let changes = Set(prayers.flatMap { [$0.adhan, $0.adhan.addingTimeInterval(Self.currentWindow)] })
            .filter { $0 > now }
            .sorted()
        for change in changes {
            guard entries.count < limit, let last = entries.last, last.state != nil else { break }
            let state = state(at: change)
            if state != last.state { entries.append(PrayerWidgetEntry(date: change, state: state)) }
        }
        return entries
    }
}

/// One prayer as the widget shows it.
public struct PrayerWidgetState: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        /// Its adhan sounded less than ``PrayerWidgetSnapshot/currentWindow`` ago.
        case current
        /// The next adhan.
        case next
    }

    public let phase: Phase
    public let prayer: PrayerTime
    public let adhan: Date
    public let iqama: Date?

    public init(phase: Phase, prayer: PrayerTime, adhan: Date, iqama: Date?) {
        self.phase = phase
        self.prayer = prayer
        self.adhan = adhan
        self.iqama = iqama
    }

    init(phase: Phase, prayer: PrayerWidgetSnapshot.Prayer) {
        self.init(phase: phase, prayer: prayer.prayer, adhan: prayer.adhan, iqama: prayer.iqama)
    }
}

/// A timeline entry: from `date`, the widget shows `state`, or asks for the app to be opened when it is `nil`.
public struct PrayerWidgetEntry: Equatable, Sendable {
    public let date: Date
    public let state: PrayerWidgetState?

    public init(date: Date, state: PrayerWidgetState?) {
        self.date = date
        self.state = state
    }
}
