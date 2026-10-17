import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

@MainActor
final class DeviceLocationRequestTests: XCTestCase {
    func testDeniedAndRestrictedAuthorizationDoNotRequestFixes() async throws {
        for (status, error) in [(LocationAuthorization.denied, DeviceLocationError.denied), (.restricted, .restricted)] {
            let fixture = LocationFixture(authorization: status)
            let (call, driver) = try await fixture.start()
            try await assertResult(call, .failure(error))
            XCTAssertEqual(driver.permissionRequests, 0)
            XCTAssertEqual(driver.fixRequests, 0)
            XCTAssertTrue(fixture.clock.entries.isEmpty)
            XCTAssertEqual(driver.invalidations, 1)
        }
    }

    func testBothAllowedStatusesRequestOneFixWithoutPermission() async throws {
        for status in [LocationAuthorization.whenInUse, .always] {
            let fixture = LocationFixture(authorization: status)
            let (call, driver) = try await fixture.start()
            XCTAssertEqual(driver.permissionRequests, 0)
            XCTAssertEqual(driver.fixRequests, 1)
            XCTAssertEqual(fixture.clock.entries.count, 1)
            driver.emit(.locations([fixture.fix()]))
            try await assertResult(call, fixture.success)
        }
    }

    func testPermissionHasNoTimeoutAndFixGetsFullIntervalAfterDecision() async throws {
        let fixture = LocationFixture(authorization: .notDetermined)
        let (call, driver) = try await fixture.start()
        XCTAssertEqual(driver.permissionRequests, 1)
        driver.emit(.authorization(.notDetermined))
        fixture.clock.advance(seconds: 3_600)
        XCTAssertNil(call.result)
        XCTAssertEqual(driver.invalidations, 0)
        XCTAssertEqual(driver.fixRequests, 0)
        XCTAssertTrue(fixture.clock.entries.isEmpty)

        driver.emit(.authorization(.whenInUse))
        driver.emit(.authorization(.always))
        XCTAssertEqual(driver.fixRequests, 1)
        XCTAssertEqual(fixture.clock.entries.count, 1)
        XCTAssertEqual(fixture.clock.entries[0].deadline, .seconds(3_615))
        fixture.clock.advance(seconds: 14)
        XCTAssertNil(call.result)
        XCTAssertEqual(driver.invalidations, 0)
        fixture.clock.advance(seconds: 1)
        try await assertResult(call, .failure(.unavailable))
        XCTAssertEqual(driver.invalidations, 1)
    }

    func testDeniedAndRestrictedDecisionsEndPermissionWait() async throws {
        for (status, error) in [(LocationAuthorization.denied, DeviceLocationError.denied), (.restricted, .restricted)] {
            let fixture = LocationFixture(authorization: .notDetermined)
            let (call, driver) = try await fixture.start()
            driver.emit(.authorization(status))
            try await assertResult(call, .failure(error))
            XCTAssertEqual(driver.fixRequests, 0)
            XCTAssertTrue(fixture.clock.entries.isEmpty)
            XCTAssertEqual(driver.invalidations, 1)
        }
    }

    func testAdmissionStaysBusyAcrossPermissionToFixTransition() async throws {
        let fixture = LocationFixture(authorization: .notDetermined)
        let (first, driver) = try await fixture.start()
        try await assertResult(PendingLocationCall(fixture.request), .failure(.busy))
        driver.emit(.authorization(.whenInUse))
        try await assertResult(PendingLocationCall(fixture.request), .failure(.busy))
        XCTAssertEqual(fixture.factory.drivers.count, 1)
        XCTAssertEqual(driver.permissionRequests, 1)
        XCTAssertEqual(driver.fixRequests, 1)
        XCTAssertEqual(driver.invalidations, 0)

        driver.emit(.locations([fixture.fix()]))
        try await assertResult(first, fixture.success)
        fixture.factory.authorization = .whenInUse
        let (next, nextDriver) = try await fixture.start()
        XCTAssertFalse(driver.generation === nextDriver.generation)
        nextDriver.emit(.locations([fixture.fix()]))
        try await assertResult(next, fixture.success)
    }

