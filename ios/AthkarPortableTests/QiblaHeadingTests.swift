import AthkarCore
import XCTest
@testable import AthkarModels

/// The القبلة compass policy: which CoreLocation headings count, when they stop counting, what the screen may say
/// about facing the Qibla, and when that plays the haptic. Riyadh's Qibla is about 244° from true north.
final class QiblaHeadingTests: XCTestCase {
    private let qibla = Qibla.bearing(from: GeoCoordinates(latitude: 24.71, longitude: 46.68))

    private func started() -> HeadingReading {
        var reading = HeadingReading()
        reading.start()
        return reading
    }

    /// Readings through the policy as QiblaView applies them, counting alignment haptics.
    private struct Screen {
        let bearing: Double
        var reading = HeadingReading()
        var haptic = AlignmentHaptic()
        var played = 0

        init(bearing: Double) {
            self.bearing = bearing
            reading.start()
        }

        /// A heading of `degrees` from true north.
        mutating func heading(_ degrees: Double, accuracy: Double = 5) {
            apply { $0.update(trueHeading: degrees, magneticHeading: degrees - 3, accuracy: accuracy) }
        }

        mutating func apply(_ change: (inout HeadingReading) -> Void) {
            change(&reading)
            if haptic.update(reading.facing(bearing: bearing), haptics: true) { played += 1 }
        }
    }

    func testInvalidAccuracyIsNoReadingAndNeverAligns() {
        var reading = started()
        // CoreLocation marks an invalid heading with a negative accuracy.
        for accuracy in [-1, -Double.infinity, .infinity, .nan] {
            reading.update(trueHeading: qibla, magneticHeading: qibla - 3, accuracy: 5)
            XCTAssertEqual(reading.degrees, qibla)
            XCTAssertEqual(reading.facing(bearing: qibla), .aligned)
            reading.update(trueHeading: qibla, magneticHeading: qibla - 3, accuracy: accuracy)
            XCTAssertNil(reading.degrees, "accuracy \(accuracy)")
            XCTAssertFalse(reading.isTrueNorth, "accuracy \(accuracy)")
            XCTAssertEqual(reading.facing(bearing: qibla), .unknown, "accuracy \(accuracy)")
        }
    }

    func testUnusableDirectionsAreNoReading() {
        var reading = started()
        let directions: [(Double, Double)] = [(-1, -1), (-1, .nan), (.nan, .infinity), (-.infinity, -.infinity)]
        for (trueHeading, magnetic) in directions {
            reading.update(trueHeading: qibla, magneticHeading: qibla, accuracy: 5)
            reading.update(trueHeading: trueHeading, magneticHeading: magnetic, accuracy: 5)
            XCTAssertNil(reading.degrees, "\(trueHeading), \(magnetic)")
            XCTAssertEqual(reading.facing(bearing: qibla), .unknown, "\(trueHeading), \(magnetic)")
        }
    }

    func testTrueNorthIsPreferredAndMagneticNorthIsDisclosed() {
        var reading = started()
        reading.update(trueHeading: 100, magneticHeading: 97, accuracy: 5)
        XCTAssertEqual(reading.degrees, 100)
        XCTAssertTrue(reading.isTrueNorth)
        XCTAssertEqual(reading.note(compassAvailable: true), .ready)
        // Without a location fix the true heading is negative: the magnetic one is used, and the note says so.
        reading.update(trueHeading: -1, magneticHeading: 97, accuracy: 5)
        XCTAssertEqual(reading.degrees, 97)
        XCTAssertFalse(reading.isTrueNorth)
        XCTAssertEqual(reading.note(compassAvailable: true), .magneticNorth)
        reading.update(trueHeading: 0, magneticHeading: 357, accuracy: 5)
        XCTAssertEqual(reading.degrees, 0)
        XCTAssertTrue(reading.isTrueNorth)
        XCTAssertEqual(reading.note(compassAvailable: true), .ready)
    }

