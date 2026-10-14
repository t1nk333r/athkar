import AthkarCore
import Foundation
import Observation

/// Local reminders (NATIVE_APP_PLAN.md §7.5): the rules in SQLite, turned into pending `UNNotificationRequest`s by
/// `ReminderPlanner`. The whole plan is rebuilt on every trigger (foreground, clock or zone change, a rule, the
/// location or the calculation settings, a period completed or reopened, an import); requests keep stable IDs, so
/// rebuilding replaces them instead of adding duplicates. Permission is asked only when a reminder is turned on.
/// iOS's notification centre is reached through `ReminderNotificationCenter` (`ReminderNotifications.swift`).
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
    @ObservationIgnored private let center: any ReminderNotificationCenter
    /// The current instant, for rule timestamps and planning.
    @ObservationIgnored private let clock: () -> Date
    /// Supplies what the planner needs from the rest of the app at planning time.
    @ObservationIgnored var inputs: () -> PlanInputs? = { nil }
    /// Internal so tests can wait for it.
    @ObservationIgnored private(set) var replanTask: Task<Void, Never>?

    struct PlanInputs {
        let zone: TimeZone
        let schedule: (String) -> PrayerSchedule?
        let completeToday: Set<Period>
    }

    /// Prefixes of the request IDs this model owns (`PlannedNotification.id`).
    private static let ownedPrefixes = ["adhkar.", "prayer."]
    nonisolated static let ruleIdKey = "ruleId"
    nonisolated static let targetKey = "target"

    init(repository: ReminderRepository, report: @escaping (any Error) -> Void,
         center: any ReminderNotificationCenter, clock: @escaping () -> Date = { Date() }) throws {
        self.repository = repository
        self.report = report
        self.center = center
        self.clock = clock
        rules = Dictionary(uniqueKeysWithValues: try repository.rules().map { ($0.id, $0) })
    }

    // MARK: Rules

    func isEnabled(_ period: Period) -> Bool { rules[ReminderRule.adhkarId(period)]?.enabled ?? false }

    func prayerRule(_ key: ReminderRule.PrayerKey) -> ReminderRule? { rules[ReminderRule.prayerId(key)] }

    var anyEnabled: Bool { rules.values.contains { $0.enabled && $0.kind != .personal } }

    func setAdhkar(_ period: Period, enabled: Bool) async {
        save(.adhkar(period, enabled: enabled, updatedAt: clock()))
        if enabled { await requestAuthorization() }
        replan()
    }

    /// Turns a prayer's reminder on or off, or moves it (`offsetMinutes` from the prayer; negative is before).
    func setPrayer(_ key: ReminderRule.PrayerKey, enabled: Bool, offsetMinutes: Int) async {
        save(.prayer(key, offsetMinutes: offsetMinutes, enabled: enabled, updatedAt: clock()))
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
        _ = try? await center.requestAuthorization()
        await refreshAuthorization()
    }

    func refreshAuthorization() async {
        authorization = await center.authorization()
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
        let now = clock()
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
        let pending = await center.pendingRequests().map(\.id).filter(Self.isOwned)
        center.removePendingRequests(withIdentifiers: pending.filter { !wanted.contains($0) })
        // Today's delivered adhkar reminder goes once its period is complete (`periodIsComplete`).
        if let complete = inputs?.completeToday, !complete.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: complete.map { "adhkar.\($0.rawValue).\(today)" })
        }
        guard !Task.isCancelled else { return }
        for item in plan {
            guard let rule = ruleId(for: item) else { continue }
            do {
                try await center.add(ReminderRequest(item: item, ruleId: rule, now: now, zone: zone))
            } catch {
                report(error)
            }
        }
        await refreshNextPending()
    }

    private func refreshNextPending() async {
        let next = await center.pendingRequests()
            .filter { Self.isOwned($0.id) }
            .compactMap { request -> (String, Date)? in request.fireAt.map { (request.title, $0) } }
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
            guard Self.isOwned(notification.id) else { continue }
            let date = SessionCalendar.localDate(of: notification.date, in: zone)
            guard date == today else { continue }
            markShown(ReminderPayload(ruleId: notification.ruleId, requestId: notification.id), localDate: date)
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

    // MARK: Wording

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

/// The notification centre calls reminders make, in the app's own types: `UNUserNotificationCenter` in the app
/// (`ReminderNotifications.swift`), a controlled centre in the portable tests.
@MainActor
protocol ReminderNotificationCenter: AnyObject {
    func authorization() async -> ReminderModel.Authorization
    /// Asks for alert, sound and badge permission.
    func requestAuthorization() async throws
    func deliveredNotifications() async -> [DeliveredReminder]
    func pendingRequests() async -> [PendingReminder]
    func removePendingRequests(withIdentifiers ids: [String])
    func removeDeliveredNotifications(withIdentifiers ids: [String])
    /// Adds a request, replacing a pending one with the same ID. Cancellation does not stop it: once called, it
    /// completes.
    func add(_ request: ReminderRequest) async throws
}

/// A delivered notification: its request ID, the rule in its payload, and when it was shown.
struct DeliveredReminder: Equatable, Sendable {
    let id: String
    let ruleId: String?
    let date: Date
}

/// A pending request: its ID, title and next fire date.
struct PendingReminder: Equatable, Sendable {
    let id: String
    let title: String
    let fireAt: Date?
}

/// A planned notification to add, the rule it comes from, and the instant and zone it was planned in: a catch-up's
/// delay and a calendar trigger's wall clock come from them.
struct ReminderRequest: Equatable, Sendable {
    let item: PlannedNotification
    let ruleId: String
    let now: Date
    let zone: TimeZone
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
