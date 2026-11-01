import AthkarCore
import Foundation
import GRDB
import Testing

/// `spec/tracker/fixtures/*.json` (spec/tracker/tracker.md): the transitions through the pure rules and through the
/// repository on SQLite, the calendar summary through both, and the next prayer across DST with the real adapter.
@Suite("Tracker fixtures")
struct TrackerFixtureTests {
    // MARK: Transitions

    @Test(arguments: try TrackerFixtures.transitions())
    func transitionsFollowTheRules(_ fixture: TransitionCase) throws {
        var records = Dictionary(uniqueKeysWithValues: fixture.records.map { ($0.occurrence, $0) })
        var previous: [PrayerOccurrence: PrayerEntry] = [:]
        var results: [String] = []
        for step in fixture.steps {
            let context = step.context
            if step.command == .clearDay {
                do {
                    let changed = try PrayerTracker.clearDay(step.date, records: Array(records.values),
                                                             context: context)
                    for record in changed { records[record.occurrence] = record }
                    results.append(changed.isEmpty ? "unchanged" : "changed")
                } catch {
                    results.append("refused:\(error.rawValue)")
                }
                continue
            }
            let occurrence = try step.occurrence()
            let command = try step.command.domain(undoing: previous[occurrence])
            let existing = records[occurrence]
            do {
                switch try PrayerTracker.apply(command, to: occurrence, existing: existing, context: context) {
                case .unchanged:
                    results.append("unchanged")
                case let .changed(record):
                    previous[occurrence] = existing?.entry ?? .unrecorded
                    records[occurrence] = record
                    results.append("changed")
                }
            } catch {
                results.append("refused:\(error.rawValue)")
            }
        }
        #expect(results == fixture.results)
        #expect(records.values.sorted(by: TrackerFixtures.order) == fixture.expected)
    }

