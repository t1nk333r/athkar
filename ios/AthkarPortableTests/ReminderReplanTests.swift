import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

/// Replan ordering on the production `ReminderModel` and a real SQLite database, with the notification centre held at
/// chosen calls. Each race runs in a fixed order: a pass held mid-flight, a newer request, then the held call resumed.
/// The latest inputs alone decide what stays pending and what `nextPending` shows.
final class ReminderReplanTests: XCTestCase {
    // MARK: Races

    /// Both adhkar reminders are turned off while the first add is in flight. The add lands, the latest pass removes
    /// it, and the older pass adds nothing more. No other call reaches the centre before that add returns.
    @MainActor
    func testDisablingDuringAnInFlightAddLeavesNoObsoleteRequest() async throws {
        let harness = try Harness([morningRule, eveningRule])
        harness.center.hold(.add)
        harness.model.replan()
        let add = await harness.center.held(.add)
        let id = try XCTUnwrap(add.id)
        XCTAssertEqual(id, "adhkar.evening.\(day(0))")

        await harness.model.setAdhkar(.morning, enabled: false)
        await harness.model.setAdhkar(.evening, enabled: false)
        add.resume()
        await harness.settle()

        let events = harness.center.events
        let start = try XCTUnwrap(events.firstIndex(of: .add(id)))
        XCTAssertEqual(Array(events[(start + 1)...].prefix(1)), [.added(id)])
        XCTAssertEqual(harness.center.adds, [id])
        XCTAssertEqual(harness.ids, [])
        XCTAssertNil(harness.model.nextPending)
        XCTAssertTrue(harness.world.reports.isEmpty)
    }

    /// The evening reminder is turned back on while a pass that would remove it reads the pending requests. That pass
    /// stops before removing anything, and the latest plan keeps every request.
    @MainActor
    func testNewerRequestDuringThePendingReadStopsAnOlderRemoval() async throws {
        let harness = try Harness([morningRule, eveningRule])
        harness.model.replan()
        await harness.settle()
        XCTAssertEqual(harness.ids, bothPeriods)

        harness.center.hold(.pending)
        await harness.model.setAdhkar(.evening, enabled: false)
        let read = await harness.center.held(.pending)
        await harness.model.setAdhkar(.evening, enabled: true)
        read.resume()
        await harness.settle()

        XCTAssertEqual(harness.center.pendingRemovals, [[], []])
        XCTAssertEqual(harness.ids, bothPeriods)
        XCTAssertEqual(harness.model.nextPending?.title, "adhkar.evening.\(day(0))")
        XCTAssertTrue(harness.world.reports.isEmpty)
    }

    /// The evening period is completed while today's evening request is being added. The latest pass removes that
    /// request and today's delivered banner, keeps the following days, and shows tomorrow's as the next reminder.
    @MainActor
    func testCompletingDuringAnInFlightAddDropsTodaysReminder() async throws {
        let harness = try Harness([eveningRule])
        harness.center.hold(.add)
        harness.model.replan()
        let add = await harness.center.held(.add)
        XCTAssertEqual(add.id, "adhkar.evening.\(day(0))")

        harness.world.completeToday = [.evening]
        harness.model.replan()
        add.resume()
        await harness.settle()

        XCTAssertEqual(harness.ids, (1...6).map { "adhkar.evening.\(day($0))" })
        XCTAssertEqual(harness.center.count(.removeDelivered(["adhkar.evening.\(day(0))"])), 1)
        XCTAssertEqual(harness.model.nextPending?.title, "adhkar.evening.\(day(1))")
        XCTAssertEqual(harness.model.nextPending?.fireAt, local(day: 1, hour: 16.5))
    }

    /// The completed evening period is reopened while tomorrow's request is being added. Today's request returns.
    @MainActor
    func testReopeningDuringAnInFlightAddRestoresTodaysReminder() async throws {
        let harness = try Harness([eveningRule])
        harness.world.completeToday = [.evening]
        harness.center.hold(.add)
        harness.model.replan()
        let add = await harness.center.held(.add)
        XCTAssertEqual(add.id, "adhkar.evening.\(day(1))")

        harness.world.completeToday = []
        harness.model.replan()
        add.resume()
        await harness.settle()

        XCTAssertEqual(Set(harness.ids), Set((0...6).map { "adhkar.evening.\(day($0))" }))
        XCTAssertEqual(harness.ids.count, 7)
        XCTAssertEqual(harness.center.count(.removeDelivered(["adhkar.evening.\(day(0))"])), 1)
        XCTAssertEqual(harness.model.nextPending?.title, "adhkar.evening.\(day(0))")
    }

