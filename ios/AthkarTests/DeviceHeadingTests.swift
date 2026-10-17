import CoreLocation
import XCTest
@testable import Athkar

/// CoreLocation's headings and errors reaching the القبلة compass; the portable tests cover the rest of
/// `HeadingReading`. The delegate is called directly with fixed headings, so a device's own compass changes nothing.
final class DeviceHeadingTests: XCTestCase {
    @MainActor
    func testInvalidAccuracyPublishesNoHeading() {
        let device = DeviceHeading()
        device.start()
        defer { device.stop() }
        deliver(FixedHeading(trueHeading: 244, magneticHeading: 241, accuracy: 5), to: device)
        XCTAssertEqual(device.reading.degrees, 244)
        XCTAssertTrue(device.reading.isTrueNorth)
        XCTAssertEqual(device.reading.facing(bearing: 244), .aligned)
        // CoreLocation marks an invalid heading with a negative accuracy.
        deliver(FixedHeading(trueHeading: 244, magneticHeading: 241, accuracy: -1), to: device)
        XCTAssertNil(device.reading.degrees)
        XCTAssertEqual(device.reading.facing(bearing: 244), .unknown)
    }

    @MainActor
    func testMagneticHeadingWithoutALocationFix() {
        let device = DeviceHeading()
        device.start()
        defer { device.stop() }
        deliver(FixedHeading(trueHeading: -1, magneticHeading: 241, accuracy: 5), to: device)
        XCTAssertEqual(device.reading.degrees, 241)
        XCTAssertFalse(device.reading.isTrueNorth)
        XCTAssertFalse(device.reading.needsCalibration)
        deliver(FixedHeading(trueHeading: -1, magneticHeading: 241, accuracy: 30), to: device)
        XCTAssertEqual(device.reading.degrees, 241)
        XCTAssertTrue(device.reading.needsCalibration)
        XCTAssertEqual(device.reading.facing(bearing: 241), .unknown)
    }

    @MainActor
    func testOnlyAHeadingFailureDropsTheReading() {
        let device = DeviceHeading()
        device.start()
        defer { device.stop() }
        deliver(FixedHeading(trueHeading: 244, magneticHeading: 241, accuracy: 5), to: device)
        device.locationManager(CLLocationManager(), didFailWithError: CLError(.locationUnknown))
        XCTAssertEqual(device.reading.degrees, 244)
        device.locationManager(CLLocationManager(), didFailWithError: CLError(.headingFailure))
        XCTAssertNil(device.reading.degrees)
        deliver(FixedHeading(trueHeading: 244, magneticHeading: 241, accuracy: 5), to: device)
        XCTAssertEqual(device.reading.degrees, 244)
    }

    @MainActor
    func testStoppingDropsTheReadingAndIgnoresLateHeadings() {
        let device = DeviceHeading()
        device.start()
        defer { device.stop() }
        deliver(FixedHeading(trueHeading: 244, magneticHeading: 241, accuracy: 5), to: device)
        device.stop()
        XCTAssertNil(device.reading.degrees)
        deliver(FixedHeading(trueHeading: 244, magneticHeading: 241, accuracy: 5), to: device)
        XCTAssertNil(device.reading.degrees)
        device.start()
        XCTAssertNil(device.reading.degrees)
        deliver(FixedHeading(trueHeading: 244, magneticHeading: 241, accuracy: 5), to: device)
        XCTAssertEqual(device.reading.degrees, 244)
    }

    @MainActor
    private func deliver(_ heading: CLHeading, to device: DeviceHeading) {
        device.locationManager(CLLocationManager(), didUpdateHeading: heading)
    }
}

/// A heading with given values; CLHeading has no initializer that takes them.
private final class FixedHeading: CLHeading {
    private let fixedTrueHeading: CLLocationDirection
    private let fixedMagneticHeading: CLLocationDirection
    private let fixedAccuracy: CLLocationDirection

    init(trueHeading: CLLocationDirection, magneticHeading: CLLocationDirection, accuracy: CLLocationDirection) {
        fixedTrueHeading = trueHeading
        fixedMagneticHeading = magneticHeading
        fixedAccuracy = accuracy
        super.init()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var trueHeading: CLLocationDirection { fixedTrueHeading }
    override var magneticHeading: CLLocationDirection { fixedMagneticHeading }
    override var headingAccuracy: CLLocationDirection { fixedAccuracy }
}
