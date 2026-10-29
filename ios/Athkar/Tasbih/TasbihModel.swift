import AthkarCore
import Foundation
import Observation

/// «مسبحة», the athkar PWA's counter (`athkar-tasbih-v1`): today's count of each phrase (`counts`), stored in
/// `tasbih_counts`, and three preferences kept in settings: the phrase counted (`selected`), the target and the saved
/// phrases (`custom`). A change is shown only once it is stored, and a day only once it has been read.
///
/// Phrase keys compare as code units, as JavaScript compares the keys of `counts`; Swift's `==` would also equate
/// spellings whose tashkeel is only ordered differently.
@MainActor
@Observable
final class TasbihModel: ResettableSection {
    /// A phrase's count today.
    struct PhraseCount: Equatable {
        var key: String
        var count: Int
    }

    /// A row of the phrase sheet (`tasbihOptionMarkup`).
    struct Option: Identifiable, Equatable {
        var key: String
        /// Shown with its tashkeel.
        var label: String
        /// Today's count, shown when it is not zero.
        var count: Int
        var isSelected: Bool
        /// «سبحان الله، اليوم ٣٣», or the short form alone at zero.
        var accessibilityLabel: String

        var id: String { key }
    }

    /// What a change did, so the view can move the ring, play the haptic and speak.
    struct Change: Equatable {
        enum Ring: Equatable {
            /// Moves to the new fraction (160 ms).
            case step
            /// Set at once, so the tap after a full lap never sweeps back.
            case jump
            /// Retracts (220 ms).
            case reset
        }

        enum Announcement: Equatable {
            /// Spoken at once, cancelling a count announcement still waiting.
            case now(String)
            /// ``TasbihModel/countAnnouncement``, once taps have paused for a second.
            case countAfterPause
        }

        /// `nil`: the ring stays as it is.
        var ring: Ring?
        var announcement: Announcement?
        /// Play the completion haptic (when the haptics setting is on).
        var haptic = false
        /// A multiple of the target was reached: the count breathes.
        var reached = false
    }

    /// The local date the counts belong to.
    private(set) var date: String
    /// Today's counts, in first-use order.
    private(set) var counts: [PhraseCount]
    /// A preset ID, or `c:` and a saved phrase.
    private(set) var selected: String
    /// `nil`: «بلا هدف».
    private(set) var target: Int?
    /// The saved phrases, newest first.
    private(set) var custom: [String]
    private(set) var hasHistory: Bool

    @ObservationIgnored private let repository: TasbihRepository
    @ObservationIgnored private let settings: SettingsRepository
    @ObservationIgnored private let report: (any Error) -> Void
    /// `tasbihCapAnnounced`: the cap is announced once, until the count is below it again.
    @ObservationIgnored private var capAnnounced = false

    init(database: AppDatabase, today: String, report: @escaping (any Error) -> Void) throws {
        repository = database.tasbih
        settings = database.settings
        self.report = report
        date = today
        counts = try repository.counts(on: today).map { PhraseCount(key: $0.phraseKey, count: $0.count) }
        hasHistory = try repository.recordedDayCount(.all, before: today) > 0
        // `normalizeTasbihState`: saved phrases are cleaned, and one that names a preset or an earlier phrase, or is
        // past the eighth, is dropped; a target out of range reads as 33; a selection that is neither a preset nor
        // saved reads as «سبحان الله».
        var phrases: [String] = []
        for stored in try settings.value(for: .tasbihCustomPhrases) where phrases.count < TasbihText.maxCustom {
            let text = TasbihText.cleanPhrase(stored)
            if !text.isEmpty, TasbihText.findPhrase(text, custom: phrases) == nil { phrases.append(text) }
        }
        custom = phrases
        let target = try settings.value(for: .tasbihTarget)
        self.target = switch target {
        case 0: nil
        case 1...TasbihText.maxTarget: target
        default: TasbihText.defaultTarget
        }
        let stored = try settings.value(for: .tasbihSelected)
        if TasbihText.preset(stored) != nil {
            selected = stored
        } else if TasbihText.isCustomKey(stored),
                  let key = TasbihText.findPhrase(TasbihText.savedText(of: stored), custom: phrases) {
            selected = key
        } else {
            selected = TasbihText.presets[0].id
        }
    }