    func testSynchronousDriverDecisionsAndFixesCompleteOnce() async throws {
        let fixture = LocationFixture(authorization: .notDetermined)
        fixture.factory.onPermission = { $0.emit(.authorization(.whenInUse)) }
        let fix = fixture.fix()
        fixture.factory.onFix = {
            $0.emit(.locations([fix]))
            $0.replay(.failure(.denied))
        }
        let (call, driver) = try await fixture.start()
        try await assertResult(call, fixture.success)
        XCTAssertEqual(driver.permissionRequests, 1)
        XCTAssertEqual(driver.fixRequests, 1)
        XCTAssertEqual(driver.invalidations, 1)
        XCTAssertEqual(call.completions, 1)
        XCTAssertTrue(fixture.clock.entries[0].cancelled)
    }

    func testSilentFixTimesOutAtMonotonicBoundary() async throws {
        let fixture = LocationFixture()
        let (call, driver) = try await fixture.start()
        XCTAssertEqual(fixture.clock.entries[0].deadline, .seconds(15))
        fixture.clock.advance(seconds: 14)
        XCTAssertNil(call.result)
        XCTAssertEqual(driver.invalidations, 0)
        fixture.clock.advance(seconds: 1)
        try await assertResult(call, .failure(.unavailable))
        fixture.clock.entries[0].replay()
        driver.replay(.failure(.denied))
        XCTAssertEqual(call.completions, 1)
        XCTAssertEqual(driver.invalidations, 1)
    }

    func testFixAtOrAfterDeadlineCannotBeatDelayedTimeoutAction() async throws {
        for elapsed in [15.0, 15.001] {
            let fixture = LocationFixture()
            let (call, driver) = try await fixture.start()
            fixture.clock.advance(seconds: elapsed, fire: false)
            driver.emit(.locations([fixture.fix()]))
            try await assertResult(call, .failure(.unavailable))
            XCTAssertTrue(fixture.clock.entries[0].cancelled)
            XCTAssertEqual(driver.invalidations, 1)
        }
    }

    func testSuccessBeforeDeadlineCancelsTimerAndIgnoresReplay() async throws {
        let fixture = LocationFixture()
        let (call, driver) = try await fixture.start()
        fixture.clock.advance(seconds: 14)
        driver.emit(.locations([fixture.fix()]))
        try await assertResult(call, fixture.success)
        XCTAssertTrue(fixture.clock.entries[0].cancelled)
        fixture.clock.advance(seconds: 100)
        fixture.clock.entries[0].replay()
        driver.replay(.locations([fixture.fix(latitude: 80)]))
        XCTAssertEqual(call.result, fixture.success)
        XCTAssertEqual(call.completions, 1)
        XCTAssertEqual(driver.invalidations, 1)
    }

    func testWallClockChangesCannotExtendDeadline() async throws {
        let fixture = LocationFixture()
        let (call, driver) = try await fixture.start()
        fixture.clock.date = fixture.clock.date.addingTimeInterval(86_400)
        fixture.clock.advance(seconds: 14)
        XCTAssertNil(call.result)
        XCTAssertEqual(driver.invalidations, 0)
        fixture.clock.date = fixture.clock.date.addingTimeInterval(-172_800)
        fixture.clock.advance(seconds: 1)
        try await assertResult(call, .failure(.unavailable))
    }

    func testInvalidCoordinatesAccuracyAndTimestampsFailPromptly() async throws {
        let invalid: [(Double, Double, Double, Date)] = [
            (.nan, 0, 1, testLocationDate), (.infinity, 0, 1, testLocationDate),
            (-.infinity, 0, 1, testLocationDate), (90.001, 0, 1, testLocationDate),
            (-90.001, 0, 1, testLocationDate), (0, .nan, 1, testLocationDate),
            (0, .infinity, 1, testLocationDate), (0, -.infinity, 1, testLocationDate),
            (0, 180.001, 1, testLocationDate), (0, -180.001, 1, testLocationDate),
            (0, 0, -1, testLocationDate), (0, 0, .nan, testLocationDate),
            (0, 0, .infinity, testLocationDate), (0, 0, -.infinity, testLocationDate),
            (0, 0, 1, Date(timeIntervalSinceReferenceDate: .nan)),
            (0, 0, 1, Date(timeIntervalSinceReferenceDate: .infinity)),
            (0, 0, 1, Date(timeIntervalSinceReferenceDate: -.infinity))
        ]
        for (latitude, longitude, accuracy, timestamp) in invalid {
            let fixture = LocationFixture()
            let (call, driver) = try await fixture.start()
            driver.emit(.locations([LocationFix(latitude: latitude, longitude: longitude,
                                               horizontalAccuracy: accuracy, timestamp: timestamp)]))
            try await assertResult(call, .failure(.unavailable))
            XCTAssertEqual(driver.invalidations, 1)
            XCTAssertTrue(fixture.clock.entries[0].cancelled)
        }
    }

