import AthkarCore
import CoreLocation

/// One-shot device location for prayer times (NATIVE_APP_PLAN.md §7.4). Asked for only when the user taps
/// تحديد الموقع or enables a reminder without a location; when-in-use authorization only; never in the background.
/// An approximate fix is accepted without asking for temporary full accuracy. Coordinates leave this type
/// rounded to two decimals with the storage rounding. Permission has no timeout; the fix has a 15-second deadline.
@MainActor
final class DeviceLocation {
    private let request = OneShotLocationRequest { _, sink in CoreLocationRequestDriver(sink: sink) }

    func currentCoordinates() async throws(DeviceLocationError) -> GeoCoordinates {
        try await request.currentCoordinates()
    }
}

/// Each admitted call owns a different manager and delegate. A queued callback from a retired manager
/// retains its original sink/generation; it can never be labelled as belonging to the next request.
@MainActor
final class CoreLocationRequestDriver: NSObject, LocationRequestDriver {
    let manager = CLLocationManager()
    private var sink: OneShotLocationRequest.Sink?
    private var requestedFix = false

    init(sink: @escaping OneShotLocationRequest.Sink) {
        self.sink = sink
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
    }

    var authorization: LocationAuthorization { Self.authorization(manager.authorizationStatus) }

    func requestAuthorization() {
        guard sink != nil else { return }
        manager.requestWhenInUseAuthorization()
    }

    func requestFix() {
        guard sink != nil, !requestedFix else { return }
        requestedFix = true
        manager.requestLocation()
    }

    func invalidate() {
        sink = nil
        manager.delegate = nil
        if requestedFix {
            requestedFix = false
            manager.stopUpdatingLocation()
        }
    }

    static func authorization(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    static func fix(_ location: CLLocation) -> LocationFix {
        LocationFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                    horizontalAccuracy: location.horizontalAccuracy, timestamp: location.timestamp)
    }

    static func failure(_ error: any Error) -> DeviceLocationError {
        if let error = error as? CLError, error.code == .denied { return .denied }
        return .unavailable
    }
}

// The manager is created on the main thread and calls its delegate there.
extension CoreLocationRequestDriver: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        sink?(.authorization(Self.authorization(manager.authorizationStatus)))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager else { return }
        sink?(.locations(locations.map { Self.fix($0) }))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard manager === self.manager else { return }
        sink?(.failure(Self.failure(error)))
    }
}