    @Test(arguments: try TrackerFixtures.transitions())
    func repositoryStoresTheSameRecords(_ fixture: TransitionCase) throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            for record in fixture.records { try record.insert(db) }
        }
        var previous: [PrayerOccurrence: PrayerEntry] = [:]
        var results: [String] = []
        for step in fixture.steps {
            do {
                if step.command == .clearDay {
                    results.append(try database.prayerRecords.clearDay(step.date, context: step.context)
                        ? "changed" : "unchanged")
                    continue
                }
                let occurrence = try step.occurrence()
                let before = try database.prayerRecords.records(on: occurrence.date)
                    .first { $0.prayerKey == occurrence.prayer }?.entry ?? .unrecorded
                let command = try step.command.domain(undoing: previous[occurrence])
                switch try database.prayerRecords.apply(command, to: occurrence, context: step.context) {
                case .unchanged: results.append("unchanged")
                case .changed:
                    previous[occurrence] = before
                    results.append("changed")
                }
            } catch let refusal as PrayerCommandRefusal {
                results.append("refused:\(refusal.rawValue)")
            }
        }
        #expect(results == fixture.results)
        #expect(try database.prayerRecords.records(from: "0000-01-01", through: "9999-12-31") == fixture.expected)
    }

    // MARK: Calendar

    @Test(arguments: try TrackerFixtures.calendar())
    func calendarCountsPlainly(_ fixture: CalendarCase) throws {
        let month = try #require(PrayerCalendar.month(
            fixture.month, today: fixture.today, marks: fixture.marks, morning: fixture.days(.morning),
            evening: fixture.days(.evening), ruqyah: Set(fixture.ruqyahDays)))
        #expect(month.days.map(DaySummary.init) == fixture.expectedDays)
        #expect(month.totals == fixture.expectedTotals)
    }

    @Test(arguments: try TrackerFixtures.calendar())
    func repositoryReadsTheCalendarFromTheTables(_ fixture: CalendarCase) throws {
        let database = try AppDatabase.inMemory()
        let stamp = Instant.at("2026-10-01T00:00:00.000Z")
        try database.writer.write { db in
            for mark in fixture.marks {
                try PrayerRecord(calculationDate: mark.date, prayerKey: mark.prayer, zoneId: "Asia/Riyadh",
                                 scheduledAt: nil, profileVersion: "mwl/standard/twilight-angle/0,0,0,0,0,0",
                                 state: mark.state, timing: nil, noonPrayer: nil,
                                 loggedAt: mark.state == .unrecorded ? nil : stamp, updatedAt: stamp).insert(db)
            }
            for day in fixture.adhkarDays {
                try AdhkarDay(localDate: day.date, period: day.period, completedAt: stamp, completionOrigin: .counters)
                    .insert(db)
            }
            for date in fixture.ruqyahDays {
                try RuqyahDay(localDate: date, completedAt: stamp, completionOrigin: .counters).insert(db)
            }
        }
        let month = try #require(try database.prayerRecords.month(fixture.month, today: fixture.today))
        #expect(month.days.map(DaySummary.init) == fixture.expectedDays)
        #expect(month.totals == fixture.expectedTotals)
    }

    /// The summary has no missed, failed or score value: its fields are exactly the plain counts the spec lists.
    @Test func calendarSummaryHasNoMissedValue() {
        let day = PrayerDaySummary(date: "2026-10-30", weekday: 6, isFuture: false, prayed: 0, notApplicable: 0,
                                   morning: false, evening: false, ruqyah: false)
        let fields = Mirror(reflecting: day).children.compactMap(\.label)
        #expect(fields == ["date", "weekday", "isFuture", "prayed", "notApplicable", "morning", "evening", "ruqyah"])
        #expect(Set(PrayerRecordState.allCases.map(\.rawValue)) == ["unrecorded", "prayed", "not_applicable"])
        #expect(day.unrecorded == 5 && day.applicable == 5 && !day.hasPrayerRecords)
    }

    // MARK: Next prayer

    @Test(arguments: try TrackerFixtures.nextPrayer())
    func nextPrayerAcrossDST(_ fixture: NextPrayerCase) throws {
        let zone = try #require(TimeZone(identifier: fixture.timeZone))
        let place = GeoCoordinates(latitude: fixture.latitude, longitude: fixture.longitude)
        let settings = CalculationSettings(method: .mwl, asrSchool: .standard)
        let port = AdhanPrayerTimes()
        let upcoming = try #require(NextPrayer.upcoming(after: fixture.now, in: zone) { date in
            try? port.schedule(on: date, at: place, in: zone, settings: settings)
        })
        #expect(upcoming.today == fixture.today)
        #expect(upcoming.prayer.rawValue == fixture.prayer)
        #expect(upcoming.date == fixture.date)
        #expect(abs(upcoming.at.timeIntervalSince(fixture.at)) <= fixture.tolerance,
                "\(upcoming.at) vs \(fixture.at)")
    }

    // MARK: Profile and local dates

    @Test func profileVersionSpellsTheCalculationProfile() {
        #expect(CalculationSettings(method: .ummAlQura).profileVersion
            == "umm-al-qura/standard/twilight-angle/0,0,0,0,0,0")
        let adjusted = CalculationSettings(method: .mwl, asrSchool: .hanafi, highLatitudeRule: .seventhOfTheNight,
                                           adjustments: PrayerAdjustments(fajr: -2, isha: 30), hijriOffset: 1)
        #expect(adjusted.profileVersion == "mwl/hanafi/seventh-of-the-night/-2,0,0,0,0,30")
    }

    @Test func localDatesMoveByCalendarDays() {
        #expect(LocalDate.adding(1, to: "2026-03-07") == "2026-03-08")
        #expect(LocalDate.adding(1, to: "2028-02-28") == "2028-02-29")
        #expect(LocalDate.adding(1, to: "2026-12-31") == "2027-01-01")
        #expect(LocalDate.adding(-1, to: "2026-03-01") == "2026-02-28")
        #expect(LocalDate.adding(1, to: "2026-02-29") == nil)
        #expect(LocalDate.weekday("2026-10-30") == 6)
        #expect(LocalDate.weekday("2026-11-01") == 1)
        #expect(LocalDate.weekday("1970-01-01") == 5)
        #expect(LocalDate.weekday("1969-12-27") == 7)
        #expect(LocalDate.isFriday("2026-10-23") && !LocalDate.isFriday("2026-10-24"))
        #expect(LocalDate.days(inMonth: "2028-02")?.count == 29)
        #expect(LocalDate.days(inMonth: "2026-02")?.last == "2026-02-28")
        #expect(LocalDate.days(inMonth: "2026-13") == nil)
        #expect(LocalDate.month(-1, from: "2026-01") == "2025-12")
        #expect(LocalDate.month(13, from: "2026-12") == "2028-01")
        #expect(LocalDate.month(1, from: "2026-1") == nil)
    }
}

// MARK: - Fixture shapes

/// A fixture record, read in the file's field names.
struct FixtureRecord: Decodable {
    var date: String
    var prayer: ObligatoryPrayer
    var zone: String
    var scheduledAt: String?
    var profileVersion: String
    var state: PrayerRecordState
    var timing: PrayerTiming?
    var noon: NoonPrayer?
    var loggedAt: String?
    var updatedAt: String

