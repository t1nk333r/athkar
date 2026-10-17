import AthkarCore

/// What the القبلة compass may show from CoreLocation's headings, kept free of CoreLocation so Linux tests can run it.
/// A heading counts only while updates run and only when CoreLocation could determine it: a negative accuracy marks an
/// invalid heading, and a negative true heading means no location fix, so the magnetic heading is used and disclosed.
/// Stopping, a heading failure or an invalid heading drops the reading until the next valid heading, and headings that
/// arrive after stopping are ignored.
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

    /// Facing the Qibla (`Qibla.isAligned`); never without a usable heading.
    func isAligned(bearing: Double) -> Bool {
        guard let degrees else { return false }
        return Qibla.isAligned(bearing: bearing, heading: degrees)
    }

    /// CoreLocation's documented range, which also rules out NaN and infinities.
    private static func isDirection(_ value: Double) -> Bool {
        (0..<360).contains(value)
    }
}

/// The haptic on facing the Qibla: once each time the phone turns onto it, and only with the haptics setting on.
struct AlignmentHaptic {
    private var wasAligned = false

    /// Notes whether the phone now faces the Qibla, and returns whether to play the haptic.
    mutating func update(aligned: Bool, haptics: Bool) -> Bool {
        defer { wasAligned = aligned }
        return haptics && aligned && !wasAligned
    }
}
