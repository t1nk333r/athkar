import AthkarCore
import Foundation
import Testing

struct PrayerWidgetTests {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!

    /// Local `hour`:`minute` on 1970-01-0(`day` + 1) in Riyadh, which is UTC+3 all year.
    private func local(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: TimeInterval(((day * 24 + hour - 3) * 60 + minute) * 60))
    }

    private func schedule(day: Int, asrClamped: Bool = false, isha: (Int, Int) = (19, 30),
                          dhuhr: Date?? = nil) -> PrayerSchedule {
        PrayerSchedule(localDate: "1970-01-0\(day + 1)", zone: zone, fajr: local(day: day, 4),
                       sunrise: local(day: day, 5, 30), dhuhr: dhuhr ?? local(day: day, 12),
                       asr: asrClamped ? local(day: day, 18) : local(day: day, 15, 30), maghrib: local(day: day, 18),
                       isha: local(day: day, isha.0, isha.1), asrClamped: asrClamped)
    }

    private func snapshot(_ schedules: [PrayerSchedule], delays: IqamaDelays = IqamaDelays()) -> PrayerWidgetSnapshot {
        PrayerWidgetSnapshot(zone: zone, schedules: schedules, delays: delays)
    }

    private func state(_ phase: PrayerWidgetState.Phase, _ prayer: PrayerTime, _ adhan: Date,
                       iqama: Date?, since start: Date?) -> PrayerWidgetState {
        PrayerWidgetState(phase: phase, prayer: prayer, adhan: adhan, iqama: iqama, start: start)
    }

    @Test func theSnapshotHoldsTheFivePrayersWithTheirIqama() {
        let day = snapshot([schedule(day: 1)])
        #expect(day.zone == "Asia/Riyadh")
        #expect(day.format == PrayerWidgetSnapshot.currentFormat)
        #expect(day.prayers == [
            .init(prayer: .fajr, adhan: local(day: 1, 4), iqama: local(day: 1, 4, 25)),
            .init(prayer: .dhuhr, adhan: local(day: 1, 12), iqama: local(day: 1, 12, 20)),
            .init(prayer: .asr, adhan: local(day: 1, 15, 30), iqama: local(day: 1, 15, 50)),
            .init(prayer: .maghrib, adhan: local(day: 1, 18), iqama: local(day: 1, 18, 10)),
            .init(prayer: .isha, adhan: local(day: 1, 19, 30), iqama: local(day: 1, 19, 50)),
        ])
    }

    /// Sunrise is not a prayer; a clamped Asr and a time the schedule could not compute are left out, and a zero
    /// delay has no iqama.
    @Test func theSnapshotLeavesOutWhatTheCountersSkip() {
        let day = snapshot([schedule(day: 1, asrClamped: true, dhuhr: .some(nil))], delays: IqamaDelays(maghrib: 0))
        #expect(day.prayers.map(\.prayer) == [.fajr, .maghrib, .isha])
        #expect(day.prayers[1].iqama == nil)
    }

    @Test func theSnapshotRoundTripsAndRejectsAnotherFormat() throws {
        let days = snapshot([schedule(day: 0), schedule(day: 1)])
        #expect(PrayerWidgetSnapshot.decoded(from: try days.encoded()) == days)
        let other = try #require(String(data: try days.encoded(), encoding: .utf8))
            .replacingOccurrences(of: #""format":1"#, with: #""format":2"#)
        #expect(PrayerWidgetSnapshot.decoded(from: Data(other.utf8)) == nil)
        #expect(PrayerWidgetSnapshot.decoded(from: Data("{}".utf8)) == nil)
    }

    /// A prayer shows from its adhan for 30 minutes, then the next one does, from the end of that window.
    @Test func aPrayerIsCurrentForThirtyMinutesThenTheNextShows() {
        let days = snapshot([schedule(day: 1)])
        let dhuhr = state(.current, .dhuhr, local(day: 1, 12), iqama: local(day: 1, 12, 20), since: local(day: 1, 12))
        let asr = state(.next, .asr, local(day: 1, 15, 30), iqama: local(day: 1, 15, 50), since: local(day: 1, 12, 30))
        #expect(days.state(at: local(day: 1, 11, 59)) == state(.next, .dhuhr, local(day: 1, 12),
                                                               iqama: local(day: 1, 12, 20),
                                                               since: local(day: 1, 4, 30)))
        #expect(days.state(at: local(day: 1, 12)) == dhuhr)
        #expect(days.state(at: local(day: 1, 12, 29)) == dhuhr)
        #expect(days.state(at: local(day: 1, 12, 30)) == asr)
        #expect(days.state(at: local(day: 1, 15, 29)) == asr)
    }

    /// An Isha at 23:50 is still current at 00:10, from yesterday's times; then the next day's Fajr shows.
    @Test func anIshaAfterMidnightIsCurrentFromYesterday() {
        let days = snapshot([schedule(day: 1, isha: (23, 50)), schedule(day: 2)])
        #expect(days.state(at: local(day: 2, 0, 10))
                == state(.current, .isha, local(day: 1, 23, 50), iqama: local(day: 2, 0, 10),
                         since: local(day: 1, 23, 50)))
        #expect(days.state(at: local(day: 2, 0, 20))
                == state(.next, .fajr, local(day: 2, 4), iqama: local(day: 2, 4, 25), since: local(day: 2, 0, 20)))
    }

    /// When the next adhan comes within the window, the later prayer replaces the earlier at once.
    @Test func aLaterAdhanEndsTheWindowEarly() {
        let days = snapshot([schedule(day: 1, isha: (18, 20))])
        #expect(days.state(at: local(day: 1, 18, 20))?.prayer == .isha)
        #expect(days.state(at: local(day: 1, 18, 20))?.phase == .current)
    }

    /// The ring of the snapshot's first prayer has nowhere to start.
    @Test func theFirstPrayerHasNoStart() {
        let days = snapshot([schedule(day: 1)])
        #expect(days.state(at: local(day: 1, 3))?.prayer == .fajr)
        #expect(days.state(at: local(day: 1, 3))?.start == nil)
    }

    @Test func pastTheLastAdhanThereIsNoState() {
        let days = snapshot([schedule(day: 1)])
        #expect(days.state(at: local(day: 1, 20)) == nil)
        #expect(snapshot([]).state(at: local(day: 1, 12)) == nil)
    }

    /// The current prayer's iqama gets an entry of its own: the widget stops counting down to it there.
    @Test func theTimelineChangesAtEachAdhanIqamaAndWindowEnd() {
        let entries = snapshot([schedule(day: 1)]).timeline(from: local(day: 1, 11), limit: 100)
        #expect(entries.map(\.date) == [local(day: 1, 11), local(day: 1, 12), local(day: 1, 12, 20),
                                        local(day: 1, 12, 30), local(day: 1, 15, 30), local(day: 1, 15, 50),
                                        local(day: 1, 16), local(day: 1, 18), local(day: 1, 18, 10),
                                        local(day: 1, 18, 30), local(day: 1, 19, 30), local(day: 1, 19, 50),
                                        local(day: 1, 20)])
        #expect(entries.map { $0.state.map { "\($0.phase.rawValue) \($0.prayer.rawValue)" } ?? "none" }
                == ["next dhuhr", "current dhuhr", "current dhuhr", "next asr", "current asr", "current asr",
                    "next maghrib", "current maghrib", "current maghrib", "next isha", "current isha",
                    "current isha", "none"])
    }

    /// An iqama after the window ends falls on the next prayer's countdown, and a zero delay has no iqama: neither
    /// adds an entry.
    @Test func anIqamaOutsideTheWindowAddsNoEntry() {
        let entries = snapshot([schedule(day: 1)], delays: IqamaDelays(dhuhr: 45, asr: 0))
            .timeline(from: local(day: 1, 11), limit: 6)
        #expect(entries.map(\.date) == [local(day: 1, 11), local(day: 1, 12), local(day: 1, 12, 30),
                                        local(day: 1, 15, 30), local(day: 1, 16), local(day: 1, 18)])
    }

    @Test func theTimelineStopsAtItsLimit() {
        let entries = snapshot([schedule(day: 1), schedule(day: 2)]).timeline(from: local(day: 1, 11), limit: 3)
        #expect(entries.map(\.date) == [local(day: 1, 11), local(day: 1, 12), local(day: 1, 12, 20)])
    }

    /// Starting inside a window after the iqama: the first entry is the current prayer, the next is the end of its
    /// window.
    @Test func theTimelineStartsWithTheStateAtNow() {
        let entries = snapshot([schedule(day: 1)]).timeline(from: local(day: 1, 12, 25), limit: 2)
        #expect(entries.map(\.date) == [local(day: 1, 12, 25), local(day: 1, 12, 30)])
        #expect(entries.first?.state?.phase == .current)
    }

    @Test func anEmptySnapshotHasOneEntryWithoutAState() {
        #expect(snapshot([]).timeline(from: local(day: 1, 12), limit: 10)
                == [PrayerWidgetEntry(date: local(day: 1, 12), state: nil)])
    }
}
