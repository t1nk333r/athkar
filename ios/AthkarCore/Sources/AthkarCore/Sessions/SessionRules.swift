import Foundation

// Session rules ported from the PWA (`index.html`). Each method names the function it reproduces; the
// fixtures in `spec/sessions/fixtures/` are the contract.

// MARK: - Counters and completion

extension SessionState {
    /// `targetForState(item, period, state)`: a stored target counts only if it is one of the item's
    /// `targetOptions` (compared after `Number()`), otherwise `defaultTarget`; items without options use
    /// `count || 1`. An item with options but no `defaultTarget` (which the content validator rejects) is
    /// treated as having no options; the PWA would return `undefined` there.
    public func target(for item: SessionItem, in period: Period) -> Int {
        if let options = item.targetOptions, let defaultTarget = item.defaultTarget {
            let stored = targets[period][item.id]?.numberValue ?? .nan
            return options.first { Double($0) == stored } ?? defaultTarget
        }
        return item.count.flatMap { $0 == 0 ? nil : $0 } ?? 1
    }

    /// `countForState(item, period, state)`: `Number()` of the stored counter; non-finite or negative is 0;
    /// otherwise floored and clamped to the target.
    public func count(for item: SessionItem, in period: Period) -> Int {
        let raw = progress[period][item.id]?.numberValue ?? .nan
        guard raw.isFinite, raw >= 0 else { return 0 }
        return Int(min(raw.rounded(.down), Double(target(for: item, in: period))))
    }

    /// `periodCountersComplete(period, state)`: every non-review item has reached its target.
    /// A period with no non-review items is complete.
    public func countersComplete(_ period: Period, in collections: SessionCollections) -> Bool {
        collections[period].allSatisfy { $0.review || count(for: $0, in: period) >= target(for: $0, in: period) }
    }

    /// `periodIsManuallyComplete(period, state)`.
    public func isManuallyComplete(_ period: Period) -> Bool {
        manualCompletion[period]
    }

    /// `periodIsComplete(period, state)`: complete by counters or marked complete manually.
    public func isComplete(_ period: Period, in collections: SessionCollections) -> Bool {
        countersComplete(period, in: collections) || isManuallyComplete(period)
    }
}

// MARK: - Day rollover

extension SessionState {
    /// `historyEntryFor(state)`: today's outcome as a history entry.
    public func historyEntry(in collections: SessionCollections) -> HistoryEntry {
        HistoryEntry(
            date: date,
            morning: isComplete(.morning, in: collections),
            evening: isComplete(.evening, in: collections),
            morningAt: completedAt.morning,
            eveningAt: completedAt.evening
        )
    }

    /// `rollStateToDate(state, nextDate)`: an empty state for `nextDate` whose history starts with this day's
    /// entry (replacing any entry with the same date), capped at ``historyLimit``. Days in between get no entry.
    public func rolled(to nextDate: String, in collections: SessionCollections) -> SessionState {
        let previous = historyEntry(in: collections)
        var rolled = SessionState.empty(date: nextDate)
        rolled.history = [previous] + history.lazy.filter { $0.date != previous.date }.prefix(Self.historyLimit - 1)
        return rolled
    }
}

// MARK: - Deck order

extension SessionState {
    /// `isLongDhikr(item, period)`: a non-review item whose current target is at least ``longDhikrThreshold``.
    public func isLongDhikr(_ item: SessionItem, in period: Period) -> Bool {
        !item.review && target(for: item, in: period) >= Self.longDhikrThreshold
    }

    /// `buildDeck(period)`: content order, or, with `longAdhkarLast`, long items moved (in order) to just before
    /// the last item. The last item stays last; decks shorter than three items are never reordered.
    public func deck(_ period: Period, in collections: SessionCollections, longAdhkarLast: Bool) -> [SessionItem] {
        let items = collections[period]
        guard longAdhkarLast, items.count >= 3, let last = items.last else { return items }
        let rest = items.dropLast()
        return rest.filter { !isLongDhikr($0, in: period) } + rest.filter { isLongDhikr($0, in: period) } + [last]
    }

