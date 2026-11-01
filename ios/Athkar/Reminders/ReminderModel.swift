import AthkarCore
import Foundation
import Observation

/// Local reminders (NATIVE_APP_PLAN.md §7.5): the rules in SQLite, turned into pending `UNNotificationRequest`s by
/// `ReminderPlanner`. The whole plan is rebuilt on every trigger (foreground, clock or zone change, a rule, the
/// location or the calculation settings, a period completed or reopened, an import); requests keep stable IDs, so
/// rebuilding replaces them instead of adding duplicates. Permission is asked only when a reminder is turned on.
/// A prayer the tracker records gets no notification, so every tracker write replans too. An opportunistic background
/// refresh replans while the app is not opened (`runBackgroundRefresh()`).
/// iOS's notification centre is reached through `ReminderNotificationCenter` (`ReminderNotifications.swift`), its
/// background scheduler through `ReminderRefreshScheduler` (`BackgroundRefresh.swift`).
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
    /// What the diagnostics screen shows (NATIVE_APP_PLAN.md §8.4): counts and times, never worship data.
    private(set) var diagnostics: Diagnostics

    @ObservationIgnored private let repository: ReminderRepository
    @ObservationIgnored private let report: (any Error) -> Void
    @ObservationIgnored private let center: any ReminderNotificationCenter
    /// The current instant, for rule timestamps and planning.
    @ObservationIgnored private let clock: () -> Date
    /// Supplies what the planner needs from the rest of the app at a pass's planning instant, which it is given.
    @ObservationIgnored var inputs: (Date) -> PlanInputs? = { _ in nil }
    /// Counts `replan()` calls. A pass started for an earlier count is outdated.
    @ObservationIgnored private var replanRequests = 0
    /// The single writer: it runs passes until one finishes with no newer request. Internal so tests can wait for it.
    @ObservationIgnored private(set) var replanTask: Task<Void, Never>?
    /// Asks iOS for the next background refresh; `nil` where there is none (the portable tests that do not set one).
    @ObservationIgnored var refreshScheduler: (any ReminderRefreshScheduler)?
    @ObservationIgnored private let diagnosticsStore: any ReminderDiagnosticsStore
    /// The zone of the last pass, which places the next background refresh after its midnight.
    @ObservationIgnored private var planZone: TimeZone = .current

    struct PlanInputs {
        let zone: TimeZone
        let schedule: (String) -> PrayerSchedule?
        let completeToday: Set<Period>
        /// The tracker's recorded occurrences over the horizon (`ReminderPlanner.prayerStates`).
        var prayerStates: [PrayerOccurrence: PrayerRecordState] = [:]
    }

    /// Counts and times for the diagnostics screen. A count is `nil` until a pass or a read sets it.
    struct Diagnostics: Equatable {
        /// What the last finished pass planned, and how many its budget left out.
        var planned: Int?
        var droppedByBudget: Int?
        /// The app's pending requests as iOS holds them, after the last pass or diagnostics read.
        var pending: Int?
        var lastReplanAt: Date?
        var lastBackgroundRefreshAt: Date?
        /// The last request for a background refresh: its earliest start, or `nil` when iOS refused it (the simulator
        /// does) or none was made.
        var refreshRequest: RefreshRequest?
    }

    enum RefreshRequest: Equatable {
        case accepted(earliestBegin: Date)
        case refused
    }

    /// Prefixes of the request IDs this model owns (`PlannedNotification.id`).
    private static let ownedPrefixes = ["adhkar.", "prayer."]
    nonisolated static let ruleIdKey = "ruleId"
    nonisolated static let targetKey = "target"

    init(repository: ReminderRepository, report: @escaping (any Error) -> Void,
         center: any ReminderNotificationCenter, clock: @escaping () -> Date = { Date() },
         diagnosticsStore: any ReminderDiagnosticsStore = MemoryDiagnosticsStore()) throws {
        self.repository = repository
        self.report = report
        self.center = center
        self.clock = clock
        self.diagnosticsStore = diagnosticsStore
        diagnostics = Diagnostics(lastReplanAt: diagnosticsStore.lastReplanAt,
                                  lastBackgroundRefreshAt: diagnosticsStore.lastBackgroundRefreshAt)
        rules = Dictionary(uniqueKeysWithValues: try repository.rules().map { ($0.id, $0) })
    }

    // MARK: Rules

    func isEnabled(_ period: Period) -> Bool { rules[ReminderRule.adhkarId(period)]?.enabled ?? false }

    func prayerRule(_ key: ReminderRule.PrayerKey) -> ReminderRule? { rules[ReminderRule.prayerId(key)] }

    var anyEnabled: Bool { rules.values.contains { $0.enabled && $0.kind != .personal } }

    func setAdhkar(_ period: Period, enabled: Bool) async {
        guard save(.adhkar(period, enabled: enabled, updatedAt: clock())) else { return }
        if enabled { await requestAuthorization() }
        replan()
    }

    /// Turns a prayer's reminder on or off, or moves it (`offsetMinutes` from the prayer; negative is before).
    func setPrayer(_ key: ReminderRule.PrayerKey, enabled: Bool, offsetMinutes: Int) async {
        guard save(.prayer(key, offsetMinutes: offsetMinutes, enabled: enabled, updatedAt: clock())) else { return }
        if enabled { await requestAuthorization() }
        replan()
    }

    /// A failed save is reported and changes nothing, so neither a permission request nor a replan follows it.
    private func save(_ rule: ReminderRule) -> Bool {
        do {
            try repository.save(rule)
            rules[rule.id] = rule
            return true
        } catch {
            report(error)
            return false
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
        do {
            try await center.requestAuthorization()
        } catch {
            report(error)
        }
        await refreshAuthorization()
    }

    func refreshAuthorization() async {
        authorization = await center.authorization()
    }

    // MARK: Planning

    /// Rebuilds the pending requests. One pass runs at a time; calls made while it runs coalesce into one more pass,
    /// which reads the latest rules and inputs.
    func replan() {
        replanRequests &+= 1
        guard replanTask == nil else { return }
        replanTask = Task { [weak self] in
            await self?.drainReplans()
        }
    }

    /// A replan the caller waits for: a notification action or a background refresh, which iOS may suspend once it
    /// returns.
    func replanAndWait() async {
        replan()
        await replanTask?.value
    }

    private func drainReplans() async {
        var planned: Int
        repeat {
            planned = replanRequests
            await performReplan(planned)
        } while planned != replanRequests
        replanTask = nil
    }

    /// One pass for request `generation`. Once a newer request arrives it stops at its next check, so it never
    /// removes, adds or publishes for an outdated plan. Nothing cancels it, so an `add` already started completes
    /// before the next pass reads what is pending.
    private func performReplan(_ generation: Int) async {
        func isCurrent() -> Bool { generation == replanRequests }

        let status = await center.authorization()
        authorization = status
        guard isCurrent() else { return }
        let now = clock()
        let inputs = inputs(now)
        let zone = inputs?.zone ?? .current
        let today = SessionCalendar.localDate(of: now, in: zone)
        let delivered = await center.deliveredNotifications()
        guard isCurrent() else { return }
        recordDelivered(delivered, today: today, zone: zone)

        var result = ReminderPlan(notifications: [], droppedByBudget: 0)
        if status == .allowed, let inputs {
            let firedToday = Set(rules.keys.filter { (try? repository.lastShown(ruleId: $0)) == today })
            result = ReminderPlanner.makePlan(now: now, zone: zone, rules: Array(rules.values),
                                              schedule: inputs.schedule, completeToday: inputs.completeToday,
                                              firedToday: firedToday, prayerStates: inputs.prayerStates)
        }
        let plan = result.notifications

        let wanted = Set(plan.map(\.id))
        let pending = await center.pendingRequests().map(\.id).filter(Self.isOwned)
        guard isCurrent() else { return }
        center.removePendingRequests(withIdentifiers: pending.filter { !wanted.contains($0) })
        // Today's delivered adhkar reminder goes once its period is complete (`periodIsComplete`), and a prayer's once
        // the tracker records it.
        let settled = (inputs?.completeToday ?? []).map { "adhkar.\($0.rawValue).\(today)" }
            + (inputs?.prayerStates ?? [:])
            .filter { $0.key.date == today && $0.value != .unrecorded }
            .map { "prayer.\($0.key.prayer.rawValue).\(today)" }.sorted()
        if !settled.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: settled)
        }
        for item in plan {
            guard isCurrent() else { return }
            guard let rule = ruleId(for: item) else { continue }
            do {
                try await center.add(ReminderRequest(item: item, ruleId: rule, now: now, zone: zone))
            } catch {
                // An outdated pass leaves the failure to the newer one, which adds every wanted request again.
                if isCurrent() { report(error) }
            }
        }

        let held = await center.pendingRequests().filter { Self.isOwned($0.id) }
        let next = held
            .compactMap { request -> (String, Date)? in request.fireAt.map { (request.title, $0) } }
            .min { $0.1 < $1.1 }
        guard isCurrent() else { return }
        nextPending = next.map { (title: $0.0, fireAt: $0.1) }
        planZone = zone
        diagnostics.planned = plan.count
        diagnostics.droppedByBudget = result.droppedByBudget
        diagnostics.pending = held.count
        diagnostics.lastReplanAt = now
        diagnosticsStore.lastReplanAt = now
    }

    /// «حذف كل البيانات», after the rules were deleted: reads them again and replans, which leaves nothing pending,
    /// removes every delivered notification the app owns, then forgets the diagnostics times (the replan's included).
    func eraseAll() async {
        reload()
        await replanAndWait()
        let pending = await center.pendingRequests().map(\.id).filter(Self.isOwned)
        if !pending.isEmpty { center.removePendingRequests(withIdentifiers: pending) }
        let delivered = await center.deliveredNotifications().map(\.id).filter(Self.isOwned)
        if !delivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: delivered) }
        nextPending = nil
        diagnosticsStore.lastReplanAt = nil
        diagnosticsStore.lastBackgroundRefreshAt = nil
        diagnostics = Diagnostics(pending: 0)
    }

    // MARK: Diagnostics and background refresh

    /// Reads what the diagnostics screen shows from iOS again: the permission and the pending requests.
    func refreshDiagnostics() async {
        await refreshAuthorization()
        let pending = await center.pendingRequests().filter { Self.isOwned($0.id) }.count
        diagnostics.pending = pending
    }

    /// The `BGAppRefreshTask` identifier, also listed in Info.plist's `BGTaskSchedulerPermittedIdentifiers`.
    nonisolated static let refreshTaskIdentifier = "local.dev.athkar.reminders.refresh"

    /// Asks iOS for one background refresh, not before the next local midnight: a new day enters the horizon then.
    /// iOS decides whether and when it runs. Called on going to the background and from each refresh.
    func scheduleBackgroundRefresh() {
        guard let refreshScheduler else { return }
        let earliest = Self.nextRefresh(after: clock(), zone: planZone)
        do {
            try refreshScheduler.submit(earliestBegin: earliest)
            diagnostics.refreshRequest = .accepted(earliestBegin: earliest)
        } catch {
            // Not a failed save: iOS refuses where there is no background refresh (the simulator, or the user's
            // «تحديث التطبيق في الخلفية» turned off). The diagnostics screen shows it.
            diagnostics.refreshRequest = .refused
        }
    }

    /// One background refresh run: the next one is asked for first, in case iOS ends this run early, then a replan
    /// that is waited for.
    func runBackgroundRefresh() async {
        let now = clock()
        diagnostics.lastBackgroundRefreshAt = now
        diagnosticsStore.lastBackgroundRefreshAt = now
        scheduleBackgroundRefresh()
        await replanAndWait()
    }

    /// Five minutes after the next local midnight in `zone`.
    nonisolated static func nextRefresh(after now: Date, zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        return tomorrow.addingTimeInterval(5 * 60)
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
    private func recordDelivered(_ delivered: [DeliveredReminder], today: String, zone: TimeZone) {
        for notification in delivered {
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

/// Asks iOS for a background refresh: `BGTaskScheduler` in the app (`BackgroundRefresh.swift`), a recording scheduler
/// in the tests.
@MainActor
protocol ReminderRefreshScheduler: AnyObject {
    /// Replaces any refresh already asked for. Throws when iOS refuses it.
    func submit(earliestBegin: Date) throws
}

/// Where the diagnostics times are kept between launches: not in SQLite, so they never reach a backup.
@MainActor
protocol ReminderDiagnosticsStore: AnyObject {
    var lastReplanAt: Date? { get set }
    var lastBackgroundRefreshAt: Date? { get set }
}

/// The app's diagnostics times, in `UserDefaults`.
@MainActor
final class UserDefaultsDiagnosticsStore: ReminderDiagnosticsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastReplanAt: Date? {
        get { defaults.object(forKey: "diagnostics.lastReplanAt") as? Date }
        set { defaults.set(newValue, forKey: "diagnostics.lastReplanAt") }
    }

    var lastBackgroundRefreshAt: Date? {
        get { defaults.object(forKey: "diagnostics.lastBackgroundRefreshAt") as? Date }
        set { defaults.set(newValue, forKey: "diagnostics.lastBackgroundRefreshAt") }
    }
}

/// Diagnostics times for one model's lifetime: the tests.
@MainActor
final class MemoryDiagnosticsStore: ReminderDiagnosticsStore {
    var lastReplanAt: Date?
    var lastBackgroundRefreshAt: Date?

    init() {}
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

    /// The occurrence a prayer reminder belongs to, from its ID `prayer.<key>.<local_date>`: the notification's own
    /// date, whatever the date is when it is acted on.
    var occurrence: PrayerOccurrence? {
        guard let requestId else { return nil }
        let parts = requestId.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "prayer", let prayer = ObligatoryPrayer(rawValue: parts[1]),
              LocalDate.epochDay(parts[2]) != nil else { return nil }
        return PrayerOccurrence(date: parts[2], prayer: prayer)
    }
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
