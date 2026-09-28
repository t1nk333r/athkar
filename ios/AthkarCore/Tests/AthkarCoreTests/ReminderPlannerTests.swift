import AthkarCore
import Foundation
import Testing

/// `spec/reminders/fixtures/next-reminder-time.json`: the PWA's adhkar reminder timing, checked against the planner's
/// earliest notification per period. Today's times are the fixture's; later days come from Adhan, so they match within
/// the prayer-times gate (2 minutes, NATIVE_APP_PLAN.md §7.2 P1). A catch-up fires 1 s after planning where the PWA
/// waits 300 ms.
@Suite("Reminder fixtures")
struct ReminderFixtureTests {
    private struct Input: Decodable {
        let timeZone: String
        let now: String
        let notificationPermission: String
        let preferences: Preferences
        let collections: SessionCollections
        let state: SessionState
    }

    private struct Preferences: Decodable {
        struct Toggle: Decodable { let enabled: Bool }
        struct Location: Decodable { let latitude: Double; let longitude: Double }
        let morning: Toggle
        let evening: Toggle
        let calculationMethod: CalculationMethod
        let asrSchool: AsrSchool
        let location: Location?
        let lastShown: SessionPeriods<String?>
    }

    private struct Expected: Decodable {
        struct Scheduled: Decodable { let fireAt: String }
        struct Today: Decodable { let fajr: String; let asr: String }
        let todaySchedule: Today?
        let scheduled: SessionPeriods<Scheduled?>
    }

    @Test(arguments: try SessionsFixtures.cases("next-reminder-time.json", in: SessionsFixtures.remindersDirectory))
    func nextReminderTime(_ fixture: SessionsFixtureCase) throws {
        let input = try fixture.input(as: Input.self)
        let expected = try fixture.expected(as: Expected.self)
        let zone = try SessionsFixtures.timeZone(input.timeZone)
        let now = try SessionsFixtures.instant(input.now)
        let today = SessionCalendar.localDate(of: now, in: zone)

        // The app plans nothing without permission; the planner never sees the rules then.
        let rules = input.notificationPermission == "granted" ? [
            ReminderRule.adhkar(.morning, enabled: input.preferences.morning.enabled, updatedAt: now),
            ReminderRule.adhkar(.evening, enabled: input.preferences.evening.enabled, updatedAt: now),
        ] : []
        let settings = CalculationSettings(method: input.preferences.calculationMethod,
                                           asrSchool: input.preferences.asrSchool)
        let port = AdhanPrayerTimes()
        let plan = ReminderPlanner.plan(
            now: now, zone: zone, rules: rules,
            schedule: { date in
                guard let place = input.preferences.location else { return nil }
                // Today's Fajr and Asr are the PWA's own, so the millisecond boundary cases test the rules and not
                // the few seconds between the two solar models.
                if date == today, let times = expected.todaySchedule,
                   let fajr = try? SessionsFixtures.instant(times.fajr),
                   let asr = try? SessionsFixtures.instant(times.asr) {
                    return PrayerSchedule(localDate: date, zone: zone, fajr: fajr, sunrise: nil, dhuhr: nil, asr: asr,
                                          maghrib: nil, isha: nil)
                }
                return try? port.schedule(on: date, at: GeoCoordinates(latitude: place.latitude,
                                                                       longitude: place.longitude),
                                          in: zone, settings: settings)
            },
            completeToday: Set(Period.allCases.filter { input.state.isComplete($0, in: input.collections) }),
            firedToday: Set(Period.allCases.filter { input.preferences.lastShown[$0] == today }
                .map(ReminderRule.adhkarId)))

        for period in Period.allCases {
            let first = plan.first { $0.target == .adhkar(period) }
            let complete = input.state.isComplete(period, in: input.collections)
            if let scheduled = expected.scheduled[period] {
                let fireAt = try SessionsFixtures.instant(scheduled.fireAt)
                let actual = try #require(first, "\(fixture.name) [\(period)]: nothing planned")
                #expect(abs(actual.fireAt.timeIntervalSince(fireAt)) <= 120,
                        "\(fixture.name) [\(period)]: \(actual.fireAt) vs \(fireAt)")
                #expect(actual.id == "adhkar.\(period.rawValue).\(actual.localDate)")
            } else if complete, input.preferences.location != nil, !rules.isEmpty {
                // The PWA schedules only the next reminder and skips a period done today; the planner already has
                // the following days, so the first one is on a later date.
                let actual = try #require(first, "\(fixture.name) [\(period)]")
                #expect(actual.localDate > today, "\(fixture.name) [\(period)]")
            } else if expected.todaySchedule == nil {
                // No times today (polar day or night, no location): nothing planned today.
                #expect(first.map { $0.localDate > today } ?? true, "\(fixture.name) [\(period)]")
            } else {
                #expect(first == nil, "\(fixture.name) [\(period)]")
            }
        }
    }
}

struct ReminderPlannerTests {
    private let zone = TimeZone(identifier: "Asia/Riyadh")!
    private let now = Date(timeIntervalSince1970: 3 * 3600) // 06:00 in Riyadh on 1970-01-01

    /// Fajr 04:00, Dhuhr 12:00, Asr 15:30, Maghrib 18:00, Isha 19:30 local, every day.
    private func schedule(_ date: String) -> PrayerSchedule? {
        guard let day = Self.days(date) else { return nil }
        func at(_ hours: Double) -> Date { Date(timeIntervalSince1970: (Double(day) * 24 + hours - 3) * 3600) }
        return PrayerSchedule(localDate: date, zone: zone, fajr: at(4), sunrise: at(5.5), dhuhr: at(12),
                              asr: at(15.5), maghrib: at(18), isha: at(19.5))
    }

