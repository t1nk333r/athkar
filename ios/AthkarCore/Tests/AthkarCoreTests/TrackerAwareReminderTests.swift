import AthkarCore
import Foundation
import Testing

/// `spec/reminders/fixtures/tracker-aware.json` (NATIVE_APP_PLAN.md §7.5): the tracker's commands are applied, then
/// the planner gets the resulting states. Through the pure rules and through the repository on SQLite, which is where
/// the app reads them.
@Suite("Tracker-aware reminder fixtures")
struct TrackerAwareReminderTests {
    @Test(arguments: try TrackerAwareFixtures.cases())
    func recordedPrayersAreNotPlanned(_ fixture: TrackerAwareCase) throws {
        var records = Dictionary(uniqueKeysWithValues: fixture.records.map { ($0.occurrence, $0) })
        var previous: [PrayerOccurrence: PrayerEntry] = [:]
        for step in fixture.steps {
            if step.command == .clearDay {
                for record in try PrayerTracker.clearDay(step.date, records: Array(records.values),
                                                         context: step.context) {
                    records[record.occurrence] = record
                }
                continue
            }
            let occurrence = try step.occurrence()
            let existing = records[occurrence]
            let command = try step.command.domain(undoing: previous[occurrence])
            if case let .changed(record) = try PrayerTracker.apply(command, to: occurrence, existing: existing,
                                                                     context: step.context) {
                previous[occurrence] = existing?.entry ?? .unrecorded
                records[occurrence] = record
            }
        }
        try fixture.check(ReminderPlanner.prayerStates(records.values))
    }

    @Test(arguments: try TrackerAwareFixtures.cases())
    func repositoryRecordsAreNotPlanned(_ fixture: TrackerAwareCase) throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            for record in fixture.records { try record.insert(db) }
        }
        var previous: [PrayerOccurrence: PrayerEntry] = [:]
        for step in fixture.steps {
            if step.command == .clearDay {
                _ = try database.prayerRecords.clearDay(step.date, context: step.context)
                continue
            }
            let occurrence = try step.occurrence()
            let before = try database.prayerRecords.records(on: occurrence.date)
                .first { $0.prayerKey == occurrence.prayer }?.entry ?? .unrecorded
            let command = try step.command.domain(undoing: previous[occurrence])
            if case .changed = try database.prayerRecords.apply(command, to: occurrence, context: step.context) {
                previous[occurrence] = before
            }
        }
        // The app reads the horizon's dates: today and the six days after it.
        let today = SessionCalendar.localDate(of: fixture.now, in: fixture.zone)
        let last = try #require(LocalDate.adding(ReminderPlanner.horizonDays - 1, to: today))
        try fixture.check(ReminderPlanner.prayerStates(try database.prayerRecords.records(from: today, through: last)))
    }

    /// The budget keeps the earliest notifications and says how many it left out.
    @Test func budgetDropsTheFurthestAndCountsThem() throws {
        let fixture = try #require(try TrackerAwareFixtures.cases().first)
        let full = ReminderPlanner.makePlan(now: fixture.now, zone: fixture.zone, rules: fixture.rules,
                                            schedule: fixture.schedule, completeToday: [], firedToday: [])
        #expect(full.droppedByBudget == 0)
        let cut = ReminderPlanner.makePlan(now: fixture.now, zone: fixture.zone, rules: fixture.rules,
                                           schedule: fixture.schedule, completeToday: [], firedToday: [], budget: 10)
        #expect(cut.notifications == Array(full.notifications.prefix(10)))
        #expect(cut.droppedByBudget == full.notifications.count - 10)
    }
}

struct TrackerAwareCase: Sendable, CustomTestStringConvertible {
    var name: String
    var zone: TimeZone
    var now: Date
    var times: [String: String]
    var rules: [ReminderRule]
    var records: [PrayerRecord]
    var steps: [TransitionStep]
    var today: [String]
    var count: Int
    var absent: [String]
    var catchUp: [String]?

    var testDescription: String { name }

