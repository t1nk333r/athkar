import AthkarCore
import Foundation
import Observation

/// What a reading card shows (spec/sessions/deck-definition.md §12 "Cards"), in this order and each only when the
/// item has it: the title as the heading, the prefix, each Quran passage under its basmala with its citation below,
/// the text, the numbered steps and the note.
struct ReadingCardContent: Equatable, Sendable {
    /// A Quran passage set in the mushaf face as a «سور» page sets ayahs.
    struct Passage: Equatable, Sendable {
        /// The suwar pack's basmala above a passage that opens a sura; `nil` otherwise.
        var basmala: String?
        /// Uthmani text closed by its ayah markers ﴿n﴾.
        var text: String
        /// «البقرة ٢٥٥», «الملك».
        var citation: String
    }

    var title: String?
    var prefix: String?
    var passages: [Passage] = []
    var text: String?
    var steps: [String] = []
    var note: String?
    /// Salawat's opening card starts with «ليلة الجمعة» or «يوم الجمعة» from Thursday's Maghrib to Friday's Maghrib.
    var showsFridayPill = false

    /// The quick index row's opening text: the title, or the text (cut to two lines by layout), or the citation of a
    /// card that has neither.
    var indexOpening: String {
        title ?? text ?? passages.first?.citation ?? ""
    }
}

/// A reading deck: «أذكار النوم» (`content/sleep.v1.json`, the PWA's `athkar-sleep-v1`) or «الصلاة على النبي ﷺ»
/// (`content/salawat.v1.json`, `athkar-salawat-v1`), one card per item in pack order without sections (§12). Today's
/// counts and whether today is recorded complete are stored in `reading_item_progress` and `reading_days`. Situational
/// sleep items and salawat's opening card are shown but never counted, never lock and stay outside progress. A change
/// is shown only once its transaction is stored, and a day only once it has been read.
@MainActor
@Observable
final class ReadingDeckModel: DeckModel {
    /// The salawat opening card's ID: al-Ahzab 56 and the Friday virtue.
    nonisolated static let salawatOpeningID = "salawat-quran"

    let definition: DeckDefinition
    let deck: ReadingDeck
    private(set) var cards: [DeckCard] = []
    private(set) var currentIndex = 0
    /// The local date the deck shows.
    private(set) var date: String
    /// Today's stored counts (`counts`), raw: read through ``count(of:)``.
    private(set) var counts: [String: Int]
    /// Today's `reading_days` row (`completedAt`). The row alone records the day complete.
    private(set) var completedDay: ReadingDay?
    /// An earlier day is recorded complete.
    private(set) var hasHistory: Bool

    /// One card's definition: its content, and its target or, for an uncounted card, the phrase its footer shows.
    private struct Item {
        var id: String
        var content: ReadingCardContent
        /// `nil` for an uncounted card.
        var target: Int?
        var requirement: String
        /// An uncounted card's footer («عند الحاجة», «اقرأ ثم اسحب») and its spoken state.
        var uncounted: (footer: String, label: String)?
    }

    @ObservationIgnored private let items: [Item]
    @ObservationIgnored private let repository: ReadingRepository
    @ObservationIgnored private let report: (any Error) -> Void

    init(_ deck: ReadingDeck, database: AppDatabase, content: BundledContent, today: String,
         report: @escaping (any Error) -> Void) throws {
        self.deck = deck
        definition = deck == .sleep ? .sleep : .salawat
        items = deck == .sleep ? Self.items(content.sleep) : Self.items(content.salawat)
        repository = database.reading
        self.report = report
        date = today
        counts = try repository.counts(deck, on: today)
        completedDay = try repository.day(deck, on: today)
        hasHistory = try repository.recordedDayCount(deck, .all, before: today) > 0
        currentIndex = openingIndex()
        refresh()
    }

    /// `ensureCurrentDay`: a new day starts with that day's counts and opens on its first incomplete card. A day that
    /// cannot be read is not shown: the deck keeps its day, so the next `ensureCurrentDay` tries again.
    func roll(to today: String) {
        guard today != date else { return }
        load(today)
    }

    /// After a backup import or «حذف كل البيانات»: the day on screen is read again and opens on its first incomplete
    /// card. A day that cannot be read keeps what is on screen.
    func reload() {
        load(date)
    }

    private func load(_ today: String) {
        do {
            let counts = try repository.counts(deck, on: today)
            let day = try repository.day(deck, on: today)
            let hasHistory = try repository.recordedDayCount(deck, .all, before: today) > 0
            date = today
            self.counts = counts
            completedDay = day
            self.hasHistory = hasHistory
        } catch {
            report(error)
            return
        }
        currentIndex = openingIndex()
        refresh()
    }

    // MARK: Summary