    func testNoteFollowsTheCompassState() {
        var reading = HeadingReading()
        XCTAssertEqual(reading.note(compassAvailable: false), .noCompass)
        reading.start()
        XCTAssertEqual(reading.note(compassAvailable: true), .waiting)
        reading.update(trueHeading: -1, magneticHeading: 97, accuracy: 25)
        XCTAssertEqual(reading.note(compassAvailable: true), .needsCalibration, "before magnetic north")
        XCTAssertEqual(reading.note(compassAvailable: false), .noCompass)
        reading.update(trueHeading: -1, magneticHeading: 97, accuracy: 20)
        XCTAssertEqual(reading.note(compassAvailable: true), .magneticNorth)
        reading.update(trueHeading: 100, magneticHeading: 97, accuracy: 20)
        XCTAssertEqual(reading.note(compassAvailable: true), .ready)
        reading.update(trueHeading: 100, magneticHeading: 97, accuracy: -1)
        XCTAssertEqual(reading.note(compassAvailable: true), .waiting, "invalid heading")
        reading.update(trueHeading: 100, magneticHeading: 97, accuracy: 5)
        reading.fail()
        XCTAssertEqual(reading.note(compassAvailable: true), .waiting, "heading failure")
        reading.update(trueHeading: 100, magneticHeading: 97, accuracy: 5)
        reading.stop()
        XCTAssertEqual(reading.note(compassAvailable: true), .waiting, "stopped")
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

    /// While the compass needs calibrating the dial still turns, but the screen gives only the bearing from north.
    func testNoAlignmentOrTurnWhileTheCompassNeedsCalibration() {
        var reading = started()
        reading.update(trueHeading: qibla, magneticHeading: qibla - 3, accuracy: 20)
        XCTAssertEqual(reading.facing(bearing: qibla), .aligned, "20° is calibrated")
        reading.update(trueHeading: qibla, magneticHeading: qibla - 3, accuracy: 25)
        XCTAssertEqual(reading.degrees, qibla, "the dial still turns")
        XCTAssertEqual(reading.facing(bearing: qibla), .unknown, "on the bearing")
        reading.update(trueHeading: qibla + 1, magneticHeading: qibla - 2, accuracy: 25)
        XCTAssertEqual(reading.facing(bearing: qibla), .unknown, "no turn by 1°")
        reading.update(trueHeading: qibla + 90, magneticHeading: qibla + 87, accuracy: 20.5)
        XCTAssertEqual(reading.facing(bearing: qibla), .unknown, "no turn by 90°")
        reading.update(trueHeading: qibla + 90, magneticHeading: qibla + 87, accuracy: 20)
        XCTAssertEqual(reading.facing(bearing: qibla), .away)
        reading.update(trueHeading: qibla + 1, magneticHeading: qibla - 2, accuracy: 15)
        XCTAssertEqual(reading.facing(bearing: qibla), .aligned, "calibrated again")
    }

    func testValidHeadingRecoversAfterAnInvalidOne() {
        var reading = started()
        reading.update(trueHeading: qibla, magneticHeading: qibla, accuracy: -1)
        XCTAssertNil(reading.degrees)
        reading.update(trueHeading: qibla + 1, magneticHeading: qibla - 2, accuracy: 10)
        XCTAssertEqual(reading.degrees, qibla + 1)
        XCTAssertTrue(reading.isTrueNorth)
        XCTAssertEqual(reading.facing(bearing: qibla), .aligned)
    }

    func testHeadingFailureDropsTheReadingUntilTheNextValidHeading() {
        var reading = started()
        reading.update(trueHeading: qibla, magneticHeading: qibla, accuracy: 30)
        reading.fail()
        XCTAssertNil(reading.degrees)
        XCTAssertFalse(reading.isTrueNorth)
        XCTAssertFalse(reading.needsCalibration)
        XCTAssertEqual(reading.facing(bearing: qibla), .unknown)
        reading.update(trueHeading: -1, magneticHeading: qibla, accuracy: 5)
        XCTAssertEqual(reading.degrees, qibla)
        XCTAssertFalse(reading.isTrueNorth)
        XCTAssertEqual(reading.facing(bearing: qibla), .aligned)
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
        XCTAssertEqual(reading.facing(bearing: qibla), .unknown)
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
        XCTAssertFalse(haptic.update(.away, haptics: true))
        XCTAssertTrue(haptic.update(.aligned, haptics: true))
        XCTAssertFalse(haptic.update(.aligned, haptics: true), "still facing it")
        XCTAssertFalse(haptic.update(.away, haptics: true))
        XCTAssertTrue(haptic.update(.aligned, haptics: true), "turned onto it again")

        var off = AlignmentHaptic()
        XCTAssertFalse(off.update(.aligned, haptics: false))
        XCTAssertFalse(off.update(.away, haptics: false))
        XCTAssertFalse(off.update(.aligned, haptics: false))
        XCTAssertFalse(off.update(.aligned, haptics: true), "turning the setting on is not a turn onto the Qibla")
    }

    /// Only a confident heading away from the Qibla arms the haptic again; an unknown one changes nothing.
    func testUnknownFacingLeavesTheHapticAsItWas() {
        var haptic = AlignmentHaptic()
        XCTAssertFalse(haptic.update(.unknown, haptics: true))
        XCTAssertTrue(haptic.update(.aligned, haptics: true), "armed from the start")
        XCTAssertFalse(haptic.update(.unknown, haptics: true))
        XCTAssertFalse(haptic.update(.aligned, haptics: true), "losing the heading does not arm it")
        XCTAssertFalse(haptic.update(.away, haptics: true))
        XCTAssertFalse(haptic.update(.unknown, haptics: true))
        XCTAssertTrue(haptic.update(.aligned, haptics: true), "nor does it disarm it")
    }

    /// Invalid, calibrating and stopped headings at the Qibla play nothing; the first confident one plays once.
    func testOnlyAConfidentHeadingOnTheQiblaPlaysTheHaptic() {
        var screen = Screen(bearing: qibla)
        screen.heading(qibla + 40)
        screen.heading(qibla, accuracy: -1)
        screen.heading(.nan)
        screen.heading(qibla, accuracy: 25)
        XCTAssertEqual(screen.played, 0)
        screen.apply { $0.stop() }
        screen.heading(qibla)
        XCTAssertEqual(screen.played, 0, "a heading after stopping")
        screen.apply { $0.start() }
        screen.heading(qibla)
        XCTAssertEqual(screen.played, 1)
    }

    /// At the same orientation, losing the heading and getting it back does not replay the haptic; turning away with a
    /// confident heading and back does.
    func testLosingTheHeadingAtTheQiblaDoesNotReplayTheHaptic() {
        var screen = Screen(bearing: qibla)
        screen.heading(qibla)
        XCTAssertEqual(screen.played, 1)
        screen.apply { $0.fail() }
        screen.heading(qibla)
        XCTAssertEqual(screen.played, 1, "after a heading failure")
        screen.heading(qibla, accuracy: -1)
        screen.heading(qibla)
        XCTAssertEqual(screen.played, 1, "after an invalid heading")
        screen.heading(qibla, accuracy: 25)
        screen.heading(qibla + 1)
        XCTAssertEqual(screen.played, 1, "after a calibration dip")
        screen.apply { $0.stop() }
        screen.apply { $0.start() }
        screen.heading(qibla)
        XCTAssertEqual(screen.played, 1, "after stopping and starting, as in the background")
        screen.heading(qibla + 30)
        screen.heading(qibla - 1)
        XCTAssertEqual(screen.played, 2, "turned away and back")
    }
}
