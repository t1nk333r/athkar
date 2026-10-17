import AthkarCore
import Foundation
import Observation

/// Today's adhkar session for both periods: the PWA's `athkar-progress-v2` state, kept in the database through
/// `AdhkarSessionStore` after every change, with the deck order (`buildDeck`) and each period's current card.
///
/// Each change is worked out on a copy of the state, saved, and shown only once the database has accepted it. A
/// rejected save is reported and leaves the committed state, cards and positions as they were, with no change to
/// act on (no haptic, advance or completion dialog).
@MainActor
@Observable
final class AdhkarSessionModel {
    private(set) var state: SessionState
    private(set) var cards = SessionPeriods<[DeckCard]>(morning: [], evening: [])
    private(set) var indices = SessionPeriods(morning: 0, evening: 0)
    private(set) var longAdhkarLast: Bool

    /// The date ``roll(to:)`` could not load. Until it loads, ``state`` is still the earlier day's.
    @ObservationIgnored private var pendingDay: String?
    @ObservationIgnored private var decks = SessionPeriods<[SessionItem]>(morning: [], evening: [])
    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let store: AdhkarSessionStore
    @ObservationIgnored let collections: SessionCollections
    @ObservationIgnored private let contents: [String: AdhkarItemContent]
    @ObservationIgnored private let numbers: [String: Int]
    @ObservationIgnored private let report: (any Error) -> Void

    init(database: AppDatabase, content: BundledContent, longAdhkarLast: Bool, today: String,
         report: @escaping (any Error) -> Void) throws {
        self.database = database
        collections = content.packs.adhkar
        store = AdhkarSessionStore(database: database, collections: collections)
        contents = Dictionary(uniqueKeysWithValues: (content.adhkar.morning + content.adhkar.evening).map { ($0.id, $0) })
        var numbers: [String: Int] = [:]
        for period in Period.allCases {
            for (offset, item) in collections[period].enumerated() { numbers[item.id] = offset + 1 }
        }
        self.numbers = numbers
        self.longAdhkarLast = longAdhkarLast
        self.report = report
        state = try store.load(date: today)
        rebuildDecks()
        indices = SessionPeriods(morning: firstIncompleteIndex(.morning), evening: firstIncompleteIndex(.evening))
        refresh()
    }

    // MARK: Day

    /// `ensureCurrentDay`: a new local date starts from that date's rows (none yet, on a real rollover), each
    /// deck on its first unread card. Nothing is deleted; the finished day is already history in the database.
    ///
    /// If the rows cannot be read, the earlier day stays on screen with its date, so the caller's next
    /// `ensureCurrentDay` tries again. An empty state for `today` would look loaded, and its first save would
    /// delete that date's saved rows.
    func roll(to today: String) {
        guard today != state.date else {
            pendingDay = nil
            return
        }
        let loaded: SessionState
        do {
            loaded = try store.load(date: today)
        } catch {
            pendingDay = today
            report(error)
            return
        }
        pendingDay = nil
        state = loaded
        rebuildDecks()
        indices = SessionPeriods(morning: firstIncompleteIndex(.morning), evening: firstIncompleteIndex(.evening))
        refresh()
    }

    // MARK: Counters

    func tap(_ period: Period, at index: Int) -> DeckChange? {
        guard let item = decks[period][safe: index], !item.review, dayIsCurrent() else { return nil }
        let target = state.target(for: item, in: period)
        let before = state.count(for: item, in: period)
        guard before < target else { return nil }
        var candidate = state
        candidate.progress[period][item.id] = .number(Double(before + 1))
        let sync = candidate.syncCompletion(period, in: collections, now: Date())
        guard commit(candidate) else { return nil }
        refresh()
        let completesItem = before + 1 == target
        return DeckChange(completedCard: completesItem, completedDeck: sync.newlyCompleted,
                          advance: completesItem && !sync.newlyCompleted)
    }

