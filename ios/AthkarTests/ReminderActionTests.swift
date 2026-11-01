import AthkarCore
import Foundation
import UserNotifications
import XCTest
@testable import Athkar

/// The prayer reminders' «سجّل الصلاة» and the background refresh on the actual `AppModel`: the tracker write goes to
/// the reminder's own occurrence, and every write or refresh replans against what the centre holds.
final class ReminderActionTests: XCTestCase {
    private let riyadh = TimeZone(identifier: "Asia/Riyadh")!

    /// A Riyadh location, Isha's reminder on, and the reminders' clock at 00:30 of today there, so every prayer of
    /// today is still ahead whatever the time the test runs.
    @MainActor
    private func makeApp(center: RecordingReminderCenter) throws -> (AppModel, today: String, database: AppDatabase) {
        let support = try NativeTestSupport()
        try support.database.location.save(LocationProfile(latitude: 24.71, longitude: 46.68, zoneId: "Asia/Riyadh",
                                                           source: .manual, updatedAt: nil))
        try support.database.reminders.save(.prayer(.isha, offsetMinutes: 0, enabled: true,
                                                    updatedAt: Date(timeIntervalSince1970: 0)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = riyadh
        let midnight = calendar.startOfDay(for: AppModel.now())
        let app = try support.makeAppModel(notifications: center,
                                           reminderClock: { midnight.addingTimeInterval(30 * 60) })
        XCTAssertEqual(app.prayer.zone, riyadh)
        return (app, app.tracker.today, support.database)
    }

    /// The action records the occurrence its reminder names, yesterday's Isha here, not today's; it marks the reminder
    /// shown and returns only once the replan it started has finished.
    @MainActor
    func testRecordPrayerWritesThePayloadsOwnOccurrenceAndReplans() async throws {
        let center = RecordingReminderCenter()
        let (app, today, database) = try makeApp(center: center)
        let yesterday = try XCTUnwrap(LocalDate.adding(-1, to: today))
        await app.reminders.replanAndWait()
        let reads = center.pendingReads

        let payload = ReminderPayload(ruleId: "prayer_isha", requestId: "prayer.isha.\(yesterday)")
        let recorded = await app.recordPrayer(payload, shownAt: Date())
        XCTAssertTrue(recorded)
        XCTAssertNil(app.reminders.replanTask, "the replan finished before the action returned")
        XCTAssertGreaterThan(center.pendingReads, reads, "the action replanned")
        XCTAssertEqual(app.tracker.entry(PrayerOccurrence(date: yesterday, prayer: .isha)).state, .prayed)
        XCTAssertNil(app.tracker.record(PrayerOccurrence(date: today, prayer: .isha)), "today is untouched")
        XCTAssertNil(app.tracker.lastChange, "nothing to undo on «اليوم»")
        XCTAssertEqual(try database.reminders.lastShown(ruleId: "prayer_isha"),
                       SessionCalendar.localDate(of: Date(), in: riyadh), "the acted-on reminder was shown")

        // Sent twice, as iOS may redeliver it: one record.
        let again = await app.recordPrayer(payload, shownAt: Date())
        XCTAssertFalse(again)
        XCTAssertEqual(try app.tracker.records(on: yesterday).count, 1)
        // A payload that names no prayer occurrence writes nothing.
        let adhkar = await app.recordPrayer(ReminderPayload(ruleId: "adhkar_morning",
                                                            requestId: "adhkar.morning.\(today)"), shownAt: Date())
        XCTAssertFalse(adhkar)
        XCTAssertNil(app.failure)
    }

    /// Recording today's Isha from «اليوم» replans at once: its pending request and banner go, the next days keep theirs.
    @MainActor
    func testRecordingFromTodayDropsThePendingReminder() async throws {
        let center = RecordingReminderCenter()
        let (app, today, _) = try makeApp(center: center)
        await app.reminders.replanAndWait()
        let tomorrow = try XCTUnwrap(LocalDate.adding(1, to: today))
        XCTAssertTrue(center.pendingIDs.contains("prayer.isha.\(today)"))
        XCTAssertEqual(app.reminders.diagnostics.planned, ReminderPlanner.horizonDays)

        XCTAssertTrue(app.tracker.quickLog(PrayerOccurrence(date: today, prayer: .isha)))
        await app.reminders.replanTask?.value
        XCTAssertFalse(center.pendingIDs.contains("prayer.isha.\(today)"))
        XCTAssertTrue(center.pendingIDs.contains("prayer.isha.\(tomorrow)"))
        XCTAssertTrue(center.removedDelivered.contains("prayer.isha.\(today)"))
        XCTAssertEqual(app.reminders.diagnostics.planned, ReminderPlanner.horizonDays - 1)

        app.tracker.undo()
        await app.reminders.replanTask?.value
        XCTAssertTrue(center.pendingIDs.contains("prayer.isha.\(today)"), "undone, it is planned again")
    }

    /// A background refresh asks for the next one after Riyadh's next midnight, then replans and records its run.
    @MainActor
    func testBackgroundRefreshReplansAndAsksForTheNext() async throws {
        let center = RecordingReminderCenter()
        let (app, _, _) = try makeApp(center: center)
        let scheduler = RecordingRefreshScheduler()
        app.reminders.refreshScheduler = scheduler
        await app.reminders.replanAndWait()
        let reads = center.pendingReads

        await app.reminders.runBackgroundRefresh()
        XCTAssertNil(app.reminders.replanTask)
        XCTAssertGreaterThan(center.pendingReads, reads)
        XCTAssertEqual(center.pendingIDs.count, ReminderPlanner.horizonDays)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = riyadh
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1,
                                               to: calendar.startOfDay(for: AppModel.now())))
        XCTAssertEqual(scheduler.requests, [next.addingTimeInterval(300)])
        XCTAssertNotNil(app.reminders.diagnostics.lastBackgroundRefreshAt)
    }