    /// Three replans and two location changes arrive while the first pass waits for the permission read. Exactly one
    /// more pass runs, with the latest prayer times.
    @MainActor
    func testRequestsDuringAPassCoalesceIntoOneLatestPass() async throws {
        let harness = try Harness([fajrRule])
        harness.center.hold(.authorization)
        harness.model.replan()
        let read = await harness.center.held(.authorization)

        harness.world.shift = 10 * 60
        harness.model.replan()
        harness.world.shift = 20 * 60
        harness.model.replan()
        harness.model.replan()
        read.resume()
        await harness.settle()

        XCTAssertEqual(harness.center.count(.authorization), 2)
        XCTAssertEqual(harness.center.count(.delivered), 1)
        XCTAssertEqual(harness.ids, (1...6).map { "prayer.fajr.\(day($0))" })
        // Fajr moved 20 minutes later, and the reminder is 10 minutes before it.
        let expected = (1...6).map { local(day: $0, hour: 4).addingTimeInterval(10 * 60) }
        XCTAssertEqual(harness.center.requests.map(\.item.fireAt), expected)
        XCTAssertEqual(harness.model.nextPending?.fireAt, expected.first)
    }

    /// The evening period is completed while the first pass reads the pending requests for `nextPending`. That pass
    /// publishes nothing, and the latest pass shows tomorrow's reminder.
    @MainActor
    func testSupersededPassPublishesNoNextPending() async throws {
        let harness = try Harness([eveningRule])
        harness.center.hold(.pending)
        harness.model.replan()
        let diff = await harness.center.held(.pending)
        harness.center.hold(.pending)
        diff.resume()
        let display = await harness.center.held(.pending)
        XCTAssertEqual(harness.ids.count, 7)

        harness.world.completeToday = [.evening]
        harness.center.hold(.authorization)
        harness.model.replan()
        display.resume()
        let read = await harness.center.held(.authorization)
        XCTAssertNil(harness.model.nextPending, "An outdated pass published nextPending.")

        read.resume()
        await harness.settle()
        XCTAssertEqual(harness.ids, (1...6).map { "adhkar.evening.\(day($0))" })
        XCTAssertEqual(harness.model.nextPending?.title, "adhkar.evening.\(day(1))")
        XCTAssertEqual(harness.model.nextPending?.fireAt, local(day: 1, hour: 16.5))
    }

    // MARK: Errors

    /// An add that fails in the latest pass is reported once, and the other requests are still added.
    @MainActor
    func testAddFailureInTheLatestPassIsReportedAndTheRestAreAdded() async throws {
        let harness = try Harness([eveningRule])
        let all = (0...6).map { "adhkar.evening.\(day($0))" }
        harness.center.addErrors[all[2]] = InjectedFailure()
        harness.model.replan()
        await harness.settle()

        XCTAssertEqual(harness.world.reports.count, 1)
        XCTAssertTrue(harness.world.reports.first is InjectedFailure)
        XCTAssertEqual(harness.center.adds, all)
        XCTAssertEqual(harness.ids, all.filter { $0 != all[2] })
        XCTAssertEqual(harness.model.nextPending?.title, all[0])
    }

    /// The first add fails after a newer request arrived. The failure is not reported, because the latest pass adds
    /// that request again.
    @MainActor
    func testAddFailureInASupersededPassIsRetriedWithoutAReport() async throws {
        let harness = try Harness([eveningRule])
        harness.center.hold(.add)
        harness.model.replan()
        let add = await harness.center.held(.add)
        harness.model.replan()
        add.resume(throwing: InjectedFailure())
        await harness.settle()

        XCTAssertTrue(harness.world.reports.isEmpty)
        XCTAssertEqual(harness.center.count(.addFailed("adhkar.evening.\(day(0))")), 1)
        XCTAssertEqual(harness.ids, (0...6).map { "adhkar.evening.\(day($0))" })
        XCTAssertEqual(harness.model.nextPending?.title, "adhkar.evening.\(day(0))")
    }

