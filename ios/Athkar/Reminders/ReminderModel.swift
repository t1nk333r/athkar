import AthkarCore
import Foundation
import Observation
import UserNotifications

/// Local reminders (NATIVE_APP_PLAN.md §7.5): the rules in SQLite, turned into pending `UNNotificationRequest`s by
/// `ReminderPlanner`. The whole plan is rebuilt on every trigger (foreground, clock or zone change, a rule, the
/// location or the calculation settings, a period completed or reopened, an import); requests keep stable IDs, so
/// rebuilding replaces them instead of adding duplicates. Permission is asked only when a reminder is turned on.
@MainActor
@Observable
final class ReminderModel {
    enum Authorization: Equatable {
        case notDetermined, denied, allowed
    }

    private(set) var rules: [String: ReminderRule] = [:]
    private(set) var authorization: Authorization = .notDetermined
    /// The earliest pending reminder as iOS holds it, after the last replan.
    private(set) var nextPending: (title: String, fireAt: Date)?

    @ObservationIgnored private let repository: ReminderRepository
    @ObservationIgnored private let report: (any Error) -> Void
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    /// Supplies what the planner needs from the rest of the app at planning time.
    @ObservationIgnored var inputs: () -> PlanInputs? = { nil }
    @ObservationIgnored private var replanTask: Task<Void, Never>?

    struct PlanInputs {
        let zone: TimeZone
        let schedule: (String) -> PrayerSchedule?
        let completeToday: Set<Period>
    }

    /// Prefixes of the request IDs this model owns (`PlannedNotification.id`).
    private static let ownedPrefixes = ["adhkar.", "prayer."]
    nonisolated static let ruleIdKey = "ruleId"
    nonisolated static let targetKey = "target"

    init(repository: ReminderRepository, report: @escaping (any Error) -> Void) throws {
        self.repository = repository
        self.report = report
        rules = Dictionary(uniqueKeysWithValues: try repository.rules().map { ($0.id, $0) })
    }

    // MARK: Rules

    func isEnabled(_ period: Period) -> Bool { rules[ReminderRule.adhkarId(period)]?.enabled ?? false }

    func prayerRule(_ key: ReminderRule.PrayerKey) -> ReminderRule? { rules[ReminderRule.prayerId(key)] }

    var anyEnabled: Bool { rules.values.contains { $0.enabled && $0.kind != .personal } }

    func setAdhkar(_ period: Period, enabled: Bool) async {
        save(.adhkar(period, enabled: enabled, updatedAt: Date()))
        if enabled { await requestAuthorization() }
        replan()
    }

    /// Turns a prayer's reminder on or off, or moves it (`offsetMinutes` from the prayer; negative is before).
    func setPrayer(_ key: ReminderRule.PrayerKey, enabled: Bool, offsetMinutes: Int) async {
        save(.prayer(key, offsetMinutes: offsetMinutes, enabled: enabled, updatedAt: Date()))
        if enabled { await requestAuthorization() }
        replan()
    }

    private func save(_ rule: ReminderRule) {
        do {
            try repository.save(rule)
            rules[rule.id] = rule
        } catch {
            report(error)
        }
    }

    /// Rules changed outside this model (a backup import).
    func reload() {
        do {
            rules = Dictionary(uniqueKeysWithValues: try repository.rules().map { ($0.id, $0) })
        } catch {
            report(error)
        }
        replan()
    }

    // MARK: Permission

    private func requestAuthorization() async {
        await refreshAuthorization()
        guard authorization == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    func refreshAuthorization() async {
        let status = await center.notificationSettings().authorizationStatus
        authorization = switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed
        }
    }

    // MARK: Planning

    /// Rebuilds the pending requests. Calls made while one runs coalesce into the next run.
    func replan() {
        replanTask?.cancel()
        replanTask = Task { [weak self] in
            await self?.performReplan()
        }
    }

