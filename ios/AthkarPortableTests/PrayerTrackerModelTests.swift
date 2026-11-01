import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

/// The clock, zone and metadata a test's tracker reads, changeable between commands.
@MainActor
private final class TrackerHarness {
    let support: PortableTestSupport
    var now = at("2026-10-30T15:00:00.000Z")
    var zone = TimeZone(identifier: "Asia/Riyadh")!
    var profile = "umm-al-qura/standard/twilight-angle/0,0,0,0,0,0"
    let scheduled = at("2026-10-30T02:00:00.000Z")

    init() throws {
        support = try PortableTestSupport()
    }

    func makeModel() -> PrayerTrackerModel {
        PrayerTrackerModel(
            repository: support.database.prayerRecords, report: { XCTFail("Production database write failed: \($0)") },
            clock: { [unowned self] in (now, zone) },
            metadata: { [unowned self] _ in (scheduled, profile) })
    }
}

private func at(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text)!
}

private let fajr = PrayerOccurrence(date: "2026-10-30", prayer: .fajr)

/// «اليوم» and «التقويم»'s model on SQLite: quick log and its undo, the sheet's commands, Friday's choice, clearing a
/// day, and the calendar month.
final class PrayerTrackerModelTests: XCTestCase {
    @MainActor
    func testQuickLogRecordsOnceAndUndoLeavesTheRowUnrecorded() throws {
        let h = try TrackerHarness()
        let model = h.makeModel()
        XCTAssertEqual(model.today, "2026-10-30")
        XCTAssertEqual(model.entry(fajr), .unrecorded)

        XCTAssertTrue(model.quickLog(fajr))
        XCTAssertEqual(model.entry(fajr), PrayerEntry(state: .prayed, loggedAt: h.now))
        XCTAssertEqual(model.lastChange?.occurrence, fajr)
        XCTAssertEqual(TrackerText.change(fajr, entry: model.lastChange!.entry), "الفجر: صلّيتُها")

        let change = model.lastChange
        h.now = at("2026-10-30T15:00:05.000Z")
        XCTAssertFalse(model.quickLog(fajr), "a second log of the same prayer changes nothing")
        XCTAssertEqual(model.lastChange, change)

        model.undo()
        XCTAssertNil(model.lastChange)
        XCTAssertEqual(model.entry(fajr), .unrecorded)
        let record = try XCTUnwrap(model.record(fajr))
        XCTAssertEqual(record.scheduledAt, h.scheduled)
        XCTAssertEqual(record.profileVersion, h.profile)
        XCTAssertEqual(record.zoneId, "Asia/Riyadh")
        XCTAssertEqual(try h.support.database.prayerRecords.records(on: "2026-10-30").count, 1)
    }

    @MainActor
    func testUndoRestoresTheEntryBeforeTheLastChange() throws {
        let h = try TrackerHarness()
        let model = h.makeModel()
        model.quickLog(fajr)
        model.apply(.setTiming(.late), to: fajr)
        let late = model.entry(fajr)
        XCTAssertEqual(late.timing, .late)

        h.now = at("2026-10-30T16:00:00.000Z")
        model.apply(.markNotApplicable, to: fajr)
        XCTAssertEqual(model.entry(fajr), PrayerEntry(state: .notApplicable, loggedAt: h.now))
        model.undo()
        XCTAssertEqual(model.entry(fajr), late, "undo brings back the timing and the first logged time")
    }

    @MainActor
    func testMetadataIsCapturedOnceAndNeverRewritten() throws {
        let h = try TrackerHarness()
        let model = h.makeModel()
        model.quickLog(fajr)
        model.apply(.unrecord, to: fajr)
        h.profile = "mwl/hanafi/twilight-angle/0,0,0,0,0,0"
        h.zone = TimeZone(identifier: "Europe/London")!
        model.quickLog(fajr)
        let record = try XCTUnwrap(model.record(fajr))
        XCTAssertEqual(record.state, .prayed)
        XCTAssertEqual(record.zoneId, "Asia/Riyadh")
        XCTAssertEqual(record.profileVersion, "umm-al-qura/standard/twilight-angle/0,0,0,0,0,0")
    }

    @MainActor
    func testFridayDhuhrRecordsJumuahOrDhuhrInOneSlot() throws {
        let h = try TrackerHarness()
        let model = h.makeModel()
        let friday = PrayerOccurrence(date: "2026-10-30", prayer: .dhuhr)
        XCTAssertEqual(TrackerText.slot(friday, entry: .unrecorded), "الظهر أو الجمعة")

        XCTAssertTrue(model.quickLog(friday))
        XCTAssertNil(model.entry(friday).noon)
        XCTAssertTrue(model.apply(.record(noon: .jumuah), to: friday))
        XCTAssertEqual(model.entry(friday).noon, .jumuah)
        XCTAssertEqual(TrackerText.slot(friday, entry: model.entry(friday)), "الجمعة")
        XCTAssertTrue(model.apply(.record(noon: .dhuhr), to: friday))
        XCTAssertEqual(TrackerText.slot(friday, entry: model.entry(friday)), "الظهر")
        XCTAssertEqual(model.records(on: "2026-10-30").count, 1)

        let thursday = PrayerOccurrence(date: "2026-10-29", prayer: .dhuhr)
        XCTAssertEqual(TrackerText.slot(thursday, entry: .unrecorded), "الظهر")
        XCTAssertFalse(model.apply(.record(noon: .jumuah), to: thursday))
        XCTAssertNil(model.record(thursday))
    }

