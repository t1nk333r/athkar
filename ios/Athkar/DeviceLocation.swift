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
    /// The calling task was cancelled (for example, its view went away while the system prompt was up).
    case cancelled
}

/// One-shot device location for prayer times (NATIVE_APP_PLAN.md §7.4). Asked for only when the user taps
/// تحديد الموقع or enables a reminder without a location; when-in-use authorization only; never in the background.
/// An approximate (reduced accuracy) fix is used as it is: prayer times move by seconds per kilometre, so the app
/// never asks for temporary full accuracy. The fix is rounded to two decimals with the storage rounding before it
/// leaves this type.
///
/// Both waits end when the calling task is cancelled, which frees the type for the next call. The permission prompt
/// has no timeout of its own: the system keeps it up until the user answers, and a caller that stops waiting cancels
/// its task. A late answer only updates the authorization status the next call reads.
@MainActor
final class DeviceLocation: NSObject {
    private let manager = CLLocationManager()
    /// Resumed with the decision, or `nil` when the wait is cancelled.
    private var authorizationRequest: CheckedContinuation<CLAuthorizationStatus?, Never>?
    private var locationRequest: CheckedContinuation<CLLocation, any Error>?
    /// Counts admitted calls. A cancellation reaches the main actor one hop late, so it carries its call's number
    /// and does nothing once a later call has been admitted.
    private var generation = 0

    override init() {
        super.init()
        manager.delegate = self
        // Two decimals is about 1 km, so there is nothing to gain from a finer fix.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Asks for when-in-use permission if it was never asked, then for a single fix.
    func currentCoordinates() async throws(DeviceLocationError) -> GeoCoordinates {
        guard authorizationRequest == nil, locationRequest == nil else { throw .busy }
        generation &+= 1
        let call = generation

        var status = manager.authorizationStatus
        if status == .notDetermined {
            let decision = await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<CLAuthorizationStatus?, Never>) in
                    guard !Task.isCancelled else { return continuation.resume(returning: nil) }
                    authorizationRequest = continuation
                    manager.requestWhenInUseAuthorization()
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.cancelAuthorizationWait(call) }
            }
            guard let decision else { throw .cancelled }
            status = decision
        }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: break
        case .restricted: throw .restricted
        default: throw .denied
        }

        let location: CLLocation
        do {
            location = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    guard !Task.isCancelled else { return continuation.resume(throwing: CancellationError()) }
                    locationRequest = continuation
                    manager.requestLocation()
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.cancelLocationWait(call) }
            }
        } catch is CancellationError {
            throw .cancelled
        } catch let error as CLError where error.code == .denied {
            throw .denied
        } catch {
            throw .unavailable
        }
        return GeoCoordinates(latitude: LocationProfile.rounded(location.coordinate.latitude),
                              longitude: LocationProfile.rounded(location.coordinate.longitude))
    }

    // Each pending continuation is taken (set to nil) before it is resumed, all on the main actor, so the delegate
    // and a cancellation can never both resume it. A cancellation for an earlier call finds a newer `generation`:
    // its own wait already ended, and the pending one belongs to the next caller.

    private func cancelAuthorizationWait(_ call: Int) {
        guard call == generation, let request = authorizationRequest else { return }
        authorizationRequest = nil
        request.resume(returning: nil)
    }

    private func cancelLocationWait(_ call: Int) {
        guard call == generation, let request = locationRequest else { return }
        locationRequest = nil
        manager.stopUpdatingLocation() // also cancels a pending `requestLocation()`
        request.resume(throwing: CancellationError())
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
