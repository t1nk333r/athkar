import AthkarCore
import Foundation

enum DeviceLocationError: Error, Equatable, Sendable {
    /// The user refused location for this app or turned Location Services off.
    case denied
    /// Parental controls or a profile forbid location.
    case restricted
    /// A request is already running.
    case busy
    /// The device could not get an acceptable fix before the deadline.
    case unavailable
    /// The calling task was cancelled.
    case cancelled
}

enum LocationAuthorization: Equatable, Sendable {
    case notDetermined, whenInUse, always, denied, restricted
}

struct LocationFix: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date
}

/// Identity cannot wrap or be reassigned to a callback from an earlier request.
final class LocationRequestGeneration: Sendable {}

enum LocationRequestEvent: Equatable, Sendable {
    case authorization(LocationAuthorization)
    case locations([LocationFix])
    case failure(DeviceLocationError)
    case cancelled
    case deadline
}

@MainActor
protocol LocationRequestDriver: AnyObject {
    var authorization: LocationAuthorization { get }
    func requestAuthorization()
    func requestFix()
    func invalidate()
}

@MainActor
protocol LocationRequestClock: AnyObject {
    var date: Date { get }
    var now: Duration { get }
    func schedule(at deadline: Duration, action: @escaping @MainActor () -> Void) -> @MainActor () -> Void
}

@MainActor
final class SystemLocationRequestClock: LocationRequestClock {
    private let clock = ContinuousClock()
    private let origin = ContinuousClock.now

    var date: Date { Date() }
    var now: Duration { origin.duration(to: clock.now) }