    /// `ensureCurrentDay`: a new day starts with that day's counts; the phrase, target and saved phrases stay. A day
    /// that cannot be read is not shown: the counter keeps its day, so the next `ensureCurrentDay` tries again.
    func roll(to today: String) {
        guard today != date else { return }
        do {
            let rows = try repository.counts(on: today)
            let hasHistory = try repository.recordedDayCount(.all, before: today) > 0
            date = today
            counts = rows.map { PhraseCount(key: $0.phraseKey, count: $0.count) }
            self.hasHistory = hasHistory
        } catch {
            report(error)
            return
        }
        settleCap()
    }

    // MARK: Counting

    /// `addTasbihCount`: one more for the phrase on screen. Every multiple of the target plays the haptic and is
    /// announced at once; any other count is announced once taps pause. At ``TasbihCount/maxCount`` nothing is
    /// counted and the cap is announced once. A count that is not stored is not shown: `nil`.
    func add() -> Change? {
        let before = count
        guard before < TasbihCount.maxCount else {
            guard !capAnnounced else { return nil }
            capAnnounced = true
            return Change(announcement: .now("بلغت الحد الأقصى للعدّ"))
        }
        let count = before + 1
        guard store(count) else { return nil }
        let reached = target.map { count % $0 == 0 } ?? false
        let ring: Change.Ring = if let target, before > 0, before % target == 0 { .jump } else { .step }
        let announcement: Change.Announcement = if !reached {
            .countAfterPause
        } else if let target, count == target {
            .now("بلغت الهدف: \(ArabicFormat.number(target))، \(phrase.short)")
        } else {
            .now("اكتملت الدورة \(ArabicFormat.number(count / (target ?? 1)))")
        }
        return Change(ring: ring, announcement: announcement, haptic: reached, reached: reached)
    }

    /// `undoTasbihCount`: one less for the phrase on screen. Nothing to undo at zero, and an undo that is not stored
    /// is not shown: `nil`.
    func undo() -> Change? {
        let before = count
        guard before > 0 else { return nil }
        let count = before - 1
        guard store(count) else { return nil }
        let ring: Change.Ring = if let target, count > 0, count % target == 0 { .jump } else { .step }
        return Change(ring: ring, announcement: .now("تراجع، العدد \(ArabicFormat.number(count))"))
    }

    /// `requestTasbihReset`: always asked, since a count cannot be rebuilt; `nil` at zero, where there is nothing to
    /// reset.
    func resetConfirmation() -> DeckConfirmation? {
        guard count > 0 else { return nil }
        return DeckConfirmation(
            title: "إعادة عدّ \(phrase.short)؟",
            message: "سيعود عدّ هذا الذكر اليوم من \(ArabicFormat.number(count)) إلى الصفر، ويُنقص من مجموع اليوم.")
    }

    /// The confirmed reset: today's count of the phrase on screen is zero, and its next count puts it last in the
    /// day's order. A reset that is not stored is not shown: `nil`.
    func resetCount() -> Change? {
        guard store(0) else { return nil }
        return Change(ring: .reset, announcement: .now("أُعيد عدّ \(phrase.short) إلى الصفر"))
    }

    // MARK: Phrases and target

    /// `selectTasbihPhrase`: the phrase is stored as the one counted, then announced with today's count. A key that
    /// is neither a preset nor saved, or a choice that is not stored, changes nothing: `nil`.
    func select(_ key: String) -> Change? {
        guard isAvailable(key) else { return nil }
        do {
            try settings.set(key, for: .tasbihSelected)
        } catch {
            report(error)
            return nil
        }
        selected = key
        settleCap()
        return Change(ring: .step,
                      announcement: .now("الذكر: \(phrase.short)، العدد \(ArabicFormat.number(count))"))
    }

