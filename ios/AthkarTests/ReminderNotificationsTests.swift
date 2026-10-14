import AthkarCore
import Foundation
import UserNotifications
import XCTest
@testable import Athkar

/// The UserNotifications adapter alone: the requests iOS receives for `ReminderModel`'s plan, and what the model reads
/// back. Replan ordering runs on the same model in the portable `ReminderReplanTests`.
final class ReminderNotificationsTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!
    /// 2100-01-01 03:50 in Riyadh: Fajr's reminder, 10 minutes before the adhan.
    private let fajrReminder = Date(timeIntervalSince1970: 4_102_447_800)

    private func fajrRequest() -> ReminderRequest {
        let item = PlannedNotification(id: "prayer.fajr.2100-01-01", target: .prayer(.fajr), localDate: "2100-01-01",
                                       fireAt: fajrReminder, offsetMinutes: -10, isCatchUp: false)
        return ReminderRequest(item: item, ruleId: "prayer_fajr", now: fajrReminder.addingTimeInterval(-86_400),
                               zone: zone)
    }

    @MainActor
    func testCalendarRequestKeepsItsIDContentAndWallClock() throws {
        let request = UserNotificationCenterAdapter.request(fajrRequest())

        XCTAssertEqual(request.identifier, "prayer.fajr.2100-01-01")
        XCTAssertEqual(request.content.title, "صلاة الفجر")
        XCTAssertEqual(request.content.body, "بقي ١٠ دقائق على أذان الفجر.")
        XCTAssertEqual(request.content.threadIdentifier, "prayer")
        XCTAssertEqual(request.content.userInfo[ReminderModel.ruleIdKey] as? String, "prayer_fajr")
        XCTAssertEqual(request.content.userInfo[ReminderModel.targetKey] as? String, "prayer.fajr.2100-01-01")
        XCTAssertNotNil(request.content.sound)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        let components = trigger.dateComponents
        XCTAssertEqual(components.timeZone, zone)
        XCTAssertEqual([components.year, components.month, components.day, components.hour, components.minute,
                        components.second], [2100, 1, 1, 3, 50, 0])
        XCTAssertEqual(trigger.nextTriggerDate(), fajrReminder)
    }

    @MainActor
    func testCatchUpRequestFiresOneSecondAfterPlanning() throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        // The planner's catch-up instant, and one already past by the time the request is built.
        for fireAt in [now.addingTimeInterval(1), now.addingTimeInterval(-30)] {
            let item = PlannedNotification(id: "adhkar.morning.2100-01-01", target: .adhkar(.morning),
                                           localDate: "2100-01-01", fireAt: fireAt, offsetMinutes: 60, isCatchUp: true)
            let request = UserNotificationCenterAdapter.request(
                ReminderRequest(item: item, ruleId: "adhkar_morning", now: now, zone: zone))

            let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
            XCTAssertEqual(trigger.timeInterval, 1)
            XCTAssertFalse(trigger.repeats)
            XCTAssertEqual(request.identifier, "adhkar.morning.2100-01-01")
            XCTAssertEqual(request.content.title, "أذكار الصباح")
            XCTAssertEqual(request.content.body, "مرّت ساعة على صلاة الفجر. حان وقت أذكار الصباح.")
            XCTAssertEqual(request.content.threadIdentifier, "adhkar")
            XCTAssertEqual(request.content.userInfo[ReminderModel.ruleIdKey] as? String, "adhkar_morning")
        }
    }

    @MainActor
    func testPendingRequestReadsItsTitleAndNextFireDate() {
        let pending = UserNotificationCenterAdapter.pending(UserNotificationCenterAdapter.request(fajrRequest()))
        XCTAssertEqual(pending,
                       PendingReminder(id: "prayer.fajr.2100-01-01", title: "صلاة الفجر", fireAt: fajrReminder))
    }

    @MainActor
    func testAuthorizationStatusesMapToTheModelsThreeStates() {
        XCTAssertEqual(UserNotificationCenterAdapter.authorization(.notDetermined), .notDetermined)
        XCTAssertEqual(UserNotificationCenterAdapter.authorization(.denied), .denied)
        for status in [UNAuthorizationStatus.authorized, .provisional, .ephemeral] {
            XCTAssertEqual(UserNotificationCenterAdapter.authorization(status), .allowed)
        }
    }
}