    var record: PrayerRecord {
        PrayerRecord(calculationDate: date, prayerKey: prayer, zoneId: zone, scheduledAt: scheduledAt.map(Instant.at),
                     profileVersion: profileVersion, state: state, timing: timing, noonPrayer: noon,
                     loggedAt: loggedAt.map(Instant.at), updatedAt: Instant.at(updatedAt))
    }
}

struct FixtureCommand: Decodable, Equatable {
    struct Entry: Decodable, Equatable {
        var state: PrayerRecordState
        var timing: PrayerTiming?
        var noon: NoonPrayer?
        var loggedAt: String?
    }

    var kind: String
    var noon: NoonPrayer?
    var timing: PrayerTiming?
    var entry: Entry?

    static let clearDay = FixtureCommand(kind: "clearDay")

    /// The domain command; `undo` restores the entry the occurrence had before its last change.
    func domain(undoing previous: PrayerEntry?) throws -> PrayerCommand {
        switch kind {
        case "record": return .record(noon: noon)
        case "unrecord": return .unrecord
        case "setTiming": return .setTiming(timing)
        case "markNotApplicable": return .markNotApplicable
        case "unmarkNotApplicable": return .unmarkNotApplicable
        case "restore":
            let entry = try #require(entry)
            return .restore(PrayerEntry(state: entry.state, timing: entry.timing, noon: entry.noon,
                                        loggedAt: entry.loggedAt.map(Instant.at)))
        case "undo": return .restore(try #require(previous, "undo without a change"))
        default: throw FixtureFailure.malformed("command \(kind)")
        }
    }
}

struct TransitionStep: Sendable {
    var command: FixtureCommand
    var date: String
    var prayer: ObligatoryPrayer?
    var context: PrayerCommandContext

    func occurrence() throws -> PrayerOccurrence {
        PrayerOccurrence(date: date, prayer: try #require(prayer))
    }
}

extension FixtureCommand: @unchecked Sendable {}

struct TransitionCase: Sendable, CustomTestStringConvertible {
    var name: String
    var records: [PrayerRecord]
    var steps: [TransitionStep]
    var results: [String]
    var expected: [PrayerRecord]

    var testDescription: String { name }
}

struct DaySummary: Decodable, Equatable {
    var date: String
    var weekday: Int
    var future: Bool
    var prayed: Int
    var notApplicable: Int
    var unrecorded: Int
    var applicable: Int
    var morning: Bool
    var evening: Bool
    var ruqyah: Bool

    init(_ day: PrayerDaySummary) {
        date = day.date
        weekday = day.weekday
        future = day.isFuture
        prayed = day.prayed
        notApplicable = day.notApplicable
        unrecorded = day.unrecorded
        applicable = day.applicable
        morning = day.morning
        evening = day.evening
        ruqyah = day.ruqyah
    }
}

struct CalendarCase: Sendable, CustomTestStringConvertible {
    struct AdhkarDate: Decodable {
        var date: String
        var period: Period
    }

    var name: String
    var today: String
    var month: String
    var marks: [PrayerStateMark]
    var adhkarDays: [AdhkarDate]
    var ruqyahDays: [String]
    var expectedDays: [DaySummary]
    var expectedTotals: PrayerMonthTotals

    var testDescription: String { name }

    func days(_ period: Period) -> Set<String> {
        Set(adhkarDays.filter { $0.period == period }.map(\.date))
    }
}

extension CalendarCase.AdhkarDate: @unchecked Sendable {}
extension DaySummary: @unchecked Sendable {}

struct NextPrayerCase: Sendable, CustomTestStringConvertible {
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZone: String
    var now: Date
    var today: String
    var prayer: String
    var date: String
    var at: Date
    var tolerance: TimeInterval

    var testDescription: String { name }
}

enum FixtureFailure: Error {
    case malformed(String)
}

enum TrackerFixtures {
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appending(path: "spec/tracker/fixtures")
    }()

    static func order(_ left: PrayerRecord, _ right: PrayerRecord) -> Bool {
        if left.calculationDate != right.calculationDate { return left.calculationDate < right.calculationDate }
        let prayers = ObligatoryPrayer.allCases
        return prayers.firstIndex(of: left.prayerKey)! < prayers.firstIndex(of: right.prayerKey)!
    }

    private struct TransitionFile: Decodable {
        struct Defaults: Decodable {
            var now: String
            var timeZone: String
            var profileVersion: String
            var scheduledAt: String?
            var records: [FixtureRecord]
        }

        struct Step: Decodable {
            var command: FixtureCommand
            var date: String
            var prayer: ObligatoryPrayer?
            var now: String?
            var timeZone: String?
            var profileVersion: String?
            var scheduledAt: String?
        }