    /// `firstIncompleteIndex(period)`: index in `deck` of the first non-review item below its target; the last
    /// index when there is none; 0 for an empty deck. Manual completion does not affect it.
    public func firstIncompleteIndex(in deck: [SessionItem], period: Period) -> Int {
        deck.firstIndex { !$0.review && count(for: $0, in: period) < target(for: $0, in: period) }
            ?? max(0, deck.count - 1)
    }
}

// MARK: - Completion bookkeeping

extension SessionState {
    /// Result of ``syncCompletion(_:in:now:)``.
    public struct CompletionSync: Codable, Sendable, Equatable {
        public var complete: Bool
        /// Counters just completed the period (it was neither manually complete nor stamped before):
        /// the PWA opens its completion dialog.
        public var newlyCompleted: Bool

        public init(complete: Bool, newlyCompleted: Bool) {
            self.complete = complete
            self.newlyCompleted = newlyCompleted
        }
    }

    /// `syncCompletionState(period)`, run after a counter or target change: counter completion clears the manual
    /// flag; a complete period gets `completedAt = now` unless already stamped; an incomplete one loses it.
    public mutating func syncCompletion(_ period: Period, in collections: SessionCollections, now: Date) -> CompletionSync {
        let byCounters = countersComplete(period, in: collections)
        let manually = isManuallyComplete(period)
        let complete = byCounters || manually
        let stamped = Self.isTruthy(completedAt[period])
        let newlyCompleted = byCounters && !manually && !stamped
        if byCounters { manualCompletion[period] = false }
        if complete {
            if !stamped { completedAt[period] = SessionCalendar.isoString(now) }
        } else if stamped {
            completedAt[period] = nil
        }
        return CompletionSync(complete: complete, newlyCompleted: newlyCompleted)
    }

    /// `setManualCompletion(period, completed)`: marks the period done (or not) outside the app. Ignored while
    /// the counters already complete the period. Marking keeps an existing `completedAt`, else stamps `now`;
    /// unmarking clears it.
    ///
    /// - Returns: `false` when the change was ignored because the counters are complete.
    @discardableResult
    public mutating func setManualCompletion(
        _ period: Period,
        completed: Bool,
        in collections: SessionCollections,
        now: Date
    ) -> Bool {
        if countersComplete(period, in: collections) { return false }
        manualCompletion[period] = completed
        completedAt[period] = completed
            ? (Self.isTruthy(completedAt[period]) ? completedAt[period] : SessionCalendar.isoString(now))
            : nil
        return true
    }

    /// A stored timestamp is "set" when it is a non-empty string (JavaScript truthiness).
    private static func isTruthy(_ timestamp: String?) -> Bool {
        !(timestamp?.isEmpty ?? true)
    }
}

// MARK: - Scoped reset

extension SessionState {
    /// `hasResettableState()`: any non-review counter above zero, any manual completion, or any history.
    public func hasResettableState(in collections: SessionCollections) -> Bool {
        let anyProgress = Period.allCases.contains { period in
            collections[period].contains { !$0.review && count(for: $0, in: period) > 0 }
        }
        let anyManual = Period.allCases.contains { isManuallyComplete($0) }
        return anyProgress || anyManual || !history.isEmpty
    }

    /// `resetDayProgress()`: clears today's counters, `completedAt` and manual flags. Targets, date and history
    /// are kept.
    public mutating func resetDay() {
        for period in Period.allCases {
            progress[period] = [:]
            completedAt[period] = nil
            manualCompletion[period] = false
        }
    }

    /// `resetWeek()` (confirmed): removes history entries dated within the last seven local dates of `now`
    /// (today inclusive, per `recentDates(7)`), then resets the day.
    ///
    /// - Returns: The seven local dates of the window, newest first.
    @discardableResult
    public mutating func resetWeek(now: Date, timeZone: TimeZone) -> [String] {
        let window = SessionCalendar.recentDates(7, endingAt: now, in: timeZone)
        history.removeAll { window.contains($0.date) }
        resetDay()
        return window
    }

    /// `resetEverything()` (confirmed): removes all history, then resets the day.
    public mutating func resetEverything() {
        history = []
        resetDay()
    }
}
