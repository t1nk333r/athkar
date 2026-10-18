import AthkarCore
import Foundation
@testable import AthkarModels

/// The production `ReminderNotificationCenter` protocol under the test's control: state a test sets and reads, a log
/// of every call, and calls a test can hold mid-flight. A held call returns only when the test resumes it, and
/// nothing cancels it, as nothing cancels iOS's `add`. Real titles and trigger dates belong to the native adapter
/// tests.
@MainActor
final class ControlledReminderCenter: ReminderNotificationCenter {
    enum Call: Hashable {
        case authorization, requestAuthorization, delivered, pending, add
    }

    enum Event: Equatable {
        case authorization, requestAuthorization, delivered, pending
        case removePending([String]), removeDelivered([String])
        /// An `add` was called; `added` or `addFailed` follows when it returns.
        case add(String), added(String), addFailed(String)
    }

    /// One held call, resumed by the test.
    @MainActor
    final class Held {
        let call: Call
        /// The request ID of a held `add`.
        let id: String?
        private var continuation: CheckedContinuation<Void, any Error>?
        private var outcome: Result<Void, any Error>?

        fileprivate init(call: Call, id: String?) {
            self.call = call
            self.id = id
        }

        /// Lets the call return, or fail with `error`.
        func resume(throwing error: (any Error)? = nil) {
            let outcome: Result<Void, any Error> = error.map { .failure($0) } ?? .success(())
            if let continuation {
                self.continuation = nil
                continuation.resume(with: outcome)
            } else {
                self.outcome = outcome
            }
        }

        fileprivate func wait() async throws {
            if let outcome { return try outcome.get() }
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }

    var status: ReminderModel.Authorization = .allowed
    /// What `requestAuthorization()` grants, unless `requestError` makes it throw.
    var grant: ReminderModel.Authorization = .allowed
    var requestError: (any Error)?
    var delivered: [DeliveredReminder] = []
    /// Another feature's pending requests, which reminders must leave alone.
    var foreignPending: [PendingReminder] = []
    /// Adds that fail every time, by request ID.
    var addErrors: [String: any Error] = [:]
    /// This app's pending requests in the order added; adding an ID again replaces its request.
    private(set) var requests: [ReminderRequest] = []
    private(set) var events: [Event] = []

    private var holds: [Call: Int] = [:]
    private var parked: [Call: [Held]] = [:]
    private var waiters: [Call: [CheckedContinuation<Held, Never>]] = [:]

    /// The IDs of every `add` called, in order.
    var adds: [String] {
        events.compactMap { event -> String? in
            guard case .add(let id) = event else { return nil }
            return id
        }
    }

    /// The IDs of each `removePendingRequests` call, in order.
    var pendingRemovals: [[String]] {
        events.compactMap { event -> [String]? in
            guard case .removePending(let ids) = event else { return nil }
            return ids
        }
    }

    func count(_ event: Event) -> Int { events.filter { $0 == event }.count }

    /// Holds the next call of this kind until the test resumes it.
    func hold(_ call: Call) { holds[call, default: 0] += 1 }

    /// Waits until a held call of this kind has arrived.
    func held(_ call: Call) async -> Held {
        if let held = parked[call]?.first {
            parked[call]?.removeFirst()
            return held
        }
        return await withCheckedContinuation { waiters[call, default: []].append($0) }
    }

    // MARK: ReminderNotificationCenter

    func authorization() async -> ReminderModel.Authorization {
        events.append(.authorization)
        try? await gate(.authorization)
        return status
    }

    func requestAuthorization() async throws {
        events.append(.requestAuthorization)
        try await gate(.requestAuthorization)
        if let requestError { throw requestError }
        status = grant
    }

    func deliveredNotifications() async -> [DeliveredReminder] {
        events.append(.delivered)
        try? await gate(.delivered)
        return delivered
    }

    func pendingRequests() async -> [PendingReminder] {
        events.append(.pending)
        try? await gate(.pending)
        return requests.map { PendingReminder(id: $0.item.id, title: $0.item.id, fireAt: $0.item.fireAt) }
            + foreignPending
    }

    func removePendingRequests(withIdentifiers ids: [String]) {
        events.append(.removePending(ids))
        requests.removeAll { ids.contains($0.item.id) }
        foreignPending.removeAll { ids.contains($0.id) }
    }

    func removeDeliveredNotifications(withIdentifiers ids: [String]) {
        events.append(.removeDelivered(ids))
        delivered.removeAll { ids.contains($0.id) }
    }

    func add(_ request: ReminderRequest) async throws {
        let id = request.item.id
        events.append(.add(id))
        do {
            try await gate(.add, id: id)
            if let error = addErrors[id] { throw error }
        } catch {
            events.append(.addFailed(id))
            throw error
        }
        requests.removeAll { $0.item.id == id }
        requests.append(request)
        events.append(.added(id))
    }

    /// Suspends a held call until the test resumes it; any other call passes straight through.
    private func gate(_ call: Call, id: String? = nil) async throws {
        guard let count = holds[call], count > 0 else { return }
        holds[call] = count - 1
        let held = Held(call: call, id: id)
        if let waiter = waiters[call]?.first {
            waiters[call]?.removeFirst()
            waiter.resume(returning: held)
        } else {
            parked[call, default: []].append(held)
        }
        try await held.wait()
    }
}