    /// `updateSessionProgress`: counted cards complete out of the counted cards, or «اكتملت <section> اليوم».
    var summary: DeckSummary {
        let counted = items.filter { $0.target != nil }
        let done = counted.filter { isComplete($0) }.count
        let progress = "\(ArabicFormat.number(done)) من \(ArabicFormat.number(counted.count))"
        return DeckSummary(copy: isComplete ? "اكتملت \(definition.title) اليوم" : progress, value: done,
                           total: counted.count, isComplete: isComplete,
                           accessibilityLabel: "\(definition.title): \(progress)")
    }

    /// The أخرى row: the deck's idle line («قبل النوم وفي الليل», «صيغتان») until today has a count, then the summary.
    /// The salawat row's Friday line is the list's, which knows the prayer times.
    var listSummary: DeckSummary {
        var line = summary
        if !hasCountToday, !isComplete, let idle = definition.listIdle { line.copy = idle }
        return line
    }

    /// Today is recorded complete (the أخرى row's ✓).
    var isComplete: Bool { completedDay != nil }

    /// A counted card has a count today.
    var hasCountToday: Bool { items.contains { $0.target != nil && count(of: $0) > 0 } }

    /// The completion dialog: «تم» alone.
    var completion: DeckCompletion {
        DeckCompletion(title: deck == .sleep ? "تمت أذكار النوم بحمد الله" : "تمت الصلاة على النبي ﷺ بحمد الله",
                       message: "حُفظ إكمال اليوم على هذا الجهاز.",
                       time: completedDay.map { "وقت الإكمال: \(ArabicFormat.time($0.completedAt))" },
                       dismissTitle: "تم", primary: nil)
    }

    // MARK: Cards

    func show(_ index: Int) {
        currentIndex = max(0, min(index, cards.count - 1))
    }

    /// The adhkar lock: «التالي» and a forward swipe wait until the card is complete; an uncounted card always is.
    func canMoveForward(from index: Int) -> Bool {
        guard index < cards.count - 1, let card = cards[safe: index] else { return false }
        return card.isComplete
    }

    /// One reading: the haptic when the card reaches its target, whatever the target (the ruqyah rule). The reading
    /// that completes the day records it in the same write (once; the first time is kept) and opens the dialog;
    /// otherwise a completed card moves the deck on. An uncounted or complete card, or a reading that is not stored,
    /// counts nothing: `nil`.
    func tap(cardAt index: Int) -> DeckChange? {
        guard let item = items[safe: index], let target = item.target else { return nil }
        let current = count(of: item)
        guard current < target else { return nil }
        let next = current + 1
        let completesCard = next >= target
        let completesDay = completesCard
            && items.allSatisfy { $0.id == item.id || $0.target == nil || isComplete($0) }
        let now = Date()
        do {
            try repository.setCount(next, for: item.id, in: deck, on: date, completingDayAt: completesDay ? now : nil,
                                    at: now)
        } catch {
            report(error)
            return nil
        }
        counts[item.id] = next
        // The same transaction inserted the row; an existing row keeps its first time.
        if completesDay, completedDay == nil {
            completedDay = ReadingDay(deck: deck, localDate: date, completedAt: now)
        }
        refresh()
        return DeckChange(completedCard: completesCard, completedDeck: completesDay,
                          advance: completesCard && !completesDay, haptic: completesCard)
    }

    func setTarget(_ target: Int, forCardAt index: Int) -> DeckChange? { nil }

    /// A card reset never asks («سور»'s rule).
    func resetConfirmation(forCardAt index: Int) -> DeckConfirmation? { nil }

    /// The count returns to 0 and today's record is deleted, in one write, so completion follows the counters.
    func resetCard(at index: Int) {
        guard let item = items[safe: index], item.target != nil, count(of: item) > 0 else { return }
        do {
            try repository.resetItem(item.id, in: deck, on: date)
        } catch {
            report(error)
            return
        }
        counts[item.id] = 0
        completedDay = nil
        refresh()
    }

    // MARK: Scoped reset

    /// Any count today, or today or an earlier day recorded complete.
    var canReset: Bool { hasCountToday || completedDay != nil || hasHistory }

    /// The confirmation counts the earlier days in scope with a completion record.
    func confirmation(for scope: ResetScope) -> DeckConfirmation? {
        let removal: HistoryRemoval
        switch scope {
        case .day: return nil
        case .week: removal = .week(endingAt: Date(), in: .current)
        case .everything: removal = .all
        }
        return scope.confirmation(recordedDays: (try? repository.recordedDayCount(deck, removal, before: date)) ?? 0)
    }

    /// تقدم اليوم deletes today's counts and record; هذا الأسبوع and كل شيء also the deck's history in scope. The deck
    /// then opens on its first incomplete card. A reset that is not stored changes nothing and returns `false`.
    @discardableResult
    func reset(_ scope: ResetScope) -> Bool {
        let removal: HistoryRemoval? = switch scope {
        case .day: nil
        case .week: .week(endingAt: Date(), in: .current)
        case .everything: .all
        }
        let keepsHistory: Bool
        do {
            // Read first, so that once the transaction is stored nothing is left to fail.
            keepsHistory = try removal.map {
                try repository.recordedDayCount(deck, .all, before: date)
                    > repository.recordedDayCount(deck, $0, before: date)
            } ?? hasHistory
            try repository.reset(deck, on: date, removing: removal)
        } catch {
            report(error)
            return false
        }
        counts = [:]
        completedDay = nil
        hasHistory = keepsHistory
        currentIndex = openingIndex()
        refresh()
        return true
    }