    @MainActor
    func testAFutureDayIsReadOnlyAndAPastDayIsEditable() throws {
        let h = try TrackerHarness()
        let model = h.makeModel()
        let tomorrow = PrayerOccurrence(date: "2026-10-31", prayer: .fajr)
        XCTAssertFalse(model.isEditable("2026-10-31"))
        XCTAssertFalse(model.quickLog(tomorrow))
        XCTAssertNil(model.record(tomorrow))
        XCTAssertNil(model.lastChange)

        let pastIsha = PrayerOccurrence(date: "2026-10-20", prayer: .isha)
        XCTAssertTrue(model.isEditable("2026-10-20"))
        XCTAssertTrue(model.quickLog(pastIsha))
        XCTAssertEqual(model.entry(pastIsha).state, .prayed)
    }

    @MainActor
    func testAfterMidnightTheRecordStaysOnYesterday() throws {
        let h = try TrackerHarness()
        h.now = at("2026-10-30T21:30:00.000Z")  // 00:30 on 31 October in Riyadh.
        let model = h.makeModel()
        XCTAssertEqual(model.today, "2026-10-31")
        let isha = PrayerOccurrence(date: "2026-10-30", prayer: .isha)
        XCTAssertTrue(model.quickLog(isha))
        XCTAssertEqual(model.records(on: "2026-10-30").count, 1)
        XCTAssertEqual(model.records(on: "2026-10-31").count, 0)
    }

    @MainActor
    func testClearDayKeepsTheRowsAndDropsTheUndo() throws {
        let h = try TrackerHarness()
        let model = h.makeModel()
        model.quickLog(fajr)
        model.apply(.markNotApplicable, to: PrayerOccurrence(date: "2026-10-30", prayer: .asr))
        XCTAssertNotNil(model.lastChange)
        XCTAssertTrue(model.clearDay("2026-10-30"))
        XCTAssertNil(model.lastChange)
        XCTAssertFalse(model.clearDay("2026-10-30"))
        XCTAssertFalse(model.clearDay("2026-10-31"), "a future day is refused")
        let records = try h.support.database.prayerRecords.records(on: "2026-10-30")
        XCTAssertEqual(records.map(\.state), [.unrecorded, .unrecorded])
        XCTAssertEqual(records.map(\.profileVersion), [h.profile, h.profile])
    }

    @MainActor
    func testRecordsPersistAcrossLaunches() throws {
        let h = try TrackerHarness()
        h.makeModel().quickLog(fajr)
        let relaunched = h.makeModel()
        XCTAssertEqual(relaunched.entry(fajr).state, .prayed)
        XCTAssertNil(relaunched.lastChange)
    }

    @MainActor
    func testTheMonthCountsPrayersAndCompletionsPlainly() throws {
        let h = try TrackerHarness()
        let model = h.makeModel()
        model.quickLog(fajr)
        model.apply(.markNotApplicable, to: PrayerOccurrence(date: "2026-10-30", prayer: .isha))
        let stamp = at("2026-10-30T05:00:00.000Z")
        try h.support.database.writer.write { db in
            try AdhkarDay(localDate: "2026-10-30", period: .morning, completedAt: stamp, completionOrigin: .counters)
                .insert(db)
            try RuqyahDay(localDate: "2026-10-12", completedAt: stamp, completionOrigin: .counters).insert(db)
        }
        let month = try XCTUnwrap(model.month("2026-10"))
        XCTAssertEqual(month.days.count, 31)
        XCTAssertEqual(month.totals, PrayerMonthTotals(prayed: 1, morning: 1, evening: 0, ruqyah: 1))
        let day = try XCTUnwrap(month.days.first { $0.date == "2026-10-30" })
        XCTAssertEqual([day.prayed, day.notApplicable, day.unrecorded, day.applicable], [1, 1, 3, 4])
        XCTAssertEqual(TrackerText.dayDescription(day), "الصلوات المسجّلة: ١ من ٤، أذكار الصباح")
        let quiet = try XCTUnwrap(month.days.first { $0.date == "2026-10-29" })
        XCTAssertEqual(TrackerText.dayDescription(quiet), "لا تسجيل للصلوات")
        XCTAssertEqual(TrackerText.dayDescription(month.days.last!), "لم يأتِ بعد")
        XCTAssertEqual(TrackerText.month("2026-10"), "أكتوبر ٢٠٢٦")
        XCTAssertEqual(TrackerText.totals(month.totals),
                       ["الصلوات المسجّلة: ١", "أذكار الصباح: يوم واحد", "أذكار المساء: ٠ أيام", "الرقية: يوم واحد"])
        XCTAssertTrue(try XCTUnwrap(model.month("2026-11")).days.allSatisfy(\.isFuture))
    }