    func testFreshnessAndFutureSkewInclusiveBoundaries() async throws {
        for (age, accepted) in [(300.0, true), (300.001, false), (-5.0, true), (-5.001, false), (0.0, true)] {
            let fixture = LocationFixture()
            let (call, driver) = try await fixture.start()
            driver.emit(.locations([fixture.fix(timestamp: fixture.clock.date.addingTimeInterval(-age))]))
            try await assertResult(call, accepted ? fixture.success : .failure(.unavailable))
        }
    }

    func testNonFiniteComputedAgeIsRejected() async throws {
        let fixture = LocationFixture()
        let (call, driver) = try await fixture.start()
        let fix = fixture.fix()
        fixture.clock.date = Date(timeIntervalSinceReferenceDate: .infinity)
        driver.emit(.locations([fix]))
        try await assertResult(call, .failure(.unavailable))
    }

    func testCoordinateEndpointsZeroAndReducedAccuracyRemainValid() async throws {
        for (latitude, longitude, accuracy) in [(0.0, 0.0, 0.0), (-90, -180, 10_000), (90, 180, 100_000)] {
            let fixture = LocationFixture()
            let (call, driver) = try await fixture.start()
            driver.emit(.locations([fixture.fix(latitude: latitude, longitude: longitude, accuracy: accuracy)]))
            try await assertResult(call, .success(GeoCoordinates(latitude: latitude, longitude: longitude)))
        }
    }

    func testActualStorageRoundingPreservesPositiveAndNegativeHalves() async throws {
        for (input, expected) in [(-33.865, -33.86), (33.865, 33.87), (-12.345, -12.34), (12.345, 12.35)] {
            let fixture = LocationFixture()
            let (call, driver) = try await fixture.start()
            driver.emit(.locations([fixture.fix(latitude: input, longitude: input)]))
            try await assertResult(call, .success(GeoCoordinates(latitude: expected, longitude: expected)))
        }
    }

    func testNewestAcceptableSampleSkipsInvalidLastAndBreaksTimestampTies() async throws {
        let fixture = LocationFixture()
        let (call, driver) = try await fixture.start()
        driver.emit(.locations([
            fixture.fix(latitude: 10, timestamp: fixture.clock.date.addingTimeInterval(-1)),
            fixture.fix(latitude: 20),
            fixture.fix(latitude: 30),
            fixture.fix(latitude: .nan)
        ]))
        try await assertResult(call, .success(GeoCoordinates(latitude: 30, longitude: 39.83)))
    }

