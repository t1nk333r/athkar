import AthkarCore
import XCTest
@testable import AthkarModels

/// The القبلة compass policy: which CoreLocation headings count, when they stop counting, and when facing the Qibla
/// plays the haptic. Riyadh's Qibla is about 244° from true north.
final class QiblaHeadingTests: XCTestCase {
    private let qibla = Qibla.bearing(from: GeoCoordinates(latitude: 24.71, longitude: 46.68))

    private func started() -> HeadingReading {
        var reading = HeadingReading()
        reading.start()
        return reading
    }

    func testInvalidAccuracyIsNoReadingAndNeverAligns() {
        var reading = started()
        // CoreLocation marks an invalid heading with a negative accuracy.
        for accuracy in [-1, -Double.infinity, .infinity, .nan] {
            reading.update(trueHeading: qibla, magneticHeading: qibla - 3, accuracy: 5)
            XCTAssertEqual(reading.degrees, qibla)
            XCTAssertTrue(reading.isAligned(bearing: qibla))
            reading.update(trueHeading: qibla, magneticHeading: qibla - 3, accuracy: accuracy)
            XCTAssertNil(reading.degrees, "accuracy \(accuracy)")
            XCTAssertFalse(reading.isTrueNorth, "accuracy \(accuracy)")
            XCTAssertFalse(reading.isAligned(bearing: qibla), "accuracy \(accuracy)")
        }
    }

    func testUnusableDirectionsAreNoReading() {
        var reading = started()
        let directions: [(Double, Double)] = [(-1, -1), (-1, .nan), (.nan, .infinity), (-.infinity, -.infinity)]
        for (trueHeading, magnetic) in directions {
            reading.update(trueHeading: qibla, magneticHeading: qibla, accuracy: 5)
            reading.update(trueHeading: trueHeading, magneticHeading: magnetic, accuracy: 5)
            XCTAssertNil(reading.degrees, "\(trueHeading), \(magnetic)")
            XCTAssertFalse(reading.isAligned(bearing: qibla), "\(trueHeading), \(magnetic)")
        }
    }

    func testTrueNorthIsPreferredAndMagneticNorthIsDisclosed() {
        var reading = started()
        reading.update(trueHeading: 100, magneticHeading: 97, accuracy: 5)
        XCTAssertEqual(reading.degrees, 100)
        XCTAssertTrue(reading.isTrueNorth)
        // Without a location fix the true heading is negative: the magnetic one is used, and the screen says so.
        reading.update(trueHeading: -1, magneticHeading: 97, accuracy: 5)
        XCTAssertEqual(reading.degrees, 97)
        XCTAssertFalse(reading.isTrueNorth)
        reading.update(trueHeading: 0, magneticHeading: 357, accuracy: 5)
        XCTAssertEqual(reading.degrees, 0)
        XCTAssertTrue(reading.isTrueNorth)
    }

    func testCalibrationIsNeededAboveTwentyDegrees() {
        var reading = started()
        reading.update(trueHeading: 100, magneticHeading: 97, accuracy: 20)
        XCTAssertFalse(reading.needsCalibration)
        reading.update(trueHeading: 101, magneticHeading: 98, accuracy: 25)
        XCTAssertTrue(reading.needsCalibration)
        XCTAssertEqual(reading.degrees, 101)
        reading.update(trueHeading: 102, magneticHeading: 99, accuracy: 0)
        XCTAssertFalse(reading.needsCalibration)
        XCTAssertEqual(reading.degrees, 102)
    }

    func testValidHeadingRecoversAfterAnInvalidOne() {
        var reading = started()
        reading.update(trueHeading: qibla, magneticHeading: qibla, accuracy: -1)
        XCTAssertNil(reading.degrees)
        reading.update(trueHeading: qibla + 1, magneticHeading: qibla - 2, accuracy: 10)
        XCTAssertEqual(reading.degrees, qibla + 1)
        XCTAssertTrue(reading.isTrueNorth)
        XCTAssertTrue(reading.isAligned(bearing: qibla))
    }