    private func performReplan() async {
        await refreshAuthorization()
        let now = Date()
        let inputs = inputs()
        let zone = inputs?.zone ?? .current
        let today = SessionCalendar.localDate(of: now, in: zone)
        await recordDelivered(today: today, zone: zone)
        guard !Task.isCancelled else { return }

        var plan: [PlannedNotification] = []
        if authorization == .allowed, let inputs {
            let firedToday = Set(rules.keys.filter { (try? repository.lastShown(ruleId: $0)) == today })
            plan = ReminderPlanner.plan(now: now, zone: zone, rules: Array(rules.values), schedule: inputs.schedule,
                                        completeToday: inputs.completeToday, firedToday: firedToday)
        }

        let wanted = Set(plan.map(\.id))
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter(Self.isOwned)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { !wanted.contains($0) })
        // Today's delivered adhkar reminder goes once its period is complete (`periodIsComplete`).
        if let complete = inputs?.completeToday, !complete.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: complete.map { "adhkar.\($0.rawValue).\(today)" })
        }
        guard !Task.isCancelled else { return }
        for item in plan {
            guard let rule = ruleId(for: item) else { continue }
            let request = UNNotificationRequest(identifier: item.id, content: Self.content(item, ruleId: rule),
                                                trigger: Self.trigger(item, now: now, zone: zone))
            do {
                try await center.add(request)
            } catch {
                report(error)
            }
        }
        await refreshNextPending()
    }

    private func refreshNextPending() async {
        let next = await center.pendingNotificationRequests()
            .filter { Self.isOwned($0.identifier) }
            .compactMap { request -> (String, Date)? in
                let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                    ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                return date.map { (request.content.title, $0) }
            }
            .min { $0.1 < $1.1 }
        nextPending = next.map { (title: $0.0, fireAt: $0.1) }
    }

    private func ruleId(for item: PlannedNotification) -> String? {
        switch item.target {
        case .adhkar(let period): ReminderRule.adhkarId(period)
        case .prayer(let key): ReminderRule.prayerId(key)
        }
    }

    private static func isOwned(_ id: String) -> Bool { ownedPrefixes.contains { id.hasPrefix($0) } }

    /// Delivered notifications become `lastShown` (the PWA's `reminderPreferences.lastShown`), so a replan the same
    /// day neither repeats nor catches them up.
    private func recordDelivered(today: String, zone: TimeZone) async {
        for notification in await center.deliveredNotifications() {
            guard Self.isOwned(notification.request.identifier) else { continue }
            let date = SessionCalendar.localDate(of: notification.date, in: zone)
            guard date == today else { continue }
            markShown(ReminderPayload(notification.request.content.userInfo), localDate: date)
        }
    }

    /// Records that a reminder was shown on `localDate`.
    func markShown(_ payload: ReminderPayload, localDate: String) {
        guard let ruleId = payload.ruleId, rules[ruleId] != nil,
              (try? repository.lastShown(ruleId: ruleId)) != localDate else { return }
        do {
            try repository.setLastShown(localDate, ruleId: ruleId)
        } catch {
            report(error)
        }
    }

    // MARK: Requests

    private static func trigger(_ item: PlannedNotification, now: Date, zone: TimeZone) -> UNNotificationTrigger {
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

    static func prayerBody(_ name: String, offsetMinutes offset: Int) -> String {
        if offset == 0 { return "حان الآن وقت صلاة \(name)." }
        let minutes = minutesLabel(abs(offset))
        return offset < 0 ? "بقي \(minutes) على أذان \(name)." : "مضى \(minutes) على أذان \(name)."
    }

    /// «دقيقة واحدة»، «دقيقتان»، «٥ دقائق»، «١٥ دقيقة».
    static func minutesLabel(_ count: Int) -> String {
        switch count {
        case 1: "دقيقة واحدة"
        case 2: "دقيقتان"
        case 3...10: "\(ArabicFormat.number(count)) دقائق"
        default: "\(ArabicFormat.number(count)) دقيقة"
        }
    }

}

/// What the app reads from a reminder's `userInfo`.
struct ReminderPayload: Sendable, Equatable {
    let ruleId: String?
    /// The request ID (`PlannedNotification.id`).
    let requestId: String?

    init(ruleId: String?, requestId: String?) {
        self.ruleId = ruleId
        self.requestId = requestId
    }

    init(_ userInfo: [AnyHashable: Any]) {
        ruleId = userInfo[ReminderModel.ruleIdKey] as? String
        requestId = userInfo[ReminderModel.targetKey] as? String
    }

    /// The deck a tapped reminder opens; `nil` for a prayer reminder (it opens أوقات الصلاة).
    var deck: DeckID? {
        guard let requestId else { return nil }
        if requestId.hasPrefix("adhkar.morning.") { return .morning }
        if requestId.hasPrefix("adhkar.evening.") { return .evening }
        return nil
    }

    var isPrayer: Bool { requestId?.hasPrefix("prayer.") ?? false }
}

extension ReminderRule.PrayerKey {
    var prayerTime: PrayerTime {
        switch self {
        case .fajr: .fajr
        case .dhuhr: .dhuhr
        case .asr: .asr
        case .maghrib: .maghrib
        case .isha: .isha
        }
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