    func testEmptyInvalidAndStaleBatchesDoNotWaitForDeadline() async throws {
        for batch in [[], [LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: -1, timestamp: testLocationDate)],
                      [LocationFix(latitude: 0, longitude: 0, horizontalAccuracy: 1,
                                   timestamp: testLocationDate.addingTimeInterval(-301))]] {
            let fixture = LocationFixture()
            let (call, driver) = try await fixture.start()
            driver.emit(.locations(batch))
            try await assertResult(call, .failure(.unavailable))
            XCTAssertEqual(fixture.clock.now, .zero)
            XCTAssertEqual(driver.invalidations, 1)
        }
    }

    func testPreCancelledTaskCreatesNoDriver() async throws {
        let fixture = LocationFixture()
        let call = PendingLocationCall(fixture.request)
        call.cancel() // The main-actor task has not started yet.
        try await assertResult(call, .failure(.cancelled))
        XCTAssertTrue(fixture.factory.drivers.isEmpty)
        XCTAssertTrue(fixture.clock.entries.isEmpty)
    }

    func testRealTaskCancellationEndsBothWaitsAndAdmitsFollowingCall() async throws {
        for status in [LocationAuthorization.notDetermined, .whenInUse] {
            let fixture = LocationFixture(authorization: status)
            let (call, driver) = try await fixture.start()
            call.cancel()
            try await assertResult(call, .failure(.cancelled))
            XCTAssertEqual(driver.invalidations, 1)
            XCTAssertTrue(fixture.clock.entries.allSatisfy { $0.cancelled })
            fixture.factory.authorization = .whenInUse
            let (next, nextDriver) = try await fixture.start()
            driver.replay(.authorization(.denied))
            driver.replay(.locations([fixture.fix(latitude: 80)]))
            XCTAssertNil(next.result)
            nextDriver.emit(.locations([fixture.fix()]))
            try await assertResult(next, fixture.success)
        }
    }

    func testCancelledBusyCallerCannotInvalidateActiveRequest() async throws {
        let fixture = LocationFixture()
        let (first, driver) = try await fixture.start()
        let busy = PendingLocationCall(fixture.request)
        try await assertResult(busy, .failure(.busy))
        busy.cancel()
        let preCancelledBusy = PendingLocationCall(fixture.request)
        preCancelledBusy.cancel()
        try await assertResult(preCancelledBusy, .failure(.cancelled))
        XCTAssertEqual(driver.invalidations, 0)
        XCTAssertEqual(fixture.factory.drivers.count, 1)
        driver.emit(.locations([fixture.fix()]))
        try await assertResult(first, fixture.success)
    }

    func testOldGenerationEventsCannotCompleteOrCancelNewerRequest() async throws {
        for ending in ["success", "failure", "timeout", "cancellation"] {
            let fixture = LocationFixture()
            let (first, oldDriver) = try await fixture.start()
            switch ending {
            case "success": oldDriver.emit(.locations([fixture.fix()]))
            case "failure": oldDriver.emit(.failure(.denied))
            case "timeout": fixture.clock.advance(seconds: 15)
            default: first.cancel()
            }
            let firstResult = try await first.value()
            let expected: Result<GeoCoordinates, DeviceLocationError>
            switch ending {
            case "success": expected = fixture.success
            case "failure": expected = .failure(.denied)
            case "timeout": expected = .failure(.unavailable)
            default: expected = .failure(.cancelled)
            }
            XCTAssertEqual(firstResult, expected)

            let oldTimer = fixture.clock.entries[0]
            let (next, newDriver) = try await fixture.start()
            XCTAssertFalse(oldDriver.generation === newDriver.generation)
            // This sample is fresh and valid, so validation cannot conceal incorrect generation handling.
            oldDriver.replay(.locations([fixture.fix(latitude: 80, longitude: 90)]))
            oldDriver.replay(.failure(.denied))
            oldDriver.replay(.authorization(.restricted))
            oldTimer.replay()
            fixture.request.receive(.cancelled, for: oldDriver.generation)
            XCTAssertNil(next.result)
            XCTAssertEqual(newDriver.fixRequests, 1)
            XCTAssertEqual(newDriver.invalidations, 0)
            XCTAssertFalse(fixture.clock.entries.last!.cancelled)
            newDriver.emit(.locations([fixture.fix()]))
            try await assertResult(next, fixture.success)
            XCTAssertEqual(first.completions, 1)
            XCTAssertEqual(next.completions, 1)
            XCTAssertEqual(oldDriver.invalidations, 1)
            XCTAssertEqual(newDriver.invalidations, 1)
        }
    }

    func testLatePermissionAnswerAndFixDoNotEndNewPermissionWait() async throws {
        let fixture = LocationFixture(authorization: .notDetermined)
        let (first, oldDriver) = try await fixture.start()
        first.cancel()
        try await assertResult(first, .failure(.cancelled))
        let (next, driver) = try await fixture.start()
        oldDriver.replay(.authorization(.whenInUse))
        oldDriver.replay(.locations([fixture.fix()]))
        driver.emit(.locations([fixture.fix()])) // Even the current driver cannot fix before permission.
        XCTAssertNil(next.result)
        XCTAssertEqual(driver.invalidations, 0)
        XCTAssertEqual(driver.fixRequests, 0)
        XCTAssertTrue(fixture.clock.entries.isEmpty)
        driver.emit(.authorization(.whenInUse))
        driver.emit(.locations([fixture.fix()]))
        try await assertResult(next, fixture.success)
    }

    func testSuccessAndCancellationRacesUseFirstTerminalActorEvent() async throws {
        for cancelFirst in [false, true] {
            let fixture = LocationFixture()
            let (call, driver) = try await fixture.start()
            if cancelFirst { fixture.request.receive(.cancelled, for: driver.generation) }
            driver.replay(.locations([fixture.fix()]))
            fixture.request.receive(.cancelled, for: driver.generation)
            driver.replay(.failure(.denied))
            try await assertResult(call, cancelFirst ? .failure(.cancelled) : fixture.success)
            XCTAssertEqual(call.completions, 1)
            XCTAssertEqual(driver.invalidations, 1)
        }
    }

    func testFailureAndTimeoutRacesUseFirstTerminalActorEvent() async throws {
        for timeoutFirst in [false, true] {
            let fixture = LocationFixture()
            let (call, driver) = try await fixture.start()
            fixture.clock.advance(seconds: 15, fire: false)
            if timeoutFirst { fixture.clock.entries[0].replay() }
            driver.replay(.failure(.denied))
            fixture.clock.entries[0].replay()
            try await assertResult(call, .failure(timeoutFirst ? .unavailable : .denied))
            XCTAssertEqual(call.completions, 1)
            XCTAssertEqual(driver.invalidations, 1)
        }
    }

    func testRevokedAuthorizationEndsFixAndDuplicateAllowedStatusDoesNotRestart() async throws {
        for (status, error) in [(LocationAuthorization.denied, DeviceLocationError.denied),
                                (.restricted, .restricted), (.notDetermined, .denied)] {
            let fixture = LocationFixture()
            let (call, driver) = try await fixture.start()
            driver.emit(.authorization(.whenInUse))
            driver.emit(.authorization(.always))
            fixture.request.receive(.deadline, for: driver.generation) // Early timer action is harmless.
            XCTAssertNil(call.result)
            XCTAssertEqual(driver.fixRequests, 1)
            XCTAssertEqual(fixture.clock.entries.count, 1)
            driver.emit(.authorization(status))
            try await assertResult(call, .failure(error))
            XCTAssertTrue(fixture.clock.entries[0].cancelled)
        }
    }

    func testConfiguredFixDeadlineUsesSameProductionPolicy() async throws {
        let fixture = LocationFixture(fixTimeout: .seconds(2))
        let (call, driver) = try await fixture.start()
        fixture.clock.advance(seconds: 1)
        XCTAssertNil(call.result)
        XCTAssertEqual(driver.invalidations, 0)
        fixture.clock.advance(seconds: 1)
        try await assertResult(call, .failure(.unavailable))
    }

    private func assertResult(_ call: PendingLocationCall, _ expected: Result<GeoCoordinates, DeviceLocationError>,
                              file: StaticString = #filePath, line: UInt = #line) async throws {
        let result = try await call.value()
        XCTAssertEqual(result, expected, file: file, line: line)
    }
}