    /// Prayer reminders carry «سجّل الصلاة», which runs in the background after the user unlocks; adhkar reminders
    /// keep their plain tap.
    @MainActor
    func testPrayerRemindersCarryTheRecordAction() throws {
        let categories = ReminderModel.categories
        XCTAssertEqual(categories.map(\.identifier), ["prayer"])
        let action = try XCTUnwrap(categories.first?.actions.first)
        XCTAssertEqual(action.identifier, "record-prayer")
        XCTAssertEqual(action.title, "سجّل الصلاة")
        XCTAssertTrue(action.options.contains(.authenticationRequired))
        XCTAssertFalse(action.options.contains(.foreground))

        let prayer = PlannedNotification(id: "prayer.isha.2100-01-01", target: .prayer(.isha),
                                         localDate: "2100-01-01", fireAt: Date(timeIntervalSince1970: 4_102_500_000),
                                         offsetMinutes: 0, isCatchUp: false)
        XCTAssertEqual(ReminderModel.content(prayer, ruleId: "prayer_isha").categoryIdentifier, "prayer")
        let adhkar = PlannedNotification(id: "adhkar.morning.2100-01-01", target: .adhkar(.morning),
                                         localDate: "2100-01-01", fireAt: Date(timeIntervalSince1970: 4_102_500_000),
                                         offsetMinutes: 60, isCatchUp: false)
        XCTAssertEqual(ReminderModel.content(adhkar, ruleId: "adhkar_morning").categoryIdentifier, "")
    }
}

/// A notification centre that holds what it is given, for the app-unit tests (the portable tests' controlled centre
/// is not in this target).
@MainActor
final class RecordingReminderCenter: ReminderNotificationCenter {
    private(set) var requests: [String: ReminderRequest] = [:]
    private(set) var removedDelivered: [String] = []
    private(set) var pendingReads = 0
    var delivered: [DeliveredReminder] = []

    var pendingIDs: Set<String> { Set(requests.keys) }

    func authorization() async -> ReminderModel.Authorization { .allowed }
    func requestAuthorization() async throws {}
    func deliveredNotifications() async -> [DeliveredReminder] { delivered }

    func pendingRequests() async -> [PendingReminder] {
        pendingReads += 1
        return requests.values.map { PendingReminder(id: $0.item.id, title: $0.item.id, fireAt: $0.item.fireAt) }
    }

    func removePendingRequests(withIdentifiers ids: [String]) {
        for id in ids { requests[id] = nil }
    }

    func removeDeliveredNotifications(withIdentifiers ids: [String]) {
        removedDelivered += ids
    }

    func add(_ request: ReminderRequest) async throws {
        requests[request.item.id] = request
    }
}

@MainActor
final class RecordingRefreshScheduler: ReminderRefreshScheduler {
    private(set) var requests: [Date] = []

    func submit(earliestBegin: Date) throws {
        requests.append(earliestBegin)
    }
}