    func schedule(at deadline: Duration, action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        let instant = origin.advanced(by: deadline)
        let task = Task { @MainActor [clock] in
            do { try await clock.sleep(until: instant) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }
}

/// The real request policy, compiled unchanged by the app and Linux XCTest.
/// Permission has no deadline. Only the fix wait is bounded, starting after authorization.
@MainActor
final class OneShotLocationRequest {
    typealias Sink = @MainActor (LocationRequestEvent) -> Void
    typealias DriverFactory = @MainActor (LocationRequestGeneration, @escaping Sink) -> any LocationRequestDriver

    private enum Phase: Equatable { case preparing, authorization, fix }

    private final class Request {
        let generation: LocationRequestGeneration
        var phase = Phase.preparing
        var driver: (any LocationRequestDriver)?
        var deadline: Duration?
        var cancelDeadline: (@MainActor () -> Void)?
        var continuation: CheckedContinuation<Result<GeoCoordinates, DeviceLocationError>, Never>?
        // Also covers cancellation reaching the actor before the continuation is installed.
        var result: Result<GeoCoordinates, DeviceLocationError>?

        init(generation: LocationRequestGeneration) { self.generation = generation }
    }

    private let makeDriver: DriverFactory
    private let clock: any LocationRequestClock
    private let fixTimeout: Duration
    private static let maximumFixAge: TimeInterval = 300
    private static let maximumFutureSkew: TimeInterval = 5
    private var active: Request?

    init(clock: any LocationRequestClock = SystemLocationRequestClock(), fixTimeout: Duration = .seconds(15),
         makeDriver: @escaping DriverFactory) {
        self.clock = clock
        self.fixTimeout = fixTimeout
        self.makeDriver = makeDriver
    }

    func currentCoordinates() async throws(DeviceLocationError) -> GeoCoordinates {
        guard !Task.isCancelled else { throw .cancelled }
        guard active == nil else { throw .busy }
        let request = Request(generation: LocationRequestGeneration())
        active = request // Admission spans the whole operation, including every suspension.
        let generation = request.generation
        let result: Result<GeoCoordinates, DeviceLocationError> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let result = request.result {
                    continuation.resume(returning: result)
                    return
                }
                request.continuation = continuation
                guard !Task.isCancelled else {
                    finish(request, .failure(.cancelled))
                    return
                }
                let driver = makeDriver(generation) { [weak self] event in
                    self?.receive(event, for: generation)
                }
                guard active === request else { driver.invalidate(); return }
                request.driver = driver
                switch driver.authorization {
                case .notDetermined:
                    request.phase = .authorization
                    driver.requestAuthorization()
                case .whenInUse, .always: requestFix(request)
                case .denied: finish(request, .failure(.denied))
                case .restricted: finish(request, .failure(.restricted))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.receive(.cancelled, for: generation) }
        }
        return try result.get()
    }

    /// Driver events, scheduled deadlines, and caller cancellation use this same handler.
    /// Internal access permits ordered late-event replays without replacing the implementation.
    func receive(_ event: LocationRequestEvent, for generation: LocationRequestGeneration) {
        guard let request = active, request.generation === generation else { return }
        switch event {
        case .cancelled: finish(request, .failure(.cancelled))
        case .deadline:
            guard request.phase == .fix, let deadline = request.deadline, clock.now >= deadline else { return }
            finish(request, .failure(.unavailable))
        case let .authorization(status):
            guard request.phase != .preparing else { return }
            switch status {
            case .notDetermined:
                if request.phase == .fix { finish(request, .failure(.denied)) }
            case .whenInUse, .always:
                if request.phase == .authorization { requestFix(request) }
            case .denied: finish(request, .failure(.denied))
            case .restricted: finish(request, .failure(.restricted))
            }
        case let .locations(locations):
            guard request.phase == .fix, let deadline = request.deadline else { return }
            // A queued fix cannot win just because the timeout Task has not reached the actor yet.
            guard clock.now < deadline, let fix = newestAcceptableFix(locations) else {
                finish(request, .failure(.unavailable))
                return
            }
            finish(request, .success(GeoCoordinates(latitude: LocationProfile.rounded(fix.latitude),
                                                   longitude: LocationProfile.rounded(fix.longitude))))
        case let .failure(error):
            guard request.phase == .fix else { return }
            finish(request, .failure(error))
        }
    }

    private func requestFix(_ request: Request) {
        request.phase = .fix
        let deadline = clock.now + fixTimeout
        request.deadline = deadline
        let generation = request.generation
        let cancel = clock.schedule(at: deadline) { [weak self] in
            self?.receive(.deadline, for: generation)
        }
        guard active === request else { cancel(); return }
        request.cancelDeadline = cancel
        request.driver?.requestFix()
    }

    private func newestAcceptableFix(_ locations: [LocationFix]) -> LocationFix? {
        let now = clock.date
        var newest: LocationFix?
        for fix in locations {
            let age = now.timeIntervalSince(fix.timestamp)
            guard fix.latitude.isFinite, (-90...90).contains(fix.latitude),
                  fix.longitude.isFinite, (-180...180).contains(fix.longitude),
                  fix.horizontalAccuracy.isFinite, fix.horizontalAccuracy >= 0,
                  fix.timestamp.timeIntervalSinceReferenceDate.isFinite, age.isFinite,
                  (-Self.maximumFutureSkew...Self.maximumFixAge).contains(age) else { continue }
            // No upper accuracy cutoff: reduced-accuracy fixes are valid for prayer calculations.
            // A five-minute cache is acceptable; allow five seconds of future timestamp skew.
            if let previous = newest, fix.timestamp < previous.timestamp { continue }
            newest = fix
        }
        return newest
    }

    private func finish(_ request: Request, _ result: Result<GeoCoordinates, DeviceLocationError>) {
        guard active === request else { return }
        let continuation = request.continuation
        request.continuation = nil
        request.result = result
        active = nil // Clear ownership before teardown can synchronously deliver another callback.
        request.cancelDeadline?()
        request.cancelDeadline = nil
        request.driver?.invalidate()
        request.driver = nil
        continuation?.resume(returning: result)
    }
}