private let testLocationDate = Date(timeIntervalSince1970: 1_760_000_000)

private enum LocationTestWaitError: Error { case expired }

@MainActor
private func awaitLocationExpectation(_ expectation: XCTestExpectation) async throws {
    let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 3)
    XCTAssertEqual(result, .completed, expectation.expectationDescription)
    guard result == .completed else { throw LocationTestWaitError.expired }
}

@MainActor
private final class PendingLocationCall {
    private let completed = XCTestExpectation(description: "location caller completed")
    private var task: Task<Void, Never>?
    private(set) var result: Result<GeoCoordinates, DeviceLocationError>?
    private(set) var completions = 0

    init(_ request: OneShotLocationRequest) {
        task = Task { @MainActor [weak self] in
            let result: Result<GeoCoordinates, DeviceLocationError>
            do { result = .success(try await request.currentCoordinates()) }
            catch let error as DeviceLocationError { result = .failure(error) }
            catch {
                XCTFail("Unexpected location request error: \(error)")
                guard let self else { return }
                self.completions += 1
                self.completed.fulfill()
                return
            }
            guard let self else { return }
            self.result = result
            self.completions += 1
            self.completed.fulfill()
        }
    }

    deinit { task?.cancel() }

    func cancel() { task?.cancel() }

    func value() async throws -> Result<GeoCoordinates, DeviceLocationError> {
        do { try await awaitLocationExpectation(completed) }
        catch { cancel(); throw error }
        await task?.value
        return try XCTUnwrap(result)
    }
}

