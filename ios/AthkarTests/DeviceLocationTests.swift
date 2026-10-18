import AthkarCore
import CoreLocation
import Foundation
import XCTest
@testable import Athkar

/// These cases use actual Apple types. They require iOS runtime evidence, not Linux XCTest.
@MainActor
final class DeviceLocationTests: XCTestCase {
    func testActualAuthorizationStatusesMapWithoutRequestingPermission() async {
        XCTAssertEqual(CoreLocationRequestDriver.authorization(.notDetermined), .notDetermined)
        XCTAssertEqual(CoreLocationRequestDriver.authorization(.authorizedWhenInUse), .whenInUse)
        XCTAssertEqual(CoreLocationRequestDriver.authorization(.authorizedAlways), .always)
        XCTAssertEqual(CoreLocationRequestDriver.authorization(.denied), .denied)
        XCTAssertEqual(CoreLocationRequestDriver.authorization(.restricted), .restricted)
    }

    func testActualCoreLocationErrorsMapToExistingErrors() async {
        XCTAssertEqual(CoreLocationRequestDriver.failure(CLError(.denied)), .denied)
        XCTAssertEqual(CoreLocationRequestDriver.failure(CLError(.locationUnknown)), .unavailable)
        XCTAssertEqual(CoreLocationRequestDriver.failure(CLError(.network)), .unavailable)
        XCTAssertEqual(CoreLocationRequestDriver.failure(NSError(domain: "unrelated", code: 1)), .unavailable)
    }

    func testActualLocationMappingPreservesCoarseAccuracyAndTimestamp() async {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: -33.865, longitude: 151.20732),
                                  altitude: 0, horizontalAccuracy: 10_000, verticalAccuracy: -1, timestamp: date)
        XCTAssertEqual(CoreLocationRequestDriver.fix(location),
                       LocationFix(latitude: -33.865, longitude: 151.20732,
                                   horizontalAccuracy: 10_000, timestamp: date))
    }

    func testSessionsOwnDifferentManagersWithKilometerAccuracy() async {
        let first = CoreLocationRequestDriver { _ in }
        let second = CoreLocationRequestDriver { _ in }
        defer { first.invalidate(); second.invalidate() }
        XCTAssertFalse(first.manager === second.manager)
        XCTAssertTrue(first.manager.delegate === first)
        XCTAssertTrue(second.manager.delegate === second)
        XCTAssertEqual(first.manager.desiredAccuracy, kCLLocationAccuracyKilometer)
        XCTAssertEqual(second.manager.desiredAccuracy, kCLLocationAccuracyKilometer)
        XCTAssertFalse(first.manager.allowsBackgroundLocationUpdates)
        XCTAssertFalse(second.manager.allowsBackgroundLocationUpdates)
    }

    func testDelegateRejectsCallbacksFromAnotherManager() async {
        var firstEvents: [LocationRequestEvent] = []
        var secondEvents: [LocationRequestEvent] = []
        let first = CoreLocationRequestDriver { firstEvents.append($0) }
        let second = CoreLocationRequestDriver { secondEvents.append($0) }
        defer { first.invalidate(); second.invalidate() }
        // Initial authorization delivery is an OS detail; isolate the explicit callback assertions.
        firstEvents.removeAll()
        secondEvents.removeAll()
        let location = CLLocation(latitude: 21.42, longitude: 39.83)
        first.locationManager(second.manager, didUpdateLocations: [location])
        first.locationManager(second.manager, didFailWithError: CLError(.denied))
        first.locationManagerDidChangeAuthorization(second.manager)
        XCTAssertTrue(firstEvents.isEmpty)
        XCTAssertTrue(secondEvents.isEmpty)
        second.locationManager(second.manager, didUpdateLocations: [location])
        XCTAssertEqual(secondEvents, [.locations([CoreLocationRequestDriver.fix(location)])])
    }

    func testInvalidatedDelegateIgnoresItsOwnQueuedCallbacks() async {
        var events: [LocationRequestEvent] = []
        let retired = CoreLocationRequestDriver { events.append($0) }
        retired.invalidate()
        retired.invalidate() // Teardown is idempotent.
        events.removeAll()
        retired.locationManager(retired.manager, didUpdateLocations: [CLLocation(latitude: 80, longitude: 90)])
        retired.locationManager(retired.manager, didFailWithError: CLError(.denied))
        retired.locationManagerDidChangeAuthorization(retired.manager)
        XCTAssertNil(retired.manager.delegate)
        XCTAssertTrue(events.isEmpty)

        var nextEvents: [LocationRequestEvent] = []
        let next = CoreLocationRequestDriver { nextEvents.append($0) }
        defer { next.invalidate() }
        nextEvents.removeAll()
        next.locationManager(next.manager, didUpdateLocations: [])
        XCTAssertEqual(nextEvents, [.locations([])])
    }

    func testNativeDelegateForwardsEmptyBatchesAndMappedFailures() async {
        var events: [LocationRequestEvent] = []
        let driver = CoreLocationRequestDriver { events.append($0) }
        defer { driver.invalidate() }
        events.removeAll()
        driver.locationManager(driver.manager, didUpdateLocations: [])
        driver.locationManager(driver.manager, didFailWithError: CLError(.denied))
        driver.locationManager(driver.manager, didFailWithError: CLError(.locationUnknown))
        XCTAssertEqual(events, [.locations([]), .failure(.denied), .failure(.unavailable)])
    }
}