    /// The target picker's `change` handler: the count is clamped to the new target; with long adhkar last the
    /// deck is rebuilt around the item (its length may have changed), otherwise a target that completes the item
    /// advances.
    func setTarget(_ target: Int, _ period: Period, at index: Int) -> DeckChange? {
        guard let item = decks[period][safe: index], let options = item.targetOptions, options.contains(target),
              dayIsCurrent()
        else { return nil }
        let wasComplete = state.count(for: item, in: period) >= state.target(for: item, in: period)
        var candidate = state
        candidate.targets[period][item.id] = .number(Double(target))
        candidate.progress[period][item.id] = .number(Double(min(candidate.count(for: item, in: period), target)))
        let sync = candidate.syncCompletion(period, in: collections, now: Date())
        guard commit(candidate) else { return nil }
        if sync.newlyCompleted {
            refresh()
            return DeckChange(completedDeck: true)
        }
        if longAdhkarLast {
            applyLongOrder(true, active: period, focusing: item.id)
            return DeckChange()
        }
        refresh()
        let isComplete = state.count(for: item, in: period) >= state.target(for: item, in: period)
        return DeckChange(advance: !wasComplete && isComplete)
    }

    /// `requestItemReset`: counters of 50 and more ask first.
    func resetConfirmation(_ period: Period, at index: Int) -> DeckConfirmation? {
        guard let item = decks[period][safe: index] else { return nil }
        let count = state.count(for: item, in: period)
        guard count > 0, state.target(for: item, in: period) >= 50, let number = numbers[item.id] else { return nil }
        return DeckConfirmation(title: "إعادة عداد الذكر \(ArabicFormat.number(number))؟",
                                message: "سيعود العداد من \(ArabicFormat.number(count)) إلى الصفر.")
    }

    func resetCard(_ period: Period, at index: Int) {
        guard let item = decks[period][safe: index], state.count(for: item, in: period) > 0, dayIsCurrent()
        else { return }
        var candidate = state
        candidate.progress[period][item.id] = .number(0)
        _ = candidate.syncCompletion(period, in: collections, now: Date())
        guard commit(candidate) else { return }
        refresh()
    }

    func show(_ period: Period, at index: Int) {
        indices[period] = max(0, min(index, decks[period].count - 1))
    }

    func canMoveForward(_ period: Period, from index: Int) -> Bool {
        guard let item = decks[period][safe: index] else { return false }
        return item.review || state.count(for: item, in: period) >= state.target(for: item, in: period)
            || state.isManuallyComplete(period)
    }

    // MARK: Manual completion and long order

    /// `setManualCompletion`: `false` when nothing changed: the counters already complete the period, which the
    /// toggle cannot undo, or the change was not saved.
    @discardableResult
    func setManualCompletion(_ period: Period, completed: Bool) -> Bool {
        var candidate = state
        guard candidate.setManualCompletion(period, completed: completed, in: collections, now: Date()),
              dayIsCurrent(), commit(candidate)
        else { return false }
        refresh()
        return true
    }

    /// `applyLongOrder`: rebuilds both decks; the active period stays on the same item (or its first unread card
    /// if the item is gone), the other period restarts at its first unread card.
    func applyLongOrder(_ enabled: Bool, active: Period, focusing itemID: String? = nil) {
        let focus = itemID ?? decks[active][safe: indices[active]]?.id
        longAdhkarLast = enabled
        rebuildDecks()
        let other: Period = active == .morning ? .evening : .morning
        indices[active] = focus.flatMap { id in decks[active].firstIndex { $0.id == id } } ?? firstIncompleteIndex(active)
        indices[other] = firstIncompleteIndex(other)
        refresh()
    }

    // MARK: Scoped reset (both periods, as in the PWA)

    var canReset: Bool { state.hasResettableState(in: collections) }

    func confirmation(for scope: ResetScope) -> DeckConfirmation? {
        let recorded: Int
        switch scope {
        case .day:
            return nil
        case .week:
            recorded = (try? database.adhkar.completedDayCount(.week(endingAt: Date(), in: .current),
                                                               before: state.date)) ?? 0
        case .everything:
            recorded = (try? database.adhkar.completedDayCount(.all, before: state.date)) ?? 0
        }
        return scope.confirmation(recordedDays: recorded)
    }