    /// SQLite rejects the rule: its `updated_at` CHECK does not accept a five-digit year. Nothing that follows a saved
    /// rule happens. There is no permission request and no replan, and the toggle reads off.
    @MainActor
    func testFailedRuleSaveNeitherAsksPermissionNorReplans() async throws {
        let harness = try Harness()
        harness.center.status = .notDetermined
        harness.world.now = Date(timeIntervalSince1970: 253_402_300_800) // 10000-01-01T00:00:00Z
        await harness.model.setAdhkar(.morning, enabled: true)
        await harness.model.setPrayer(.fajr, enabled: true, offsetMinutes: -10)

        XCTAssertEqual(harness.world.reports.count, 2)
        XCTAssertFalse(harness.model.isEnabled(.morning))
        XCTAssertNil(harness.model.prayerRule(.fajr))
        XCTAssertEqual(try harness.database.reminders.rules(), [])
        XCTAssertEqual(harness.center.events, [])
        XCTAssertNil(harness.model.replanTask)
    }

    /// A permission request that throws is reported. The reminder stays saved, permission is read again, and the
    /// replan that follows plans nothing.
    @MainActor
    func testFailedPermissionRequestIsReported() async throws {
        let harness = try Harness()
        harness.center.status = .notDetermined
        harness.center.requestError = InjectedFailure()
        await harness.model.setAdhkar(.morning, enabled: true)
        await harness.settle()

        XCTAssertEqual(harness.world.reports.count, 1)
        XCTAssertTrue(harness.world.reports.first is InjectedFailure)
        XCTAssertTrue(harness.model.isEnabled(.morning))
        XCTAssertEqual(harness.model.authorization, .notDetermined)
        XCTAssertEqual(Array(harness.center.events.prefix(3)), [.authorization, .requestAuthorization, .authorization])
        XCTAssertEqual(harness.center.count(.delivered), 1)
        XCTAssertEqual(harness.center.adds, [])
        XCTAssertNil(harness.model.nextPending)
    }

    // MARK: Behaviour kept

    /// Permission is granted while a pass that read "denied" waits for the delivered list. The replan on returning to
    /// the app plans every request.
    @MainActor
    func testPermissionGrantedDuringAPassConverges() async throws {
        let harness = try Harness([eveningRule])
        harness.center.status = .denied
        harness.center.hold(.delivered)
        harness.model.replan()
        let read = await harness.center.held(.delivered)
        XCTAssertEqual(harness.model.authorization, .denied)

        harness.center.status = .allowed
        harness.model.replan()
        read.resume()
        await harness.settle()

        XCTAssertEqual(harness.model.authorization, .allowed)
        XCTAssertEqual(harness.ids, (0...6).map { "adhkar.evening.\(day($0))" })
        XCTAssertEqual(harness.model.nextPending?.title, "adhkar.evening.\(day(0))")
    }

    /// Without permission nothing is added, every owned request goes, and another feature's request stays. Delivered
    /// history is still recorded, and today's banner for a completed period is still removed.
    @MainActor
    func testWithoutPermissionOnlyOwnedRequestsAreRemoved() async throws {
        for status in [ReminderModel.Authorization.denied, .notDetermined] {
            let harness = try Harness([morningRule, eveningRule])
            let foreign = PendingReminder(id: "other.feature", title: "غير ذلك", fireAt: local(day: 0, hour: 7))
            harness.center.foreignPending = [foreign]
            harness.model.replan()
            await harness.settle()
            XCTAssertEqual(harness.ids, bothPeriods)

            harness.center.status = status
            harness.center.delivered = [
                DeliveredReminder(id: "adhkar.morning.\(day(0))", ruleId: morningRule.id,
                                  date: local(day: 0, hour: 5)),
            ]
            harness.world.completeToday = [.morning]
            let start = harness.center.events.count
            harness.model.replan()
            await harness.settle()

            XCTAssertEqual(Array(harness.center.events[start...]), [
                .authorization, .delivered, .pending, .removePending(bothPeriods),
                .removeDelivered(["adhkar.morning.\(day(0))"]), .pending,
            ], "\(status)")
            XCTAssertEqual(harness.ids, [])
            XCTAssertEqual(harness.center.foreignPending, [foreign])
            XCTAssertNil(harness.model.nextPending)
            XCTAssertEqual(harness.model.authorization, status)
            XCTAssertEqual(try harness.database.reminders.lastShown(ruleId: morningRule.id), day(0))
            XCTAssertTrue(harness.world.reports.isEmpty)
        }
    }