    func testHeadingFailureDropsTheReadingUntilTheNextValidHeading() {
        var reading = started()
        reading.update(trueHeading: qibla, magneticHeading: qibla, accuracy: 30)
        reading.fail()
        XCTAssertNil(reading.degrees)
        XCTAssertFalse(reading.isTrueNorth)
        XCTAssertFalse(reading.needsCalibration)
        XCTAssertFalse(reading.isAligned(bearing: qibla))
        reading.update(trueHeading: -1, magneticHeading: qibla, accuracy: 5)
        XCTAssertEqual(reading.degrees, qibla)
        XCTAssertFalse(reading.isTrueNorth)
        XCTAssertTrue(reading.isAligned(bearing: qibla))
    }

    func testStoppingDropsTheReadingAndIgnoresLateHeadings() {
        var reading = HeadingReading()
        reading.update(trueHeading: qibla, magneticHeading: qibla, accuracy: 5)
        XCTAssertNil(reading.degrees, "before start")
        reading.start()
        reading.update(trueHeading: qibla, magneticHeading: qibla, accuracy: 30)
        XCTAssertTrue(reading.needsCalibration)
        reading.stop()
        XCTAssertNil(reading.degrees)
        XCTAssertFalse(reading.isTrueNorth)
        XCTAssertFalse(reading.needsCalibration)
        // A heading CoreLocation had already queued when it stopped.
        reading.update(trueHeading: qibla, magneticHeading: qibla, accuracy: 5)
        XCTAssertNil(reading.degrees, "after stop")
        XCTAssertFalse(reading.isAligned(bearing: qibla))
        reading.start()
        XCTAssertNil(reading.degrees, "a restart waits for a fresh heading")
        reading.update(trueHeading: qibla, magneticHeading: qibla, accuracy: 5)
        XCTAssertEqual(reading.degrees, qibla)
        // Starting again while running, as on coming back to the foreground without leaving it, keeps the reading.
        reading.start()
        XCTAssertEqual(reading.degrees, qibla)
    }

    func testAlignmentHapticPlaysOnTurningOntoTheQiblaOnlyWithTheSettingOn() {
        var haptic = AlignmentHaptic()
        XCTAssertFalse(haptic.update(aligned: false, haptics: true))
        XCTAssertTrue(haptic.update(aligned: true, haptics: true))
        XCTAssertFalse(haptic.update(aligned: true, haptics: true), "still facing it")
        XCTAssertFalse(haptic.update(aligned: false, haptics: true))
        XCTAssertTrue(haptic.update(aligned: true, haptics: true), "turned onto it again")

        var off = AlignmentHaptic()
        XCTAssertFalse(off.update(aligned: true, haptics: false))
        XCTAssertFalse(off.update(aligned: false, haptics: false))
        XCTAssertFalse(off.update(aligned: true, haptics: false))
        XCTAssertFalse(off.update(aligned: true, haptics: true), "turning the setting on is not a turn onto the Qibla")
    }

    /// Invalid, failed and stopped headings at the Qibla play nothing; the next valid one plays once.
    func testOnlyAValidHeadingPlaysTheAlignmentHaptic() {
        var reading = started()
        var haptic = AlignmentHaptic()
        var played = 0
        func show(_ change: (inout HeadingReading) -> Void) {
            change(&reading)
            if haptic.update(aligned: reading.isAligned(bearing: qibla), haptics: true) { played += 1 }
        }
        show { $0.update(trueHeading: qibla + 40, magneticHeading: qibla + 37, accuracy: 5) }
        show { $0.update(trueHeading: qibla, magneticHeading: qibla - 3, accuracy: -1) }
        show { $0.update(trueHeading: .nan, magneticHeading: .nan, accuracy: 5) }
        XCTAssertEqual(played, 0)
        show { $0.stop() }
        show { $0.update(trueHeading: qibla, magneticHeading: qibla - 3, accuracy: 5) }
        XCTAssertEqual(played, 0)
        show { $0.start() }
        show { $0.update(trueHeading: qibla, magneticHeading: qibla - 3, accuracy: 5) }
        XCTAssertEqual(played, 1)
        show { $0.fail() }
        show { $0.update(trueHeading: qibla + 1, magneticHeading: qibla - 2, accuracy: 5) }
        XCTAssertEqual(played, 2)
    }
}
