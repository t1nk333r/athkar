import AthkarCore
import Foundation
import XCTest
@testable import Athkar

/// The actual `AppModel` tracker: its dates are the prayer times' dates, and a new record captures the time and the
/// calculation profile أوقات الصلاة shows, once.
final class PrayerTrackerWiringTests: XCTestCase {
    @MainActor
    func testANewRecordCapturesThePrayerTimesZoneScheduleAndProfile() throws {
        let support = try NativeTestSupport()
        try support.database.location.save(LocationProfile(latitude: 24.71, longitude: 46.68, zoneId: "Asia/Riyadh",
                                                           source: .manual, updatedAt: nil))
        let app = try support.makeAppModel()
        let tracker = app.tracker
        XCTAssertEqual(tracker.zone.identifier, "Asia/Riyadh")
        XCTAssertEqual(tracker.today, SessionCalendar.localDate(of: Date(), in: app.prayer.zone))

        let dhuhr = PrayerOccurrence(date: tracker.today, prayer: .dhuhr)
        XCTAssertTrue(tracker.quickLog(dhuhr))
        let record = try XCTUnwrap(tracker.record(dhuhr))
        let expected = try XCTUnwrap(app.prayer.schedule(on: tracker.today)?[.dhuhr])
        XCTAssertEqual(try XCTUnwrap(record.scheduledAt).timeIntervalSince(expected), 0, accuracy: 0.001)
        XCTAssertEqual(record.zoneId, "Asia/Riyadh")
        XCTAssertEqual(record.profileVersion, app.prayer.settings.profileVersion)

        // A later method change keeps the record's own metadata.
        let profile = record.profileVersion
        app.prayer.setMethod(app.prayer.settings.method == .mwl ? .egyptian : .mwl)
        XCTAssertNotEqual(app.prayer.settings.profileVersion, profile)
        XCTAssertTrue(tracker.apply(.setTiming(.onTime), to: dhuhr))
        XCTAssertEqual(tracker.record(dhuhr)?.profileVersion, profile)
        XCTAssertNil(app.failure)
    }

    @MainActor
    func testWithoutALocationTheRecordHasNoScheduledTime() throws {
        let support = try NativeTestSupport()
        let app = try support.makeAppModel()
        XCTAssertNil(app.prayer.location)
        XCTAssertNil(app.prayer.upcoming())
        let fajr = PrayerOccurrence(date: app.tracker.today, prayer: .fajr)
        XCTAssertTrue(app.tracker.quickLog(fajr))
        let record = try XCTUnwrap(app.tracker.record(fajr))
        XCTAssertNil(record.scheduledAt)
        XCTAssertEqual(record.zoneId, TimeZone.current.identifier)
        XCTAssertEqual(try support.database.prayerRecords.records(on: fajr.date).count, 1)
    }

    /// The countdown and «اليوم» take the next prayer from the same civil-date rule.
    @MainActor
    func testTheCountdownUsesTheCivilDateRule() throws {
        let support = try NativeTestSupport()
        try support.database.location.save(LocationProfile(latitude: 40.71, longitude: -74.01,
                                                           zoneId: "America/New_York", source: .manual,
                                                           updatedAt: nil))
        let app = try support.makeAppModel()
        // 2026-11-01 05:30 UTC: 01:30 EDT, before the repeated hour ends; the next prayer is that day's Fajr.
        let now = Date(timeIntervalSince1970: 1_793_511_000)
        let upcoming = try XCTUnwrap(app.prayer.upcoming(now: now))
        XCTAssertEqual(upcoming.today, "2026-11-01")
        XCTAssertEqual(upcoming.date, "2026-11-01")
        XCTAssertEqual(upcoming.prayer, .fajr)
        XCTAssertEqual(app.prayer.nextPrayer(now: now), upcoming.next)
    }

    /// After Dhuhr's adhan the counters count to its iqama, 20 minutes later by default; a delay set to 0 sends them
    /// on to Asr, and the delays outlast a relaunch.
    @MainActor
    func testTheCountersCountToTheIqamaAfterTheAdhan() throws {
        let support = try NativeTestSupport()
        try support.database.location.save(LocationProfile(latitude: 24.71, longitude: 46.68, zoneId: "Asia/Riyadh",
                                                           source: .manual, updatedAt: nil))
        let app = try support.makeAppModel()
        XCTAssertEqual(app.prayer.iqama, IqamaDelays(fajr: 25, dhuhr: 20, asr: 20, maghrib: 10, isha: 20))
        let schedule = try XCTUnwrap(app.prayer.schedule(on: "2026-10-14"))
        let dhuhr = try XCTUnwrap(schedule.dhuhr)
        let now = dhuhr.addingTimeInterval(60)

        let iqama = try XCTUnwrap(app.prayer.countdown(now: now))
        XCTAssertEqual(iqama, PrayerCountdown(event: .iqama, prayer: .dhuhr, at: dhuhr.addingTimeInterval(20 * 60),
                                              date: "2026-10-14"))
        XCTAssertEqual(HomePrayerRow.title(iqama), "إقامة الظهر")
        XCTAssertEqual(PrayerNames.counting(to: iqama), "إقامة الظهر")

        app.prayer.setIqama(0, for: .dhuhr)
        let asr = try XCTUnwrap(app.prayer.countdown(now: now))
        XCTAssertEqual(asr, PrayerCountdown(event: .adhan, prayer: .asr, at: try XCTUnwrap(schedule.asr),
                                            date: "2026-10-14"))
        XCTAssertEqual(HomePrayerRow.title(asr), "أذان العصر")
        XCTAssertEqual(PrayerNames.counting(to: asr), "الصلاة القادمة: العصر")

        app.prayer.setIqama(30, for: .fajr)
        XCTAssertEqual(try support.makeAppModel().prayer.iqama, IqamaDelays(fajr: 30, dhuhr: 0))
        XCTAssertNil(app.failure)
    }

    /// The lock-screen widget gets the five times of yesterday and the coming days with their iqama, again when an
    /// iqama delay changes, and none without a location.
    @MainActor
    func testTheWidgetGetsTheTimesOfTheComingDays() throws {
        let support = try NativeTestSupport()
        let empty = RecordingPrayerWidget()
        _ = try support.makeAppModel(widget: empty)
        XCTAssertEqual(empty.published, [nil])

        try support.database.location.save(LocationProfile(latitude: 24.71, longitude: 46.68, zoneId: "Asia/Riyadh",
                                                           source: .manual, updatedAt: nil))
        let widget = RecordingPrayerWidget()
        let app = try support.makeAppModel(widget: widget)
        let snapshot = try XCTUnwrap(widget.published.last ?? nil)
        XCTAssertEqual(snapshot.zone, "Asia/Riyadh")
        XCTAssertEqual(snapshot.prayers.count, (PrayerWidgetSnapshot.days + 1) * 5)
        let dhuhr = try XCTUnwrap(app.prayer.schedule(dayOffset: 0)?.dhuhr)
        XCTAssertTrue(snapshot.prayers.contains(.init(prayer: .dhuhr, adhan: dhuhr,
                                                      iqama: dhuhr.addingTimeInterval(20 * 60))))

        app.prayer.setIqama(5, for: .dhuhr)
        let changed = try XCTUnwrap(widget.published.last ?? nil)
        XCTAssertTrue(changed.prayers.contains(.init(prayer: .dhuhr, adhan: dhuhr,
                                                     iqama: dhuhr.addingTimeInterval(5 * 60))))
        XCTAssertNil(app.failure)
    }
}