    /// A rejected save leaves every record, the cards and their positions as they were. After a saved week or
    /// everything reset, history is reread from the database; if that read fails, the saved state stays shown.
    func reset(_ scope: ResetScope) {
        guard dayIsCurrent() else { return }
        let now = Date()
        var candidate = state
        let removal: HistoryRemoval?
        switch scope {
        case .day:
            candidate.resetDay()
            removal = nil
        case .week:
            candidate.resetWeek(now: now, timeZone: .current)
            removal = .week(endingAt: now, in: .current)
        case .everything:
            candidate.resetEverything()
            removal = .all
        }
        do {
            if let removal {
                try store.save(candidate, removing: removal, at: now)
            } else {
                try store.save(candidate, at: now)
            }
        } catch {
            report(error)
            return
        }
        state = candidate
        if removal != nil {
            do {
                state = try store.load(date: state.date)
            } catch {
                report(error)
            }
        }
        indices = SessionPeriods(morning: 0, evening: 0)
        refresh()
    }

    // MARK: Presentation

    func summary(_ period: Period) -> DeckSummary {
        let title = Self.title(period)
        let items = collections[period].filter { !$0.review }
        let completed = items.filter { state.count(for: $0, in: period) >= state.target(for: $0, in: period) }.count
        let countersComplete = completed == items.count
        let manually = !countersComplete && state.isManuallyComplete(period)
        let suffix = period == .morning && collections.morning.contains(where: \.review) ? " ذكرًا متاحًا" : " ذكرًا"
        let copy = manually
            ? "اكتملت \(title) خارج التطبيق"
            : countersComplete
                ? "اكتملت \(title) اليوم"
                : "\(ArabicFormat.number(completed)) من \(ArabicFormat.number(items.count))\(suffix)"
        return DeckSummary(
            copy: copy, value: countersComplete || manually ? items.count : completed, total: items.count,
            isComplete: countersComplete || manually,
            accessibilityLabel: manually
                ? "\(title) مكتملة خارج التطبيق"
                : "\(title): \(ArabicFormat.number(completed)) من \(ArabicFormat.number(items.count)) مكتملة")
    }

    func isComplete(_ period: Period) -> Bool { state.isComplete(period, in: collections) }

    /// The periods complete on `localDate`, a reminder pass's own date: none unless the session shows that date.
    /// While a new day cannot be loaded, the session still shows the day before, whose completion must not hold
    /// back the new day's reminders.
    func completedPeriods(on localDate: String) -> Set<Period> {
        guard state.date == localDate else { return [] }
        return Set(Period.allCases.filter { isComplete($0) })
    }

    func countersComplete(_ period: Period) -> Bool { state.countersComplete(period, in: collections) }

    func isManuallyComplete(_ period: Period) -> Bool { state.isManuallyComplete(period) }