    /// `addTasbihPhrase`: a phrase that names a preset or a saved phrase selects it; a new one is saved first in the
    /// list and selected, unless eight are saved already. Counts an earlier spelling of the phrase kept, today and
    /// before, move to it (`canonicalTasbihDays` does this when the PWA next loads). `nil` when nothing changed.
    func addPhrase(_ value: String) -> Change? {
        let text = TasbihText.cleanPhrase(value)
        guard !text.isEmpty else { return nil }
        if let known = TasbihText.findPhrase(text, custom: custom) { return select(known) }
        guard canAddPhrase else { return nil }
        let key = TasbihText.customKey(text)
        let identity = TasbihText.identity(key)
        let phrases = [text] + custom
        let adopting: [String]
        do {
            adopting = try repository.phraseKeys().filter {
                !TasbihText.same($0, key) && TasbihText.same(TasbihText.identity($0), identity)
            }
            try repository.savePhrases(phrases, selected: key, adopting: adopting)
        } catch {
            report(error)
            return nil
        }
        custom = phrases
        selected = key
        for earlier in adopting {
            guard let index = counts.firstIndex(where: { TasbihText.same($0.key, earlier) }) else { continue }
            let moved = counts.remove(at: index)
            if let existing = counts.firstIndex(where: { TasbihText.same($0.key, key) }) {
                counts[existing].count = min(counts[existing].count + moved.count, TasbihCount.maxCount)
                // The earlier first use keeps its place.
                if index <= existing {
                    let merged = counts.remove(at: existing)
                    counts.insert(merged, at: index)
                }
            } else {
                counts.insert(PhraseCount(key: key, count: moved.count), at: index)
            }
        }
        settleCap()
        return Change(ring: .step, announcement: .now("أُضيفت العبارة: \(TasbihText.stripTashkeel(text))"))
    }

    /// `deleteTasbihPhrase`: the phrase leaves the list only; its counts today and before stay. When it was the one
    /// counted, «سبحان الله» is. `nil` when nothing changed.
    func deletePhrase(_ text: String) -> Change? {
        guard let index = custom.firstIndex(where: { TasbihText.same($0, text) }) else { return nil }
        var phrases = custom
        phrases.remove(at: index)
        let next = TasbihText.same(selected, TasbihText.customKey(text)) ? TasbihText.presets[0].id : selected
        do {
            try repository.savePhrases(phrases, selected: next)
        } catch {
            report(error)
            return nil
        }
        custom = phrases
        selected = next
        settleCap()
        return Change(ring: .step, announcement: .now("حُذفت العبارة: \(TasbihText.stripTashkeel(text))"))
    }

    /// `setTasbihTarget`: counts never change with the target, and a count already at or past it shows the reached
    /// state without a haptic. A target out of range, or one that is not stored, changes nothing: `nil`.
    func setTarget(_ target: Int?) -> Change? {
        if let target, !(1...TasbihText.maxTarget).contains(target) { return nil }
        do {
            try settings.set(target ?? 0, for: .tasbihTarget)
        } catch {
            report(error)
            return nil
        }
        self.target = target
        return Change(ring: .step, announcement: .now(target.map { "الهدف: \(ArabicFormat.number($0))" } ?? "بلا هدف"))
    }

    // MARK: Shown state

    /// Today's count of the phrase on screen.
    var count: Int { count(of: selected) }

    /// `tasbihDayTotal`: every phrase counted today, saved or not.
    var dayTotal: Int { counts.reduce(0) { $0 + $1.count } }

    /// `tasbihPhrase` of the phrase on screen.
    var phrase: (label: String, short: String) { TasbihText.phrase(selected) }

    var status: (text: String, check: Bool) { TasbihText.status(count: count, target: target) }

    /// How much of the ring is drawn: the count within its lap, so a full lap is a full ring.
    var ringFraction: Double {
        guard let target, count > 0 else { return 0 }
        return Double((count - 1) % target + 1) / Double(target)
    }

    /// The count has reached the target (`is-complete`).
    var isReached: Bool { target.map { count >= $0 } ?? false }

    /// The count is a whole number of laps (`data-state="lap"`).
    var isLap: Bool { count > 0 && target.map { count % $0 == 0 } ?? false }

    /// `tasbihSrSummary`: «سبحان الله، ٣ من ٣٣», or «…، ٣، بلا هدف».
    var summaryLabel: String {
        let n = ArabicFormat.number(count)
        return target.map { "\(phrase.short)، \(n) من \(ArabicFormat.number($0))" } ?? "\(phrase.short)، \(n)، بلا هدف"
    }

    /// A1, spoken once taps pause: «٣ من ٣٣», or «٣».
    var countAnnouncement: String {
        let n = ArabicFormat.number(count)
        return target.map { "\(n) من \(ArabicFormat.number($0))" } ?? n
    }

