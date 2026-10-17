import AthkarCore

/// What the القبلة compass may show from CoreLocation's headings, kept free of CoreLocation so Linux tests can run it.
/// A heading counts only while updates run and only when CoreLocation could determine it: a negative accuracy marks an
/// invalid heading, and a negative true heading means no location fix, so the magnetic heading is used and disclosed.
/// Stopping, a heading failure or an invalid heading drops the reading until the next valid heading, and headings that
/// arrive after stopping are ignored. A heading the compass needs calibrating to trust still turns the dial, but says
/// nothing about facing the Qibla.
struct HeadingReading {
    /// Degrees from north, clockwise, where the top of the phone points; `nil` without a usable heading.
    private(set) var degrees: Double?
    /// From true north (`true`) or magnetic north.
    private(set) var isTrueNorth = false
    /// Worse than ``calibrationAccuracy`` degrees, the compass needs calibrating.
    private(set) var needsCalibration = false
    private var isUpdating = false

    static let calibrationAccuracy = 20.0

    /// Accepts headings until ``stop()``. Starting again while running keeps the current reading.
    mutating func start() {
        isUpdating = true
    }

    /// Drops the reading and ignores headings until the next ``start()``.
    mutating func stop() {
        self = HeadingReading()
    }

    /// CoreLocation's `trueHeading`, `magneticHeading` and `headingAccuracy`.
    mutating func update(trueHeading: Double, magneticHeading: Double, accuracy: Double) {
        guard isUpdating else { return }
        let trueNorth = Self.isDirection(trueHeading)
        let direction = trueNorth ? trueHeading : magneticHeading
        guard accuracy.isFinite, accuracy >= 0, Self.isDirection(direction) else {
            fail()
            return
        }
        degrees = direction
        isTrueNorth = trueNorth
        needsCalibration = accuracy > Self.calibrationAccuracy
    }

    /// Drops the reading when CoreLocation could not determine the heading. It keeps trying, and its next valid
    /// heading restores the reading.
    mutating func fail() {
        degrees = nil
        isTrueNorth = false
        needsCalibration = false
    }

    /// What the screen may say about facing the Qibla at `bearing`: only the bearing itself without a heading or while
    /// the compass needs calibrating.
    func facing(bearing: Double) -> QiblaFacing {
        guard let degrees, !needsCalibration else { return .unknown }
        return Qibla.isAligned(bearing: bearing, heading: degrees) ? .aligned : .away
    }

    /// The note under the status. Magnetic north is disclosed only when true north is unavailable.
    func note(compassAvailable: Bool) -> CompassNote {
        if !compassAvailable { return .noCompass }
        if degrees == nil { return .waiting }
        if needsCalibration { return .needsCalibration }
        return isTrueNorth ? .ready : .magneticNorth
    }

    /// CoreLocation's documented range, which also rules out NaN and infinities.
    private static func isDirection(_ value: Double) -> Bool {
        (0..<360).contains(value)
    }
}

/// What the القبلة screen says about facing the Qibla; it also sets the screen's colours and the haptic.
enum QiblaFacing {
    /// No heading, or one the compass needs calibrating to trust: the bearing from north only.
    case unknown
    /// A confident heading off the Qibla: which way to turn.
    case away
    /// A confident heading within `Qibla.isAligned`'s tolerance.
    case aligned
}

/// The note under the القبلة status, in order of precedence.
enum CompassNote {
    /// The device has no compass: measure the bearing from north by hand.
    case noCompass
    /// No usable heading yet.
    case waiting
    case needsCalibration
    /// No location fix, so the heading is from magnetic north.
    case magneticNorth
    /// A calibrated heading from true north.
    case ready
}

/// The haptic on facing the Qibla: once each time the phone turns onto it, and only with the haptics setting on. Only a
/// confident heading off the Qibla arms it again, so losing the heading or a calibration dip while facing the Qibla
/// does not replay it.
struct AlignmentHaptic {
    private var armed = true

    /// Notes what the screen says now, and returns whether to play the haptic.
    mutating func update(_ facing: QiblaFacing, haptics: Bool) -> Bool {
        switch facing {
        case .unknown:
            return false
        case .away:
            armed = true
            return false
        case .aligned:
            defer { armed = false }
            return haptics && armed
        }
    }
}
