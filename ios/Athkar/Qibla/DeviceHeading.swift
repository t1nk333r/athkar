import CoreLocation
import Observation

/// The device's compass heading while the القبلة screen is open. Heading needs no permission; a true-north heading
/// needs location updates, which run only if the user already allowed location (never asked for here), at kilometre
/// accuracy and only while the screen is visible. Otherwise the heading is magnetic.
@MainActor
@Observable
final class DeviceHeading: NSObject {
    /// The heading the screen may use: empty while stopped and after an invalid heading or a heading failure.
    private(set) var reading = HeadingReading()

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
        reading.start()
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
        reading.stop()
    }
}

// The manager is created on the main thread, so it calls its delegate there.
extension DeviceHeading: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        reading.update(trueHeading: heading.trueHeading, magneticHeading: heading.magneticHeading,
                       accuracy: heading.headingAccuracy)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    /// Interference can stop CoreLocation determining the heading; it keeps trying, and its next valid heading restores
    /// the reading. A location error costs only true north, which the next heading reports.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        if (error as? CLError)?.code == .headingFailure { reading.fail() }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}