    private static func days(_ date: String) -> Int? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] == 1970, parts[1] == 1 else { return nil }
        return parts[2] - 1
    }

    private func adhkarRules() -> [ReminderRule] {
        [.adhkar(.morning, enabled: true, updatedAt: now), .adhkar(.evening, enabled: true, updatedAt: now)]
    }

    @Test func plansSevenDaysWithStableIDs() {
        let plan = ReminderPlanner.plan(now: now, zone: zone, rules: adhkarRules(), schedule: schedule,
                                        completeToday: [], firedToday: [])
        // Today and the next six days; today's morning (05:00) passed more than 15 minutes ago.
        #expect(plan.count == 2 * ReminderPlanner.horizonDays - 1)
        #expect(plan.first?.id == "adhkar.evening.1970-01-01")
        #expect(plan.last?.id == "adhkar.evening.1970-01-07")
        #expect(Set(plan.map(\.id)).count == plan.count)
        #expect(plan == plan.sorted { $0.fireAt < $1.fireAt })
    }

    @Test func prayerRulesUseTheirOffsetAndSkipAClampedAsr() {
        let rules = [ReminderRule.prayer(.dhuhr, offsetMinutes: -10, enabled: true, updatedAt: now),
                     ReminderRule.prayer(.asr, offsetMinutes: 0, enabled: true, updatedAt: now),
                     ReminderRule.adhkar(.evening, enabled: true, updatedAt: now)]
        let clamped: (String) -> PrayerSchedule? = { date in
            guard let base = schedule(date) else { return nil }
            return PrayerSchedule(localDate: date, zone: zone, fajr: base.fajr, sunrise: base.sunrise,
                                  dhuhr: base.dhuhr, asr: base.maghrib, maghrib: base.maghrib, isha: base.isha,
                                  asrClamped: true)
        }
        let plan = ReminderPlanner.plan(now: now, zone: zone, rules: rules, schedule: clamped, completeToday: [],
                                        firedToday: [])
        #expect(plan.allSatisfy { $0.target == .prayer(.dhuhr) })
        let first = plan.first
        #expect(first?.id == "prayer.dhuhr.1970-01-01")
        #expect(first?.fireAt == schedule("1970-01-01")?.dhuhr?.addingTimeInterval(-600))
    }

    @Test func aPeriodCompleteTodayIsPlannedFromTomorrow() {
        let plan = ReminderPlanner.plan(now: Date(timeIntervalSince1970: 0), zone: zone, rules: adhkarRules(),
                                        schedule: schedule, completeToday: [.morning], firedToday: [])
        #expect(plan.first?.id == "adhkar.evening.1970-01-01")
        #expect(!plan.contains { $0.id == "adhkar.morning.1970-01-01" })
        #expect(plan.contains { $0.id == "adhkar.morning.1970-01-02" })
    }

    @Test func catchUpFiresAtOnceUnlessAlreadyShown() {
        let late = Date(timeIntervalSince1970: 2 * 3600 + 10 * 60) // 05:10, ten minutes after 05:00
        let plan = ReminderPlanner.plan(now: late, zone: zone, rules: adhkarRules(), schedule: schedule,
                                        completeToday: [], firedToday: [])
        #expect(plan.first?.id == "adhkar.morning.1970-01-01")
        #expect(plan.first?.isCatchUp == true)
        #expect(plan.first?.fireAt == late.addingTimeInterval(ReminderPlanner.catchUpDelay))

        let shown = ReminderPlanner.plan(now: late, zone: zone, rules: adhkarRules(), schedule: schedule,
                                         completeToday: [], firedToday: [ReminderRule.adhkarId(.morning)])
        #expect(shown.first?.id == "adhkar.evening.1970-01-01")
    }

    @Test func everyPrayerAndBothPeriodsFitTheBudget() {
        let rules = [ReminderRule.PrayerKey.fajr, .dhuhr, .asr, .maghrib, .isha].map {
            ReminderRule.prayer($0, offsetMinutes: 0, enabled: true, updatedAt: now)
        } + adhkarRules()
        let plan = ReminderPlanner.plan(now: Date(timeIntervalSince1970: 0), zone: zone, rules: rules,
                                        schedule: schedule, completeToday: [], firedToday: [])
        #expect(plan.count == 7 * ReminderPlanner.horizonDays)
        #expect(plan.count <= ReminderPlanner.budget)
    }

    @Test func twoRulesForOnePrayerPlanOneNotification() {
        let rules = [ReminderRule.prayer(.isha, offsetMinutes: 0, enabled: true, updatedAt: now),
                     ReminderRule(id: "other", kind: .prayer, prayerKey: .isha, offsetMinutes: 30, localTime: nil,
                                  enabled: true, updatedAt: now)]
        let plan = ReminderPlanner.plan(now: Date(timeIntervalSince1970: 0), zone: zone, rules: rules,
                                        schedule: schedule, completeToday: [], firedToday: [])
        #expect(plan.count == ReminderPlanner.horizonDays)
        #expect(plan.first?.offsetMinutes == 0)
    }

    @Test func disabledAndPersonalRulesPlanNothing() {
        let rules = [ReminderRule.adhkar(.morning, enabled: false, updatedAt: now),
                     ReminderRule(id: "p", kind: .personal, prayerKey: nil, offsetMinutes: nil, localTime: "08:00",
                                  enabled: true, updatedAt: now)]
        #expect(ReminderPlanner.plan(now: now, zone: zone, rules: rules, schedule: schedule, completeToday: [],
                                     firedToday: []).isEmpty)
    }
}