@MainActor
private final class LocationFixture {
    let clock = ManualLocationClock()
    let factory: RecordingLocationFactory
    let request: OneShotLocationRequest

    init(authorization: LocationAuthorization = .whenInUse, fixTimeout: Duration = .seconds(15)) {
        let factory = RecordingLocationFactory(authorization: authorization)
        self.factory = factory
        request = OneShotLocationRequest(clock: clock, fixTimeout: fixTimeout) { generation, sink in
            factory.make(generation: generation, sink: sink)
        }
    }

    var success: Result<GeoCoordinates, DeviceLocationError> {
        .success(GeoCoordinates(latitude: 21.42, longitude: 39.83))
    }

    func fix(latitude: Double = 21.4225, longitude: Double = 39.8262, accuracy: Double = 10_000,
             timestamp: Date? = nil) -> LocationFix {
        LocationFix(latitude: latitude, longitude: longitude, horizontalAccuracy: accuracy,
                    timestamp: timestamp ?? clock.date)
    }

    func start() async throws -> (PendingLocationCall, RecordingLocationDriver) {
        let created = XCTestExpectation(description: "request admitted and driver created")
        factory.created = created
        let call = PendingLocationCall(request)
        try await awaitLocationExpectation(created)
        return (call, try XCTUnwrap(factory.drivers.last))
    }
}

@MainActor
private final class RecordingLocationFactory {
    var authorization: LocationAuthorization
    var drivers: [RecordingLocationDriver] = []
    var created: XCTestExpectation?
    var onPermission: ((RecordingLocationDriver) -> Void)?
    var onFix: ((RecordingLocationDriver) -> Void)?

    init(authorization: LocationAuthorization) { self.authorization = authorization }

    func make(generation: LocationRequestGeneration, sink: @escaping OneShotLocationRequest.Sink)
        -> RecordingLocationDriver {
        let driver = RecordingLocationDriver(generation: generation, authorization: authorization, sink: sink)
        driver.onPermission = onPermission
        driver.onFix = onFix
        drivers.append(driver)
        created?.fulfill()
        created = nil
        return driver
    }
}

/// Records effects and callbacks only. All request decisions run in OneShotLocationRequest.
@MainActor
private final class RecordingLocationDriver: LocationRequestDriver {
    let generation: LocationRequestGeneration
    let authorization: LocationAuthorization
    private let sink: OneShotLocationRequest.Sink
    var onPermission: ((RecordingLocationDriver) -> Void)?
    var onFix: ((RecordingLocationDriver) -> Void)?
    private(set) var permissionRequests = 0
    private(set) var fixRequests = 0
    private(set) var invalidations = 0

    init(generation: LocationRequestGeneration, authorization: LocationAuthorization,
         sink: @escaping OneShotLocationRequest.Sink) {
        self.generation = generation
        self.authorization = authorization
        self.sink = sink
    }

    func requestAuthorization() { permissionRequests += 1; onPermission?(self) }
    func requestFix() { fixRequests += 1; onFix?(self) }
    func invalidate() { invalidations += 1 }
    func emit(_ event: LocationRequestEvent) { if invalidations == 0 { sink(event) } }
    // An OS event may have captured the sink before invalidation. Replay that original closure.
    func replay(_ event: LocationRequestEvent) { sink(event) }
}

@MainActor
private final class ManualLocationClock: LocationRequestClock {
    @MainActor
    final class Entry {
        let deadline: Duration
        let action: @MainActor () -> Void
        var cancelled = false
        var fired = false
        init(deadline: Duration, action: @escaping @MainActor () -> Void) {
            self.deadline = deadline
            self.action = action
        }
        func replay() { action() }
    }

    var date = testLocationDate
    var now: Duration = .zero
    var entries: [Entry] = []

    func schedule(at deadline: Duration, action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let entry = Entry(deadline: deadline, action: action)
        entries.append(entry)
        return { entry.cancelled = true }
    }

    func advance(seconds: Double, fire: Bool = true) {
        now += .seconds(seconds)
        date = date.addingTimeInterval(seconds)
        guard fire else { return }
        for entry in entries where !entry.cancelled && !entry.fired && entry.deadline <= now {
            entry.fired = true
            entry.action()
        }
    }
}
