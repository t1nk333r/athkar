import AthkarCore
import CoreLocation

enum DeviceLocationError: Error, Equatable {
    /// The user refused location for this app (or turned Location Services off).
    case denied
    /// Parental controls or a profile forbid location.
    case restricted
    /// A request is already running.
    case busy
    /// The device could not get a fix.
    case unavailable
}

/// One-shot device location for prayer times (NATIVE_APP_PLAN.md §7.4). Asked for only when the user taps
/// تحديد الموقع or enables a reminder without a location; when-in-use authorization only; never in the background.
/// An approximate (reduced accuracy) fix is used as it is: prayer times move by seconds per kilometre, so the app
/// never asks for temporary full accuracy. The fix is rounded to two decimals with the storage rounding before it
/// leaves this type.
@MainActor
final class DeviceLocation: NSObject {
    private let manager = CLLocationManager()
    private var authorizationRequest: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationRequest: CheckedContinuation<CLLocation, any Error>?

    override init() {
        super.init()
        manager.delegate = self
        // Two decimals is about 1 km, so there is nothing to gain from a finer fix.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Asks for when-in-use permission if it was never asked, then for a single fix.
    func currentCoordinates() async throws(DeviceLocationError) -> GeoCoordinates {
        guard authorizationRequest == nil, locationRequest == nil else { throw .busy }

        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                authorizationRequest = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: break
        case .restricted: throw .restricted
        default: throw .denied
        }

        let location: CLLocation
        do {
            location = try await withCheckedThrowingContinuation { continuation in
                locationRequest = continuation
                manager.requestLocation()
            }
        } catch let error as CLError where error.code == .denied {
            throw .denied
        } catch {
            throw .unavailable
        }
        return GeoCoordinates(latitude: LocationProfile.rounded(location.coordinate.latitude),
                              longitude: LocationProfile.rounded(location.coordinate.longitude))
    }
}

// The manager is created on the main thread, so it calls its delegate there.
extension DeviceLocation: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Also called when the delegate is set; only a decision ends the wait.
        guard manager.authorizationStatus != .notDetermined, let request = authorizationRequest else { return }
        authorizationRequest = nil
        request.resume(returning: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let request = locationRequest else { return }
        locationRequest = nil
        request.resume(returning: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard let request = locationRequest else { return }
        locationRequest = nil
        request.resume(throwing: error)
    }
}