    /// The plan's IDs are the stable `adhkar.<period>.<date>` and `prayer.<key>.<date>`, each with its rule. Replanning
    /// the same inputs removes nothing and replaces each request instead of adding a second one.
    @MainActor
    func testReplanningTheSameInputsKeepsStableIDsWithoutDuplicates() async throws {
        let harness = try Harness([morningRule, eveningRule, fajrRule])
        let expected = ["adhkar.evening.\(day(0))"] + (1...6).flatMap {
            ["prayer.fajr.\(day($0))", "adhkar.morning.\(day($0))", "adhkar.evening.\(day($0))"]
        }
        harness.model.replan()
        await harness.settle()
        XCTAssertEqual(harness.ids, expected)
        let ruleIds = Dictionary(uniqueKeysWithValues: harness.center.requests.map { ($0.item.id, $0.ruleId) })
        XCTAssertEqual(ruleIds["adhkar.evening.\(day(0))"], "adhkar_evening")
        XCTAssertEqual(ruleIds["adhkar.morning.\(day(1))"], "adhkar_morning")
        XCTAssertEqual(ruleIds["prayer.fajr.\(day(6))"], "prayer_fajr")
        XCTAssertEqual(Set(ruleIds.values), ["adhkar_morning", "adhkar_evening", "prayer_fajr"])

        let start = harness.center.events.count
        harness.model.replan()
        await harness.settle()
        let pass = Array(harness.center.events[start...])
        XCTAssertEqual(Array(pass.prefix(4)), [.authorization, .delivered, .pending, .removePending([])])
        XCTAssertEqual(pass.last, ControlledReminderCenter.Event.pending)
        XCTAssertEqual(harness.center.adds, expected + expected)
        XCTAssertEqual(harness.ids, expected)
        XCTAssertTrue(harness.world.reports.isEmpty)
    }

    /// A reminder delivered today becomes `lastShown` and is not planned again today, even inside the catch-up window.
    /// Deliveries from yesterday, from another feature or for an unknown rule change nothing.
    @MainActor
    func testDeliveredTodayIsRecordedAndNotPlannedAgain() async throws {
        let harness = try Harness([morningRule, eveningRule])
        harness.world.now = local(day: 0, hour: 16.5).addingTimeInterval(10 * 60)
        harness.center.delivered = [
            DeliveredReminder(id: "adhkar.evening.\(day(0))", ruleId: eveningRule.id, date: local(day: 0, hour: 16.5)),
            DeliveredReminder(id: "adhkar.morning.1969-12-31", ruleId: morningRule.id, date: local(day: -1, hour: 5)),
            DeliveredReminder(id: "other.feature", ruleId: morningRule.id, date: local(day: 0, hour: 9)),
            DeliveredReminder(id: "prayer.isha.\(day(0))", ruleId: "prayer_isha", date: local(day: 0, hour: 9)),
        ]
        harness.model.replan()
        await harness.settle()

        XCTAssertEqual(try harness.database.reminders.lastShown(ruleId: eveningRule.id), day(0))
        XCTAssertNil(try harness.database.reminders.lastShown(ruleId: morningRule.id))
        XCTAssertEqual(harness.ids, (1...6).flatMap { ["adhkar.morning.\(day($0))", "adhkar.evening.\(day($0))"] })
        XCTAssertTrue(harness.world.reports.isEmpty)
    }

    /// Ten minutes after the morning reminder's time, it is planned to fire a second after planning. The planning
    /// instant and zone reach the adapter that builds its trigger.
    @MainActor
    func testCatchUpCarriesThePlanningInstantAndZone() async throws {
        let harness = try Harness([morningRule])
        let now = local(day: 0, hour: 5).addingTimeInterval(10 * 60)
        harness.world.now = now
        harness.model.replan()
        await harness.settle()

        let requests = harness.center.requests
        XCTAssertEqual(requests.map(\.item.id), (0...6).map { "adhkar.morning.\(day($0))" })
        let catchUp = try XCTUnwrap(requests.first)
        XCTAssertTrue(catchUp.item.isCatchUp)
        XCTAssertEqual(catchUp.item.fireAt, now.addingTimeInterval(1))
        XCTAssertEqual(catchUp.ruleId, morningRule.id)
        XCTAssertFalse(requests[1].item.isCatchUp)
        XCTAssertEqual(requests[1].item.fireAt, local(day: 1, hour: 5))
        for request in requests {
            XCTAssertEqual(request.now, now)
            XCTAssertEqual(request.zone, harness.world.zone)
        }
        XCTAssertEqual(harness.model.nextPending?.fireAt, now.addingTimeInterval(1))
    }

