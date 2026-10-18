import AthkarCore
import Foundation
import XCTest
@testable import Athkar

/// The actual `AppModel` reminder inputs, called at fixed instants as a reminder pass calls them: adhkar completion
/// holds back only the planner's own date, in the planner's zone at the pass's instant, and never the day before's
/// while the new day cannot be read. A renamed table is the real SQLite failure.
final class ReminderCompletionInputsTests: XCTestCase {
    @MainActor
    func testFailedRolloverInputsDoNotUseYesterdayCompletion() throws {
        let support = try NativeTestSupport()
        let app = try makeApp(support, zone: "Asia/Riyadh")
        XCTAssertTrue(app.adhkar.setManualCompletion(.morning, completed: true))
        XCTAssertTrue(app.adhkar.setManualCompletion(.evening, completed: true))
        try rename("adhkar_item_progress", to: "hidden_adhkar_item_progress", in: support.database)

        let inputs = try XCTUnwrap(app.reminders.inputs(noonTomorrow))
        XCTAssertEqual(app.adhkar.state.date, support.today, "the new day could not be read")
        XCTAssertTrue(app.adhkar.isComplete(.morning) && app.adhkar.isComplete(.evening))
        XCTAssertEqual(inputs.completeToday, [])
        XCTAssertEqual(inputs.zone.identifier, "Asia/Riyadh")
        XCTAssertNotNil(inputs.schedule(tomorrow))
        XCTAssertNotNil(app.failure)
        try rename("hidden_adhkar_item_progress", to: "adhkar_item_progress", in: support.database)
    }

    @MainActor
    func testMatchingPlannerDateSuppressesOnlyCompletedPeriods() throws {
        let support = try NativeTestSupport()
        let app = try makeApp(support, zone: "Asia/Riyadh")
        XCTAssertEqual(try XCTUnwrap(app.reminders.inputs(noonToday)).completeToday, [])
        XCTAssertTrue(app.adhkar.setManualCompletion(.evening, completed: true))
        XCTAssertEqual(try XCTUnwrap(app.reminders.inputs(noonToday)).completeToday, [.evening])
        XCTAssertTrue(app.adhkar.setManualCompletion(.evening, completed: false))
        XCTAssertEqual(try XCTUnwrap(app.reminders.inputs(noonToday)).completeToday, [])
        XCTAssertEqual(app.adhkar.state.date, support.today)
        XCTAssertNil(app.failure)
    }

    /// Noon UTC on the session's day is still that day in Riyadh and already the next one at UTC+14. The session is
    /// not rolled: the rollover follows the device, which is on the session's day.
    @MainActor
    func testInputsUsePlannerZoneAndCapturedInstant() throws {
        let cases: [(zone: String, completed: Set<Period>)] = [("Asia/Riyadh", [.evening]), ("Pacific/Kiritimati", [])]
        for (zone, completed) in cases {
            let support = try NativeTestSupport()
            let app = try makeApp(support, zone: zone)
            XCTAssertTrue(app.adhkar.setManualCompletion(.evening, completed: true), zone)
            let inputs = try XCTUnwrap(app.reminders.inputs(noonToday), zone)
            XCTAssertEqual(inputs.zone.identifier, zone)
            XCTAssertEqual(inputs.completeToday, completed, zone)
            XCTAssertEqual(app.adhkar.state.date, support.today, zone)
            XCTAssertNil(app.failure, zone)
        }
    }

    @MainActor
    func testRecoveredRolloverInputsUseCommittedCurrentDay() throws {
        let support = try NativeTestSupport()
        let app = try makeApp(support, zone: "Asia/Riyadh")
        XCTAssertTrue(app.adhkar.setManualCompletion(.morning, completed: true))
        try support.database.adhkar.markComplete(on: tomorrow, period: .evening, origin: .manual, completedAt: nil)
        try rename("adhkar_item_progress", to: "hidden_adhkar_item_progress", in: support.database)
        XCTAssertEqual(try XCTUnwrap(app.reminders.inputs(noonTomorrow)).completeToday, [])
        XCTAssertEqual(app.adhkar.state.date, support.today)

        try rename("hidden_adhkar_item_progress", to: "adhkar_item_progress", in: support.database)
        let inputs = try XCTUnwrap(app.reminders.inputs(noonTomorrow))
        XCTAssertEqual(app.adhkar.state.date, tomorrow)
        XCTAssertEqual(inputs.completeToday, [.evening])
    }

    /// An app on `support`'s database with a saved location in `zone`, which the planner uses.
    @MainActor
    private func makeApp(_ support: NativeTestSupport, zone: String) throws -> AppModel {
        // The rollover reads the device's zone: noon UTC keeps its date there from UTC−11 to UTC+11.
        XCTAssertEqual(SessionCalendar.localDate(of: noonToday, in: .current), support.today)
        XCTAssertEqual(SessionCalendar.localDate(of: noonTomorrow, in: .current), tomorrow)
        let (latitude, longitude) = zone == "Asia/Riyadh" ? (24.71, 46.68) : (1.87, -157.4)
        try support.database.location.save(LocationProfile(latitude: latitude, longitude: longitude, zoneId: zone,
                                                           source: .manual, updatedAt: nil))
        return try support.makeAppModel()
    }
}

private let tomorrow = "2026-10-15"
/// 2026-10-14 and 2026-10-15 at 12:00 UTC.
private let noonToday = Date(timeIntervalSince1970: 1_791_979_200)
private let noonTomorrow = Date(timeIntervalSince1970: 1_792_065_600)

/// Renames a table on the test's private database: every statement that reads the old name fails, no such table.
private func rename(_ table: String, to name: String, in database: AppDatabase) throws {
    try database.writer.write { db in
        try db.execute(sql: "ALTER TABLE \(table) RENAME TO \(name)")
    }
}