    // MARK: Private

    /// The stored count, clamped to `0…target` as the ruqyah's; 0 for an uncounted card.
    private func count(of item: Item) -> Int {
        guard let target = item.target else { return 0 }
        return max(0, min(counts[item.id] ?? 0, target))
    }

    /// `count >= target`, or the card is uncounted.
    private func isComplete(_ item: Item) -> Bool {
        guard let target = item.target else { return true }
        return count(of: item) >= target
    }

    /// The first incomplete counted card, or the last card when every counted card is complete.
    private func openingIndex() -> Int {
        items.firstIndex { !isComplete($0) } ?? max(0, items.count - 1)
    }

    /// Each card's counter and spoken labels.
    private func refresh() {
        cards = items.enumerated().map { index, item in
            let n = ArabicFormat.number(index + 1)
            let value = count(of: item)
            let complete = isComplete(item)
            guard let target = item.target else {
                let footer = item.uncounted?.footer ?? ""
                let label = "البطاقة \(n)، \(item.uncounted?.label ?? footer)"
                return DeckCard(
                    id: item.id, number: index + 1, content: .reading(item.content), count: 0, target: 1,
                    requirement: "", targetOptions: nil, status: .text(footer), isReview: false, progressLabel: label,
                    tapLabel: "اكتمل، البطاقة \(n). \(label)", resetLabel: "إعادة عداد البطاقة \(n)", targetLabel: "",
                    isUncounted: true)
            }
            let label = target == 1
                ? "البطاقة \(n)، \(complete ? "قُرئت" : "لم تُعلَّم كمقروءة")"
                : "البطاقة \(n)، كُرّر \(ArabicFormat.number(value)) من أصل \(ArabicFormat.number(target)) مرات"
                    + (complete ? "، اكتمل" : "")
            let tapLabel = complete ? "اكتمل، البطاقة \(n). \(label)"
                : target == 1 ? "تحديد كمقروءة، البطاقة \(n). \(label)" : "زيادة عداد البطاقة \(n). \(label)"
            return DeckCard(
                id: item.id, number: index + 1, content: .reading(item.content), count: value, target: target,
                requirement: item.requirement, targetOptions: nil,
                status: target == 1 ? .text(complete ? "تمت القراءة" : "اضغط بعد القراءة") : .numeric,
                isReview: false, progressLabel: label, tapLabel: tapLabel,
                resetLabel: "إعادة عداد البطاقة \(n)", targetLabel: "")
        }
        currentIndex = max(0, min(currentIndex, cards.count - 1))
    }

    // MARK: Cards from the packs

    /// One card per sleep item. A `sura` item's passage was resolved from the suwar pack at load
    /// (``SleepContent/resolvingSuwar(_:)``); a passage that opens a sura sits under the pack's basmala.
    private static func items(_ sleep: SleepContent) -> [Item] {
        sleep.items.map { item in
            let content = ReadingCardContent(
                title: item.title, prefix: item.prefix,
                passages: (item.quran ?? []).map {
                    .init(basmala: $0.basmala && !sleep.basmala.isEmpty ? sleep.basmala : nil, text: $0.text,
                          citation: $0.citation)
                },
                text: item.text, steps: item.steps ?? [], note: item.note?.text)
            guard !ReadingDeck.sleep.uncountedItemIDs.contains(item.id) else {
                return Item(id: item.id, content: content, target: nil, requirement: "",
                            uncounted: (footer: "عند الحاجة", label: "عند الحاجة"))
            }
            return Item(id: item.id, content: content, target: max(1, item.count ?? 1),
                        requirement: item.countLabel ?? "مرة واحدة", uncounted: nil)
        }
    }

    /// The opening card (al-Ahzab 56 and the Friday virtue, under the Friday pill), then one card per salawat.
    private static func items(_ salawat: SalawatContent) -> [Item] {
        let opening = Item(
            id: salawatOpeningID,
            content: ReadingCardContent(
                passages: [.init(basmala: nil, text: salawat.quran.text, citation: salawat.quran.citation)],
                note: salawat.virtue.text, showsFridayPill: true),
            target: nil, requirement: "", uncounted: (footer: "اقرأ ثم اسحب", label: "الآية والفضل"))
        return [opening] + salawat.items.map { item in
            Item(id: item.id, content: ReadingCardContent(title: item.title, text: item.text, note: item.note?.text),
                 target: 1, requirement: "مرة واحدة", uncounted: nil)
        }
    }
}