    /// A pass hands its inputs the instant it plans from, even once the clock has moved on: adhkar completion is read
    /// for the date the pass plans and removes delivered banners for, not a later one.
    @MainActor
    func testInputsAreReadAtThePassInstant() async throws {
        let harness = try Harness([eveningRule])
        let world = harness.world
        let start = world.now
        world.tick = 1
        var instants: [Date] = []
        harness.model.inputs = { now in
            instants.append(now)
            return world.inputs
        }
        harness.model.replan()
        await harness.settle()

        XCTAssertEqual(instants, [start])
        XCTAssertEqual(Set(harness.center.requests.map(\.now)), [start])
        XCTAssertGreaterThan(world.now, start, "the clock moved on once the pass read it")
    }
}

private struct InjectedFailure: Error {}

private let epoch = Date(timeIntervalSince1970: 0)
private let morningRule = ReminderRule.adhkar(.morning, enabled: true, updatedAt: epoch)
private let eveningRule = ReminderRule.adhkar(.evening, enabled: true, updatedAt: epoch)
private let fajrRule = ReminderRule.prayer(.fajr, offsetMinutes: -10, enabled: true, updatedAt: epoch)
/// Both adhkar reminders planned at 06:00 on day 0: this evening's, then six mornings and evenings.
private let bothPeriods = ["adhkar.evening.\(day(0))"]
    + (1...6).flatMap { ["adhkar.morning.\(day($0))", "adhkar.evening.\(day($0))"] }

/// `1970-01-01` is day 0.
private func day(_ offset: Int) -> String { "1970-01-0\(offset + 1)" }

/// An instant on day `day` at `hour` local time, at +03:00.
private func local(day: Int, hour: Double) -> Date {
    Date(timeIntervalSince1970: (Double(day) * 24 + hour - 3) * 3600)
}

/// Fajr 04:00, Sunrise 05:30, Dhuhr 12:00, Asr 15:30, Maghrib 18:00 and Isha 19:30 local every day of January 1970,
/// as in `ReminderPlannerTests`, all moved by `shift`.
private func schedule(_ date: String, zone: TimeZone, shift: TimeInterval) -> PrayerSchedule? {
    let parts = date.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, parts[0] == 1970, parts[1] == 1 else { return nil }
    func at(_ hour: Double) -> Date { local(day: parts[2] - 1, hour: hour).addingTimeInterval(shift) }
    return PrayerSchedule(localDate: date, zone: zone, fajr: at(4), sunrise: at(5.5), dhuhr: at(12), asr: at(15.5),
                          maghrib: at(18), isha: at(19.5))
}

/// The clock, completion and prayer times the model plans from, as a test moves them, and the errors it reports.
@MainActor
private final class World {
    let zone = TimeZone(secondsFromGMT: 3 * 3600)!
    var now = local(day: 0, hour: 6)
    /// How far the clock moves on each time the model reads it.
    var tick: TimeInterval = 0
    var completeToday: Set<Period> = []
    /// Moves every prayer time, as a location change does.
    var shift: TimeInterval = 0
    var reports: [any Error] = []

    var inputs: ReminderModel.PlanInputs {
        let zone = self.zone
        let shift = self.shift
        return ReminderModel.PlanInputs(zone: zone, schedule: { schedule($0, zone: zone, shift: shift) },
                                        completeToday: completeToday)
    }

    /// The model's clock: `now`, which then moves on by `tick`.
    func read() -> Date {
        defer { now += tick }
        return now
    }
}

/// A production model on its own in-memory database, with the controlled centre and the world it plans from.
@MainActor
private struct Harness {
    let database: AppDatabase
    let center: ControlledReminderCenter
    let world: World
    let model: ReminderModel

    init(_ rules: [ReminderRule] = []) throws {
        let database = try AppDatabase.inMemory()
        for rule in rules { try database.reminders.save(rule) }
        let center = ControlledReminderCenter()
        let world = World()
        let model = try ReminderModel(repository: database.reminders, report: { world.reports.append($0) },
                                      center: center, clock: { world.read() })
        model.inputs = { _ in world.inputs }
        self.database = database
        self.center = center
        self.world = world
        self.model = model
    }

    /// The IDs pending in the centre, in the order added.
    var ids: [String] { center.requests.map(\.item.id) }

    /// Waits for the replan task the model holds.
    func settle() async { await model.replanTask?.value }
}
