import AthkarCore
import Foundation
import GRDB
import UIKit
import XCTest
@testable import Athkar

/// The one router (spec/routes.md) on the actual `AppModel`, the quick-action inbox, and «حذف كل البيانات» with its
/// notification adapter.
final class RoutingAndDeleteAllTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    /// Flags of the test's own, so the import offer never reads or writes the app's.
    private func flags() -> UserDefaults {
        let suite = "athkar.tests.\(UUID().uuidString)"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    @MainActor
    private func makeApp(_ support: NativeTestSupport, center: RecordingReminderCenter = RecordingReminderCenter(),
                         diagnostics: MemoryDiagnosticsStore = MemoryDiagnosticsStore(),
                         widget: RecordingPrayerWidget = RecordingPrayerWidget(),
                         clock: @escaping () -> Date = { Date() }) throws -> AppModel {
        try AppModel(database: support.database, content: support.content, today: support.today,
                     notifications: center, reminderClock: clock, diagnosticsStore: diagnostics, widget: widget,
                     flags: flags())
    }

    // MARK: Routes

    @MainActor
    func testEachRouteOpensItsPlace() throws {
        let app = try makeApp(NativeTestSupport())
        app.tab = .other
        app.otherSection = .calendar
        let opened: [(AppRoute, HomeTab, OtherSection?, DeckID?)] = [
            (.morning, .morning, nil, .morning), (.evening, .evening, nil, .evening),
            (.ruqyah, .other, .ruqyah, .ruqyah), (.prayers, .other, .today, nil),
        ]
        for (index, (route, tab, section, deck)) in opened.enumerated() {
            app.open(route)
            XCTAssertEqual(app.tab, tab, "\(route)")
            if tab == .other { XCTAssertEqual(app.otherSection, section, "\(route)") }
            if let deck { XCTAssertEqual(app.selection, deck, "\(route)") }
            XCTAssertEqual(app.routesOpened, index + 1, "each route asks the home screen to close its sheets")
        }
        XCTAssertNil(app.failure)
    }

    @MainActor
    func testURLsOpenTheirRoutesAndOthersChangeNothing() throws {
        let app = try makeApp(NativeTestSupport())
        XCTAssertTrue(app.open(url: URL(string: "athkar://ruqyah")!))
        XCTAssertEqual(app.selection, .ruqyah)
        XCTAssertTrue(app.open(url: URL(string: "athkar://prayers")!))
        XCTAssertEqual(app.otherSection, .today)
        XCTAssertFalse(app.open(url: URL(string: "athkar://suwar")!))
        XCTAssertFalse(app.open(url: URL(string: "https://example.com/morning")!))
        XCTAssertEqual(app.otherSection, .today)
        XCTAssertEqual(app.routesOpened, 2)
        XCTAssertNil(app.pendingTransferFile)
    }

    /// An adhkar reminder opens its deck through the router; a prayer reminder opens أوقات الصلاة.
    @MainActor
    func testRemindersOpenTheirDeckOrPrayerTimes() throws {
        let app = try makeApp(NativeTestSupport())
        app.open(ReminderPayload(ruleId: "adhkar_evening", requestId: "adhkar.evening.2026-10-14"))
        XCTAssertEqual(app.selection, .evening)
        app.open(ReminderPayload(ruleId: "prayer_fajr", requestId: "prayer.fajr.2026-10-14"))
        XCTAssertEqual(app.tab, .other)
        XCTAssertEqual(app.otherSection, .prayerTimes)
        app.open(ReminderPayload(ruleId: "adhkar_morning", requestId: "adhkar.morning.2026-10-14"))
        XCTAssertEqual(app.selection, .morning)
        XCTAssertEqual(app.routesOpened, 3)
    }

    /// A quick action that arrives before the router waits for it; later ones open at once; unknown types do nothing.
    @MainActor
    func testQuickActionsWaitForTheRouter() {
        let inbox = QuickActions()
        var opened: [AppRoute] = []
        func item(_ type: String) -> UIApplicationShortcutItem {
            UIApplicationShortcutItem(type: type, localizedTitle: type)
        }
        XCTAssertTrue(inbox.perform(item(AppRoute.prayers.shortcutType)))
        XCTAssertEqual(opened, [])
        inbox.attach { opened.append($0) }
        XCTAssertEqual(opened, [.prayers])
        XCTAssertTrue(inbox.perform(item(AppRoute.morning.shortcutType)))
        XCTAssertFalse(inbox.perform(item("athkar.route.unknown")))
        XCTAssertEqual(opened, [.prayers, .morning])
    }

    /// Every shortcut item in Info.plist names a route, in the routes' order.
    func testInfoPlistDeclaresTheSchemeAndTheQuickActions() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let items = try XCTUnwrap(info["UIApplicationShortcutItems"] as? [[String: Any]])
        XCTAssertEqual(items.compactMap { $0["UIApplicationShortcutItemType"] as? String },
                       AppRoute.allCases.map(\.shortcutType))
        let types = try XCTUnwrap(info["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }, [AppRoute.scheme])
    }

    // MARK: «حذف كل البيانات»

    /// After a restore, a recorded prayer and a planned week of reminders, «حذف كل البيانات» leaves no user row, no
    /// pending request or banner of the app's, no diagnostics time, no times for the lock-screen widget, every section
    /// on its defaults, and the import offer back. The installed content versions stay.
    @MainActor
    func testDeleteAllLeavesNoRowsAndNothingPending() async throws {
        let riyadh = TimeZone(identifier: "Asia/Riyadh")!
        let support = try NativeTestSupport()
        let file = try Data(contentsOf: Self.repo.appendingPathComponent("spec/backup/examples/native.athkarbackup"))
        try BackupImporter(database: support.database, content: support.content.packs)
            .importFile(BackupFile.decode(file))
        try support.database.location.save(LocationProfile(latitude: 24.71, longitude: 46.68, zoneId: "Asia/Riyadh",
                                                           source: .manual, updatedAt: nil))
        try support.database.reminders.save(.prayer(.isha, offsetMinutes: 0, enabled: true,
                                                    updatedAt: Date(timeIntervalSince1970: 0)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = riyadh
        let midnight = calendar.startOfDay(for: AppModel.now())
        let center = RecordingReminderCenter()
        let diagnostics = MemoryDiagnosticsStore()
        let widget = RecordingPrayerWidget()
        let app = try makeApp(support, center: center, diagnostics: diagnostics, widget: widget,
                              clock: { midnight.addingTimeInterval(30 * 60) })
        XCTAssertNotNil(widget.published.last ?? nil, "the widget has the location's times")
        XCTAssertFalse(app.offersWebImport, "a launch with user data closes the offer")
        XCTAssertTrue(app.tracker.quickLog(PrayerOccurrence(date: app.tracker.today, prayer: .fajr)))
        await app.reminders.replanAndWait()
        XCTAssertFalse(center.pendingIDs.isEmpty)
        // Today in Riyadh, read before the deletion: deleting the location moves the tracker to the device's zone,
        // where the date differs between 21:00 and 24:00 UTC.
        let today = app.tracker.today
        center.delivered = [DeliveredReminder(id: "prayer.isha.\(today)", ruleId: "prayer_isha", date: Date())]
        app.tab = .other
        app.otherSection = .calendar

        let deleted = await app.deleteAllData()
        XCTAssertTrue(deleted)
        for table in AppDatabase.userTables {
            let count = try await support.database.writer.read {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)")
            }
            XCTAssertEqual(count, 0, table)
        }
        XCTAssertFalse(try support.database.contentInstalls.installs().isEmpty, "content_installs stays")
        XCTAssertTrue(center.pendingIDs.isEmpty, "nothing pending")
        XCTAssertTrue(center.removedDelivered.contains("prayer.isha.\(today)"), "banners removed")
        XCTAssertNil(diagnostics.lastReplanAt)
        XCTAssertNil(diagnostics.lastBackgroundRefreshAt)
        XCTAssertTrue(app.reminders.rules.isEmpty)
        XCTAssertNil(app.prayer.location)
        XCTAssertEqual(widget.published.last, .some(nil), "the widget's times are deleted")
        XCTAssertTrue(app.tracker.records(on: today).isEmpty)
        XCTAssertEqual(app.settings.theme, .system)
        XCTAssertEqual(app.tab, .morning)
        XCTAssertNil(app.otherSection)
        XCTAssertTrue(app.offersWebImport)
        XCTAssertNil(app.failure)

        // A replan afterwards still plans nothing.
        await app.reminders.replanAndWait()
        XCTAssertTrue(center.pendingIDs.isEmpty)
    }
}
