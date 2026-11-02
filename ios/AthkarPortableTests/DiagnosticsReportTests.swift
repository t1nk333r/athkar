import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

/// «التشخيص»: counts, times, the permission and versions, and nothing of the user's worship.
final class DiagnosticsReportTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!
    private let versions = [(pack: "adhkar", version: "1.2.0"), (pack: "ruqyah", version: "1.0.1"),
                            (pack: "suwar", version: "1.1.2")]

    @MainActor
    func testRowsShowCountsTimesPermissionAndVersions() {
        let replan = Date(timeIntervalSince1970: 1_793_520_000) // 2026-11-01 08:00 in Riyadh
        let diagnostics = ReminderModel.Diagnostics(
            planned: 35, droppedByBudget: 0, pending: 34, lastReplanAt: replan, lastBackgroundRefreshAt: nil,
            refreshRequest: .refused)
        let report = DiagnosticsReport(diagnostics: diagnostics, authorization: .allowed, zone: zone,
                                       contentVersions: versions,
                                       info: ["CFBundleShortVersionString": "1.3", "CFBundleVersion": "4"])
        let values = Dictionary(uniqueKeysWithValues: (report.reminders + report.content + report.app)
            .map { ($0.id, $0.value) })
        XCTAssertEqual(report.reminders.map(\.id), ["planned", "pending", "dropped", "horizon", "budget",
                                                    "authorization", "lastReplan", "lastRefresh", "refreshRequest"])
        XCTAssertEqual(values["planned"], "٣٥")
        XCTAssertEqual(values["pending"], "٣٤")
        XCTAssertEqual(values["dropped"], "٠")
        XCTAssertEqual(values["horizon"], "٧ أيام")
        XCTAssertEqual(values["budget"], "٦٤")
        XCTAssertEqual(values["authorization"], "مسموح")
        XCTAssertEqual(values["lastReplan"],
                       "\(ArabicFormat.shortDate(replan, in: zone)) \(ArabicFormat.time(replan, in: zone))")
        XCTAssertEqual(values["lastRefresh"], "لم يحدث بعد")
        XCTAssertEqual(values["refreshRequest"], "غير متاح على هذا الجهاز")
        XCTAssertEqual(report.content.map(\.id), ["content.adhkar", "content.ruqyah", "content.suwar"])
        XCTAssertEqual(report.content.map(\.value), ["1.2.0", "1.0.1", "1.1.2"])
        XCTAssertEqual(values["appVersion"], "1.3 (4)")
    }

    /// Before any pass, counts read «—»; the permission and the refresh read as not asked yet.
    @MainActor
    func testNothingYetReadsAsNotYet() {
        let report = DiagnosticsReport(diagnostics: ReminderModel.Diagnostics(), authorization: .notDetermined,
                                       zone: zone, contentVersions: [], info: [:])
        let values = Dictionary(uniqueKeysWithValues: report.reminders.map { ($0.id, $0.value) })
        XCTAssertEqual(values["planned"], "—")
        XCTAssertEqual(values["pending"], "—")
        XCTAssertEqual(values["authorization"], "لم يُطلب بعد")
        XCTAssertEqual(values["lastReplan"], "لم تحدث بعد")
        XCTAssertEqual(values["refreshRequest"], "لم يُطلب بعد")
        XCTAssertEqual(report.app.first?.value, "— (—)")
    }

    /// The report is built from the reminder diagnostics, the permission and versions alone: none of its inputs
    /// carries adhkar progress or a prayer record, and its words name no worship state.
    @MainActor
    func testTheReportHoldsNoWorshipData() {
        let fields = Mirror(reflecting: ReminderModel.Diagnostics()).children.compactMap(\.label)
        XCTAssertEqual(fields, ["planned", "droppedByBudget", "pending", "lastReplanAt", "lastBackgroundRefreshAt",
                                "refreshRequest"])
        let report = DiagnosticsReport(
            diagnostics: ReminderModel.Diagnostics(planned: 1, droppedByBudget: 0, pending: 1,
                                                   lastReplanAt: Date(timeIntervalSince1970: 0),
                                                   lastBackgroundRefreshAt: Date(timeIntervalSince1970: 0),
                                                   refreshRequest: .accepted(earliestBegin: Date())),
            authorization: .denied, zone: zone, contentVersions: versions, info: [:])
        let text = (report.reminders + report.content + report.app).flatMap { [$0.title, $0.value] }
            .joined(separator: " ")
        for word in ["صلّي", "مكتمل", "سُجّل", "تقدّم", "فائت", "لا تنطبق"] {
            XCTAssertFalse(text.contains(word), word)
        }
    }
}
