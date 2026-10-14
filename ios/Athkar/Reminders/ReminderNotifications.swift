import AthkarCore
import Foundation
import UserNotifications

/// `ReminderNotificationCenter` on iOS's `UNUserNotificationCenter` (NATIVE_APP_PLAN.md §7.5).
@MainActor
final class UserNotificationCenterAdapter: ReminderNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    func authorization() async -> ReminderModel.Authorization {
        Self.authorization(await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func deliveredNotifications() async -> [DeliveredReminder] {
        await center.deliveredNotifications().map { notification in
            DeliveredReminder(id: notification.request.identifier,
                              ruleId: ReminderPayload(notification.request.content.userInfo).ruleId,
                              date: notification.date)
        }
    }

    func pendingRequests() async -> [PendingReminder] {
        await center.pendingNotificationRequests().map { Self.pending($0) }
    }

    func removePendingRequests(withIdentifiers ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removeDeliveredNotifications(withIdentifiers ids: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    func add(_ request: ReminderRequest) async throws {
        try await center.add(Self.request(request))
    }

    static func authorization(_ status: UNAuthorizationStatus) -> ReminderModel.Authorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed
        }
    }

    static func request(_ request: ReminderRequest) -> UNNotificationRequest {
        UNNotificationRequest(identifier: request.item.id,
                              content: ReminderModel.content(request.item, ruleId: request.ruleId),
                              trigger: ReminderModel.trigger(request.item, now: request.now, zone: request.zone))
    }

    static func pending(_ request: UNNotificationRequest) -> PendingReminder {
        let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        return PendingReminder(id: request.identifier, title: request.content.title, fireAt: date)
    }
}

extension ReminderModel {
    /// The app's reminders, on iOS's notification centre.
    convenience init(repository: ReminderRepository, report: @escaping (any Error) -> Void) throws {
        try self.init(repository: repository, report: report, center: UserNotificationCenterAdapter())
    }

    // MARK: Requests

    fileprivate static func trigger(_ item: PlannedNotification, now: Date, zone: TimeZone) -> UNNotificationTrigger {
        if item.isCatchUp {
            return UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.fireAt.timeIntervalSince(now)),
                                                     repeats: false)
        }
        // A calendar trigger follows the wall clock, so a clock change before the next replan does not shift it.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireAt)
        components.timeZone = zone
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    static func content(_ item: PlannedNotification, ruleId: String) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = [ruleIdKey: ruleId, targetKey: item.id]
        switch item.target {
        case .adhkar(let period):
            // The PWA's `showReminder` wording.
            let section = AdhkarSessionModel.title(period)
            let prayer = period == .morning ? "الفجر" : "العصر"
            content.title = section
            content.body = "مرّت ساعة على صلاة \(prayer). حان وقت \(section)."
            content.threadIdentifier = "adhkar"
        case .prayer(let key):
            let name = PrayerNames.name(key.prayerTime)
            content.title = "صلاة \(name)"
            content.body = prayerBody(name, offsetMinutes: item.offsetMinutes)
            content.threadIdentifier = "prayer"
        }
        return content
    }
}

/// Receives notifications while the app runs and their taps. Set as the centre's delegate at launch, before the app
/// finishes launching, so a tap that cold-launches the app is delivered.
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ReminderNotificationDelegate()

    @MainActor private final class Handlers {
        var onShown: ((ReminderPayload, Date) -> Void)?
        var onOpen: ((ReminderPayload) -> Void)?
        /// A tap that arrived before the app model existed.
        var pendingOpen: ReminderPayload?
    }

    @MainActor private static let handlers = Handlers()

    /// Called by the running app: a reminder was shown (with its delivery date), or tapped.
    @MainActor func attach(onShown: @escaping (ReminderPayload, Date) -> Void,
                           onOpen: @escaping (ReminderPayload) -> Void) {
        let handlers = Self.handlers
        handlers.onShown = onShown
        handlers.onOpen = onOpen
        if let pending = handlers.pendingOpen {
            handlers.pendingOpen = nil
            onOpen(pending)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        let payload = ReminderPayload(notification.request.content.userInfo)
        let date = notification.date
        await MainActor.run { Self.handlers.onShown?(payload, date) }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let payload = ReminderPayload(response.notification.request.content.userInfo)
        let date = response.notification.date
        await MainActor.run {
            let handlers = Self.handlers
            handlers.onShown?(payload, date)
            if let onOpen = handlers.onOpen { onOpen(payload) } else { handlers.pendingOpen = payload }
        }
    }
}