    func completion(_ period: Period) -> DeckCompletion {
        let other: Period = period == .morning ? .evening : .morning
        let completedAt = state.completedAt[period].flatMap {
            try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0)
        }
        return DeckCompletion(
            title: "اكتملت \(Self.title(period)) بحمد الله", message: "تم حفظ إكمال اليوم محليًا على هذا الجهاز.",
            time: completedAt.map { "وقت الإكمال: \(ArabicFormat.time($0))" }, dismissTitle: "تم",
            primaryTitle: "الانتقال إلى \(Self.title(other))", primary: .open(other == .morning ? .morning : .evening))
    }

    static func title(_ period: Period) -> String {
        period == .morning ? DeckDefinition.morning.title : DeckDefinition.evening.title
    }

    // MARK: Private

    private func firstIncompleteIndex(_ period: Period) -> Int {
        state.firstIncompleteIndex(in: decks[period], period: period)
    }

    private func rebuildDecks() {
        for period in Period.allCases {
            decks[period] = state.deck(period, in: collections, longAdhkarLast: longAdhkarLast)
        }
    }

    /// Saves `candidate`, then makes it the state. A rejected save is reported once and changes nothing.
    private func commit(_ candidate: SessionState) -> Bool {
        do {
            try store.save(candidate)
        } catch {
            report(error)
            return false
        }
        state = candidate
        return true
    }

    /// `false` while a day ``roll(to:)`` could not load is pending: ``state`` still belongs to the day before, and
    /// saving a change would write that day's rows. The load is retried, and the change is dropped either way, as a
    /// tap that rolls the day is.
    private func dayIsCurrent() -> Bool {
        guard let day = pendingDay else { return true }
        roll(to: day)
        return false
    }

    private func refresh() {
        for period in Period.allCases {
            cards[period] = decks[period].map { card($0, period) }
            indices[period] = max(0, min(indices[period], decks[period].count - 1))
        }
    }

    /// `cardMarkup`, `updateCard` and `progressLabel` for one item.
    private func card(_ item: SessionItem, _ period: Period) -> DeckCard {
        guard let content = contents[item.id] else {
            preconditionFailure("adhkar item \(item.id) has no card content (BundledContent.validate checks this)")
        }
        let number = numbers[item.id] ?? 0
        let n = ArabicFormat.number(number)
        let target = state.target(for: item, in: period)
        let count = state.count(for: item, in: period)
        let complete = count >= target
        let label = content.isCounted
            ? "ذكر \(n)، تم تكراره \(ArabicFormat.number(count)) من أصل \(ArabicFormat.number(target)) مرات"
                + (complete ? "، اكتمل" : "")
            : count >= 1 ? "ذكر \(n)، تمت قراءته" : "ذكر \(n)، لم يُعلَّم كمقروء"
        return DeckCard(
            id: item.id, number: number, content: .dhikr(content), count: count, target: target,
            requirement: content.countLabel ?? "مرة واحدة", targetOptions: item.targetOptions,
            status: content.isCounted ? .numeric : .text(complete ? "تمت القراءة" : "اضغط بعد القراءة"),
            isReview: item.review, progressLabel: label,
            tapLabel: content.isCounted
                ? "زيادة عداد الذكر \(n). \(label)"
                : "\(count > 0 ? "اكتمل" : "تحديد كمقروء")، الذكر \(n). \(label)",
            resetLabel: "إعادة عداد الذكر \(n)", targetLabel: "اختيار عدد تكرار الذكر \(n)")
    }
}

/// One adhkar period's deck over the shared session.
@MainActor
final class AdhkarDeckModel: DeckModel {
    let period: Period
    let session: AdhkarSessionModel
    let definition: DeckDefinition

    init(period: Period, session: AdhkarSessionModel) {
        self.period = period
        self.session = session
        definition = period == .morning ? .morning : .evening
    }

    var cards: [DeckCard] { session.cards[period] }
    var currentIndex: Int { session.indices[period] }
    var summary: DeckSummary { session.summary(period) }
    var isComplete: Bool { session.isComplete(period) }
    var completion: DeckCompletion { session.completion(period) }
    var canReset: Bool { session.canReset }

    func show(_ index: Int) { session.show(period, at: index) }
    func canMoveForward(from index: Int) -> Bool { session.canMoveForward(period, from: index) }
    func tap(cardAt index: Int) -> DeckChange? { session.tap(period, at: index) }
    func setTarget(_ target: Int, forCardAt index: Int) -> DeckChange? { session.setTarget(target, period, at: index) }
    func resetConfirmation(forCardAt index: Int) -> DeckConfirmation? { session.resetConfirmation(period, at: index) }
    func resetCard(at index: Int) { session.resetCard(period, at: index) }
    func confirmation(for scope: ResetScope) -> DeckConfirmation? { session.confirmation(for: scope) }
    func reset(_ scope: ResetScope) { session.reset(scope) }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