    /// The fixture's local times on every date.
    func schedule(_ date: String) -> PrayerSchedule? {
        func at(_ prayer: String) -> Date? {
            guard let time = times[prayer] else { return nil }
            let parts = (date.split(separator: "-") + time.split(separator: ":")).compactMap { Int($0) }
            guard parts.count == 5 else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2],
                                                      hour: parts[3], minute: parts[4]))
        }
        return PrayerSchedule(localDate: date, zone: zone, fajr: at("fajr"), sunrise: at("sunrise"),
                              dhuhr: at("dhuhr"), asr: at("asr"), maghrib: at("maghrib"), isha: at("isha"))
    }

    func check(_ states: [PrayerOccurrence: PrayerRecordState]) throws {
        let plan = ReminderPlanner.plan(now: now, zone: zone, rules: rules, schedule: schedule, completeToday: [],
                                        firedToday: [], prayerStates: states)
        let today = SessionCalendar.localDate(of: now, in: zone)
        #expect(plan.filter { $0.localDate == today }.map(\.id) == self.today, "\(name)")
        #expect(plan.count == count, "\(name)")
        let ids = Set(plan.map(\.id))
        #expect(absent.allSatisfy { !ids.contains($0) }, "\(name)")
        if let catchUp {
            #expect(plan.filter(\.isCatchUp).map(\.id) == catchUp, "\(name)")
        }
    }
}

enum TrackerAwareFixtures {
    private struct File: Decodable {
        struct Rule: Decodable {
            var kind: String
            var prayer: ReminderRule.PrayerKey?
            var period: Period?
            var offsetMinutes: Int?
        }

        struct Defaults: Decodable {
            var timeZone: String
            var now: String
            var times: [String: String]
            var rules: [Rule]
            var profileVersion: String
            var records: [FixtureRecord]
            var steps: [Step]
        }

        struct Step: Decodable {
            var command: FixtureCommand
            var date: String
            var prayer: ObligatoryPrayer?
            var now: String?
        }

        struct Case: Decodable {
            struct Input: Decodable {
                var now: String?
                var records: [FixtureRecord]?
                var steps: [Step]?
            }

            struct Expected: Decodable {
                var today: [String]
                var count: Int
                var absent: [String]
                var catchUp: [String]?
            }

            var name: String
            var input: Input
            var expected: Expected
        }

        var defaultInput: Defaults
        var cases: [Case]
    }

    static func cases() throws -> [TrackerAwareCase] {
        let file = try JSONDecoder().decode(
            File.self, from: Data(contentsOf: SessionsFixtures.remindersDirectory.appending(path: "tracker-aware.json")))
        let defaults = file.defaultInput
        let zone = try SessionsFixtures.timeZone(defaults.timeZone)
        let epoch = Date(timeIntervalSince1970: 0)
        let rules = try defaults.rules.map { rule -> ReminderRule in
            switch rule.kind {
            case "prayer":
                let key = try #require(rule.prayer)
                return .prayer(key, offsetMinutes: rule.offsetMinutes ?? 0, enabled: true, updatedAt: epoch)
            case "adhkar":
                return .adhkar(try #require(rule.period), enabled: true, updatedAt: epoch)
            default:
                throw FixtureFailure.malformed("rule \(rule.kind)")
            }
        }
        return try file.cases.map { fixture in
            let now = fixture.input.now ?? defaults.now
            let steps = (fixture.input.steps ?? defaults.steps).map { step in
                TransitionStep(command: step.command, date: step.date, prayer: step.prayer,
                               context: PrayerCommandContext(now: Instant.at(step.now ?? now), zone: zone,
                                                             scheduledAt: nil,
                                                             profileVersion: defaults.profileVersion))
            }
            return TrackerAwareCase(
                name: fixture.name, zone: zone, now: try SessionsFixtures.instant(now), times: defaults.times,
                rules: rules, records: (fixture.input.records ?? defaults.records).map(\.record), steps: steps,
                today: fixture.expected.today, count: fixture.expected.count, absent: fixture.expected.absent,
                catchUp: fixture.expected.catchUp)
        }
    }
}