    /// The tracker's words never call a prayer missed or a day failed.
    @MainActor
    func testWordingIsNeutral() throws {
        var words = PrayerRecordState.allCases.map(TrackerText.state)
        words += ([nil] + PrayerTiming.allCases.map(Optional.some)).map(TrackerText.timing)
        words += NoonPrayer.allCases.map(TrackerText.noon)
        words += ObligatoryPrayer.allCases.map(TrackerText.prayer)
        words += TrackerText.weekdays.map(\.name)
        words.append(TrackerText.todaySubtitle(prayed: 0, applicable: 5))
        words.append(TrackerText.dayDescription(PrayerDaySummary(
            date: "2026-10-29", weekday: 5, isFuture: false, prayed: 0, notApplicable: 0, morning: false,
            evening: false, ruqyah: false)))
        XCTAssertEqual(PrayerRecordState.allCases.map(TrackerText.state), ["لم تُسجَّل", "صلّيتُها", "لا تنطبق"])
        for word in words {
            for judgement in ["فائت", "فاتت", "فات", "تركت", "متروكة", "missed"] {
                XCTAssertFalse(word.contains(judgement), "\(word) contains \(judgement)")
            }
        }
    }

    /// Every write the reminders depend on tells them to replan: a quick log, its undo, a timing, the Friday choice,
    /// not applicable, a past day, a cleared day and a reload. A command that changes nothing or is refused does not.
    @MainActor
    func testEveryWriteAsksTheRemindersToReplan() throws {
        let h = try TrackerHarness()
        let model = h.makeModel()
        var writes = 0
        model.didWrite = { writes += 1 }
        let friday = PrayerOccurrence(date: "2026-10-30", prayer: .dhuhr)
        let yesterday = PrayerOccurrence(date: "2026-10-29", prayer: .isha)

        XCTAssertTrue(model.quickLog(fajr))
        XCTAssertEqual(writes, 1)
        XCTAssertFalse(model.quickLog(fajr))
        XCTAssertEqual(writes, 1, "nothing changed")
        model.undo()
        XCTAssertEqual(writes, 2)
        XCTAssertTrue(model.quickLog(fajr))
        XCTAssertTrue(model.apply(.setTiming(.onTime), to: fajr))
        XCTAssertTrue(model.apply(.record(noon: .jumuah), to: friday))
        XCTAssertTrue(model.apply(.markNotApplicable, to: PrayerOccurrence(date: "2026-10-30", prayer: .asr)))
        XCTAssertTrue(model.quickLog(yesterday))
        XCTAssertEqual(writes, 7)
        XCTAssertFalse(model.quickLog(PrayerOccurrence(date: "2026-10-31", prayer: .fajr)), "a future day is refused")
        XCTAssertEqual(writes, 7)
        XCTAssertTrue(model.clearDay("2026-10-30"))
        XCTAssertEqual(writes, 8)
        model.reload()
        XCTAssertEqual(writes, 9)
    }

    /// «سجّل الصلاة» records its own occurrence once, like the quick log, and offers no «تراجع».
    @MainActor
    func testLoggingFromAReminderRecordsOnceWithoutUndo() throws {
        let h = try TrackerHarness()
        let model = h.makeModel()
        let yesterday = PrayerOccurrence(date: "2026-10-29", prayer: .isha)
        XCTAssertTrue(model.logFromReminder(yesterday))
        XCTAssertEqual(model.entry(yesterday), PrayerEntry(state: .prayed, loggedAt: h.now))
        XCTAssertNil(model.lastChange)
        XCTAssertFalse(model.logFromReminder(yesterday))
        XCTAssertEqual(try h.support.database.prayerRecords.records(on: "2026-10-29").count, 1)
        XCTAssertFalse(model.logFromReminder(PrayerOccurrence(date: "2026-10-31", prayer: .fajr)))
    }

    /// The reminder planner's input: the recorded states from a date through the horizon, unrecorded rows included.
    @MainActor
    func testStatesCoverTheHorizonFromADate() throws {
        let h = try TrackerHarness()
        let model = h.makeModel()
        XCTAssertTrue(model.quickLog(fajr))
        XCTAssertTrue(model.apply(.markNotApplicable, to: PrayerOccurrence(date: "2026-10-30", prayer: .asr)))
        XCTAssertTrue(model.quickLog(PrayerOccurrence(date: "2026-10-29", prayer: .isha)))
        XCTAssertTrue(model.quickLog(PrayerOccurrence(date: "2026-10-30", prayer: .isha)))
        model.undo()
        XCTAssertEqual(model.states(from: "2026-10-30", days: 7), [
            fajr: .prayed,
            PrayerOccurrence(date: "2026-10-30", prayer: .asr): .notApplicable,
            PrayerOccurrence(date: "2026-10-30", prayer: .isha): .unrecorded,
        ])
        XCTAssertEqual(model.states(from: "2026-10-29", days: 1),
                       [PrayerOccurrence(date: "2026-10-29", prayer: .isha): .prayed])
        XCTAssertEqual(model.states(from: "2026-10-30", days: 0), [:])
    }
}