    /// «اليوم: ١٢»; also the أخرى row's line.
    var totalText: String { "اليوم: \(ArabicFormat.number(dayTotal))" }
    var totalLabel: String { "مجموع المسبحة اليوم: \(ArabicFormat.number(dayTotal))" }
    var phraseButtonLabel: String { "اختيار الذكر، الحالي: \(phrase.short)" }
    var targetChipText: String { target.map { "الهدف: \(ArabicFormat.number($0))" } ?? "بلا هدف" }
    var targetButtonLabel: String { "تغيير الهدف، الحالي: \(target.map { ArabicFormat.number($0) } ?? "بلا هدف")" }
    var resetLabel: String { "إعادة عدّ \(phrase.short) إلى الصفر" }

    var presetOptions: [Option] { TasbihText.presets.map { option($0.id) } }
    var customOptions: [Option] { custom.map { option(TasbihText.customKey($0)) } }
    /// Fewer than eight phrases are saved (`tasbihCustomForm` shows; otherwise `tasbihCustomLimit`).
    var canAddPhrase: Bool { custom.count < TasbihText.maxCustom }

    // MARK: Scoped reset

    /// `tasbihHasResettableState`.
    var canReset: Bool { !counts.isEmpty || hasHistory }

    /// «تقدم اليوم» asks while a phrase is counted today: those counts cannot be rebuilt (the PWA's `resetDayButton`).
    func confirmation(for scope: ResetScope) -> DeckConfirmation? {
        let removal: HistoryRemoval
        switch scope {
        case .day:
            guard dayTotal > 0 else { return nil }
            return DeckConfirmation(
                title: "إعادة تقدم اليوم؟",
                message: "ستُعاد عدادات المسبحة اليوم (\(ArabicFormat.number(dayTotal)))، مع بقاء السجل كما هو."
                    + " لا يمكن التراجع.")
        case .week: removal = .week(endingAt: Date(), in: .current)
        case .everything: removal = .all
        }
        return scope.confirmation(recordedDays: (try? repository.recordedDayCount(removal, before: date)) ?? 0)
    }

    /// `resetTasbihProgress` and `deleteTasbihHistory`: no phrase is counted today, and the history the scope covers
    /// is deleted; the phrase, target and saved phrases stay. A reset that is not stored changes nothing and returns
    /// `false`.
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
                try repository.recordedDayCount(.all, before: date) > repository.recordedDayCount($0, before: date)
            } ?? hasHistory
            try repository.reset(on: date, removing: removal)
        } catch {
            report(error)
            return false
        }
        counts = []
        hasHistory = keepsHistory
        settleCap()
        return true
    }

    // MARK: Private

    private func count(of key: String) -> Int {
        counts.first { TasbihText.same($0.key, key) }?.count ?? 0
    }

    /// `keepTasbihSelection`: a preset, or a phrase still saved.
    private func isAvailable(_ key: String) -> Bool {
        TasbihText.preset(key) != nil
            || TasbihText.isCustomKey(key) && custom.contains { TasbihText.same($0, TasbihText.savedText(of: key)) }
    }

    /// `setTasbihCount` for the phrase on screen: a phrase counted for the first time today goes last; zero removes
    /// it. `false` when the count was not stored.
    private func store(_ count: Int) -> Bool {
        do {
            try repository.setCount(count, for: selected, on: date)
        } catch {
            report(error)
            return false
        }
        if let index = counts.firstIndex(where: { TasbihText.same($0.key, selected) }) {
            if count > 0 { counts[index].count = count } else { counts.remove(at: index) }
        } else if count > 0 {
            counts.append(PhraseCount(key: selected, count: count))
        }
        settleCap()
        return true
    }

    /// `renderTasbih`: below the cap, the cap is announced again when next reached.
    private func settleCap() {
        if count < TasbihCount.maxCount { capAnnounced = false }
    }

    private func option(_ key: String) -> Option {
        let phrase = TasbihText.phrase(key)
        let count = count(of: key)
        let name = count > 0 ? "\(phrase.short)، اليوم \(ArabicFormat.number(count))" : phrase.short
        return Option(key: key, label: phrase.label, count: count, isSelected: TasbihText.same(key, selected),
                      accessibilityLabel: name)
    }
}
