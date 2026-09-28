import CoreLocation
import Observation

/// The device's compass heading while the القبلة screen is open. Heading needs no permission; a true-north heading
/// needs location updates, which run only if the user already allowed location (never asked for here), at kilometre
/// accuracy and only while the screen is visible. Otherwise the heading is magnetic.
@MainActor
@Observable
final class DeviceHeading: NSObject {
    /// Degrees from north, clockwise, where the top of the phone points; `nil` before the first reading.
    private(set) var degrees: Double?
    /// From true north (`true`) or magnetic north.
    private(set) var isTrueNorth = false
    /// Worse than this many degrees, the compass needs calibrating.
    private(set) var needsCalibration = false

    let isAvailable = CLLocationManager.headingAvailable()

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 1
        manager.headingOrientation = .portrait
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        guard isAvailable else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
    }
}

// The manager is created on the main thread, so it calls its delegate there.
extension DeviceHeading: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        let trueNorth = heading.trueHeading >= 0
        degrees = trueNorth ? heading.trueHeading : heading.magneticHeading
        isTrueNorth = trueNorth
        needsCalibration = heading.headingAccuracy < 0 || heading.headingAccuracy > 20
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}