        struct Case: Decodable {
            struct Input: Decodable {
                var now: String?
                var records: [FixtureRecord]?
                var steps: [Step]
            }

            struct Expected: Decodable {
                var results: [Result]
                var records: [FixtureRecord]
            }

            var name: String
            var input: Input
            var expected: Expected
        }

        /// `"changed"`, `"unchanged"` or `{"refused": reason}`, as `"refused:reason"`.
        struct Result: Decodable {
            var text: String

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) {
                    self.text = text
                } else {
                    text = "refused:" + (try container.decode([String: String].self)["refused"] ?? "")
                }
            }
        }

        var defaultInput: Defaults
        var cases: [Case]
    }

    static func transitions() throws -> [TransitionCase] {
        let file = try JSONDecoder().decode(TransitionFile.self,
                                            from: Data(contentsOf: directory.appending(path: "transitions.json")))
        let defaults = file.defaultInput
        return try file.cases.map { fixture in
            let caseNow = fixture.input.now ?? defaults.now
            let steps = try fixture.input.steps.map { step in
                let zoneName = step.timeZone ?? defaults.timeZone
                guard let zone = TimeZone(identifier: zoneName) else { throw FixtureFailure.malformed(zoneName) }
                // A step without `scheduledAt` takes the default, which is `null`.
                let context = PrayerCommandContext(
                    now: Instant.at(step.now ?? caseNow), zone: zone,
                    scheduledAt: (step.scheduledAt ?? defaults.scheduledAt).map(Instant.at),
                    profileVersion: step.profileVersion ?? defaults.profileVersion)
                return TransitionStep(command: step.command, date: step.date, prayer: step.prayer, context: context)
            }
            return TransitionCase(name: fixture.name, records: (fixture.input.records ?? defaults.records).map(\.record),
                                  steps: steps, results: fixture.expected.results.map(\.text),
                                  expected: fixture.expected.records.map(\.record))
        }
    }

    private struct CalendarFile: Decodable {
        struct Case: Decodable {
            struct Input: Decodable {
                struct Mark: Decodable {
                    var date: String
                    var prayer: ObligatoryPrayer
                    var state: PrayerRecordState
                }

                var today: String
                var month: String
                var records: [Mark]
                var adhkarDays: [CalendarCase.AdhkarDate]
                var ruqyahDays: [String]
            }

            struct Expected: Decodable {
                struct Totals: Decodable {
                    var prayed: Int
                    var morning: Int
                    var evening: Int
                    var ruqyah: Int
                }

                var days: [DaySummary]
                var totals: Totals
            }

            var name: String
            var input: Input
            var expected: Expected
        }

        var cases: [Case]
    }

    static func calendar() throws -> [CalendarCase] {
        let file = try JSONDecoder().decode(CalendarFile.self,
                                            from: Data(contentsOf: directory.appending(path: "calendar.json")))
        return file.cases.map { fixture in
            let input = fixture.input
            let totals = fixture.expected.totals
            return CalendarCase(
                name: fixture.name, today: input.today, month: input.month,
                marks: input.records.map { PrayerStateMark(date: $0.date, prayer: $0.prayer, state: $0.state) },
                adhkarDays: input.adhkarDays, ruqyahDays: input.ruqyahDays, expectedDays: fixture.expected.days,
                expectedTotals: PrayerMonthTotals(prayed: totals.prayed, morning: totals.morning,
                                                  evening: totals.evening, ruqyah: totals.ruqyah))
        }
    }

    private struct NextPrayerFile: Decodable {
        struct Case: Decodable {
            struct Input: Decodable {
                var latitude: Double
                var longitude: Double
                var timeZone: String
                var now: String
            }

            struct Expected: Decodable {
                var today: String
                var prayer: String
                var date: String
                var at: String
            }

            var name: String
            var input: Input
            var expected: Expected
        }

        var toleranceSeconds: Double
        var cases: [Case]
    }

    static func nextPrayer() throws -> [NextPrayerCase] {
        let file = try JSONDecoder().decode(NextPrayerFile.self,
                                            from: Data(contentsOf: directory.appending(path: "next-prayer.json")))
        return file.cases.map { fixture in
            NextPrayerCase(name: fixture.name, latitude: fixture.input.latitude, longitude: fixture.input.longitude,
                           timeZone: fixture.input.timeZone, now: Instant.at(fixture.input.now),
                           today: fixture.expected.today, prayer: fixture.expected.prayer, date: fixture.expected.date,
                           at: Instant.at(fixture.expected.at), tolerance: file.toleranceSeconds)
        }
    }
}
