import AthkarCore
import Foundation
import Observation

/// The ruqyah deck, one section per sura as the ruqyah PWA shows it: today's segment counters
/// (`ruqyah-daily-v1.counts`), the suras completed today (`ruqyah-suwar-v1.completedAt`) and whether today is
/// recorded complete, as stored in `ruqyah_segment_progress`, `ruqyah_sura_days` and `ruqyah_days`. A change is shown
/// only once its transaction is stored, and a day only once it has been read.
@MainActor
@Observable
final class RuqyahDeckModel: DeckModel {
    let definition = DeckDefinition.ruqyah
    /// The selected sura's segments, numbered within the sura.
    private(set) var cards: [DeckCard] = []
    /// The shown segment's position in the selected sura.
    private(set) var currentIndex = 0
    private(set) var progress: RuqyahProgress
    /// Today's `ruqyah_days` row (`state.history[today]`). The row alone records the day complete.
    private(set) var completedDay: RuqyahDay?
    /// Today's `ruqyah_sura_days` rows: sura ID → when it was completed.
    private(set) var completedSuwar: [String: Date]
    private(set) var hasHistory: Bool
    /// The sura on screen (`selectedSuraId`). Not stored: the ruqyah PWA opens on ق unless a deep link names a sura.
    private(set) var selectedSuraID: String

    @ObservationIgnored private let segments: [RuqyahSegment]
    @ObservationIgnored private let contents: [RuqyahSegmentContent]
    @ObservationIgnored private let suwar: [RuqyahSura]
    @ObservationIgnored private let repository: RuqyahRepository
    @ObservationIgnored private let report: (any Error) -> Void
    /// The segment each sura showed last since the deck opened (`suraIndices`); a sura without one opens on its first
    /// incomplete segment.
    @ObservationIgnored private var suraIndices: [String: Int] = [:]

    init(database: AppDatabase, content: BundledContent, today: String, report: @escaping (any Error) -> Void) throws {
        segments = content.packs.ruqyahSegments
        contents = content.ruqyah
        suwar = content.ruqyahSuwar
        repository = database.ruqyah
        self.report = report
        progress = RuqyahProgress(date: today, counts: try repository.counts(on: today))
        completedDay = try repository.day(on: today)
        completedSuwar = try repository.suraDays(on: today)
        hasHistory = try repository.recordedDayCount(.all, before: today) > 0
        selectedSuraID = suwar.first?.id ?? ""
        currentIndex = firstIncompleteIndex(of: selectedSura)
        refresh()
    }

    /// `ensureCurrentDay` and `startNewDay`: a new day starts with that day's counters, and the shown sura reopens on
    /// its first segment. A day that cannot be read is not shown: the deck keeps its day, so the next
    /// `ensureCurrentDay` tries again.
    func roll(to today: String) {
        guard today != progress.date else { return }
        do {
            let counts = try repository.counts(on: today)
            let day = try repository.day(on: today)
            let suraDays = try repository.suraDays(on: today)
            let hasHistory = try repository.recordedDayCount(.all, before: today) > 0
            progress = RuqyahProgress(date: today, counts: counts)
            completedDay = day
            completedSuwar = suraDays
            self.hasHistory = hasHistory
        } catch {
            report(error)
            return
        }
        suraIndices = [:]
        currentIndex = firstIncompleteIndex(of: selectedSura)
        refresh()
    }

    // MARK: Sections

    var sections: [DeckSection] {
        suwar.map { sura in
            let complete = isComplete(sura)
            return DeckSection(id: sura.id, title: sura.shortName, isComplete: complete,
                               accessibilityLabel: complete ? "\(sura.surah)، مكتملة اليوم" : sura.surah)
        }
    }

    var selectedSectionID: String? { selectedSuraID }

    /// `selectSura`: the sura opens where it was left, or on its first incomplete segment.
    func selectSection(_ id: String) {
        guard id != selectedSuraID, let sura = suwar.first(where: { $0.id == id }) else { return }
        suraIndices[selectedSuraID] = currentIndex
        selectedSuraID = sura.id
        currentIndex = suraIndices[sura.id] ?? firstIncompleteIndex(of: sura)
        refresh()
    }

    var cardsLabel: String { "مقاطع \(selectedSura.surah)" }

    // MARK: Summary

    /// `updateSessionProgress`: the summary row follows the shown sura; the today line keeps the whole day.
    var summary: DeckSummary {
        let sura = selectedSura
        let done = readings(in: sura)
        let total = repeats(in: sura)
        let counted = "\(ArabicFormat.number(done)) من \(ArabicFormat.number(total)) تكرارًا"
        let complete = done >= total
        return DeckSummary(
            copy: complete ? "اكتملت \(sura.surah) اليوم" : counted, value: done, total: total, isComplete: complete,
            accessibilityLabel: "\(sura.surah): \(counted)", status: todayStatus, statusIsComplete: isDayComplete)
    }

    /// The whole day, for the أخرى list.
    var listSummary: DeckSummary {
        let done = progress.readings(in: segments)
        let total = segments.reduce(0) { $0 + $1.repeatCount }
        let copy = "\(ArabicFormat.number(done)) من \(ArabicFormat.number(total)) تكرارًا"
        return DeckSummary(copy: copy, value: done, total: total, isComplete: isDayComplete,
                           accessibilityLabel: "تقدم رقية اليوم: \(copy)", status: todayStatus,
                           statusIsComplete: isDayComplete)
    }

    /// The selected sura is complete today (the summary's colour).
    var isComplete: Bool { isComplete(selectedSura) }

    /// Today is recorded complete.
    var isDayComplete: Bool { completedDay != nil }

    /// When today was recorded complete (`state.history[today].completedAt`).
    var completedAt: Date? { completedDay?.completedAt }

    /// `updateTodayStatus`.
    private var todayStatus: String {
        guard let completedDay else {
            let done = progress.readings(in: segments)
            let total = segments.reduce(0) { $0 + $1.repeatCount }
            return "رقية اليوم: \(ArabicFormat.number(done)) من \(ArabicFormat.number(total)) تكرارًا"
        }
        return "تمت رقية اليوم في \(ArabicFormat.time(completedDay.completedAt))"
    }

    /// The day dialog once every segment is complete; otherwise `openSuraCompletionDialog` for the shown sura, whose
    /// primary action opens the next sura in order (wrapping) still incomplete today.
    var completion: DeckCompletion {
        if progress.allComplete(segments) {
            return DeckCompletion(title: "تمت الرقية بحمد الله", message: "اكتملت جميع المقاطع بتكراراتها.",
                                  time: completedAt.map { "وقت الإكمال: \(ArabicFormat.time($0))" },
                                  dismissTitle: "إغلاق", primary: (title: "بدء رقية جديدة", action: .restart))
        }
        let sura = selectedSura
        let position = suwar.firstIndex(of: sura) ?? 0
        let next = (suwar[(position + 1)...] + suwar[..<position]).first { !isComplete($0) } ?? sura
        return DeckCompletion(title: "اكتملت قراءة \(sura.surah) بحمد الله",
                              message: "تم حفظ إكمال اليوم محليًا على هذا الجهاز.",
                              time: suraCompletedAt(sura).map { "وقت الإكمال: \(ArabicFormat.time($0))" },
                              dismissTitle: "تم",
                              primary: (title: "الانتقال إلى \(next.surah)", action: .openSection(next.id)))
    }

    // MARK: Cards

    func show(_ index: Int) {
        currentIndex = max(0, min(index, cards.count - 1))
    }

    /// `updateDeckNavigation`: «التالي» and a forward swipe wait until the shown segment's repeats are complete.
    func canMoveForward(from index: Int) -> Bool {
        guard index < cards.count - 1, let segment = segment(at: index) else { return false }
        return progress.isComplete(segment)
    }

    /// `countReading` and `showReading`: completing a segment plays the haptic; completing the sura records it (once)
    /// and opens its dialog, and completing every segment records the day (once) and opens the day's. A reading that
    /// is not stored is not counted: `nil`, as for a complete segment.
    func tap(cardAt index: Int) -> DeckChange? {
        let sura = selectedSura
        var counted = progress
        guard let segment = segment(at: index), let next = counted.countReading(segment) else { return nil }
        let completesSegment = next >= segment.repeatCount
        let completesSura = completesSegment && segments[sura.segments].allSatisfy(counted.isComplete)
        let allComplete = completesSura && counted.allComplete(segments)
        let now = Date()
        do {
            try repository.setCount(next, for: segment.id, on: counted.date,
                                    completingSura: completesSura ? sura.id : nil,
                                    completingDayAt: allComplete ? now : nil, at: now)
        } catch {
            report(error)
            return nil
        }
        progress = counted
        // The same transaction inserted the rows; an existing row keeps its first time.
        if completesSura, completedSuwar[sura.id] == nil { completedSuwar[sura.id] = now }
        if allComplete, completedDay == nil {
            completedDay = RuqyahDay(localDate: counted.date, completedAt: now, completionOrigin: .counters)
            hasHistory = true
        }
        refresh()
        return DeckChange(completedCard: completesSegment, completedDeck: completesSura,
                          advance: completesSegment && !completesSura, haptic: completesSegment)
    }

    func setTarget(_ target: Int, forCardAt index: Int) -> DeckChange? { nil }

    /// `resetSegment` always asks.
    func resetConfirmation(forCardAt index: Int) -> DeckConfirmation? {
        guard let segment = segment(at: index), progress.count(for: segment) > 0,
              let content = content(at: index) else { return nil }
        return DeckConfirmation(title: "إعادة العداد؟", message: "سيعود عداد \(content.surah) \(content.range) إلى الصفر.")
    }

    /// `resetSegment`: the counter returns to 0 and the sura is no longer complete today.
    func resetCard(at index: Int) {
        let sura = selectedSura
        guard let segment = segment(at: index), progress.count(for: segment) > 0 else { return }
        do {
            try repository.resetSegment(segment.id, of: sura.id, on: progress.date)
        } catch {
            report(error)
            return
        }
        progress.counts[segment.id] = 0
        completedSuwar[sura.id] = nil
        refresh()
    }

    // MARK: Scoped reset

    var canReset: Bool { progress.readings(in: segments) > 0 || hasHistory }

    func confirmation(for scope: ResetScope) -> DeckConfirmation? {
        let removal: HistoryRemoval
        switch scope {
        case .day: return nil
        case .week: removal = .week(endingAt: Date(), in: .current)
        case .everything: removal = .all
        }
        return scope.confirmation(recordedDays: (try? repository.recordedDayCount(removal, before: progress.date)) ?? 0)
    }

    /// `resetDayProgress`, `resetWeek`, `resetEverything` and `showDayCleared`: today's counters and sura completions
    /// are cleared, and the deck reopens on ق's first segment. تقدم اليوم (and «بدء رقية جديدة») keeps today's record.
    /// A reset that is not stored changes nothing and returns `false`.
    @discardableResult
    func reset(_ scope: ResetScope) -> Bool {
        let now = Date()
        let removal: HistoryRemoval? = switch scope {
        case .day: nil
        case .week: .week(endingAt: now, in: .current)
        case .everything: .all
        }
        let keepsHistory: Bool
        do {
            // Read first, so that once the transaction is stored nothing is left to fail.
            keepsHistory = try removal.map {
                try repository.recordedDayCount(.all, before: progress.date)
                    > repository.recordedDayCount($0, before: progress.date)
            } ?? hasHistory
            try repository.resetCounts(on: progress.date, removing: removal, at: now)
        } catch {
            report(error)
            return false
        }
        // What the transaction stored: every counter of the day is 0, no sura is complete today, and the days
        // `removal` covers are gone.
        progress.counts = progress.counts.mapValues { _ in 0 }
        completedSuwar = [:]
        if let removal, removal.includes(progress.date) { completedDay = nil }
        hasHistory = keepsHistory
        suraIndices = [:]
        selectedSuraID = suwar.first?.id ?? ""
        currentIndex = 0
        refresh()
        return true
    }

    // MARK: Private

    private var selectedSura: RuqyahSura {
        suwar.first { $0.id == selectedSuraID } ?? RuqyahSura(id: "", surah: "", segments: 0..<0)
    }

    private func segment(at index: Int) -> RuqyahSegment? {
        let position = selectedSura.segments.lowerBound + index
        return selectedSura.segments.contains(position) ? segments[position] : nil
    }

    private func content(at index: Int) -> RuqyahSegmentContent? {
        let position = selectedSura.segments.lowerBound + index
        return selectedSura.segments.contains(position) ? contents[position] : nil
    }

    /// `suraIsComplete`: every segment read its repeats today.
    private func isComplete(_ sura: RuqyahSura) -> Bool {
        segments[sura.segments].allSatisfy(progress.isComplete)
    }

    /// When the sura was completed today. A sura complete by its counters with no row of its own takes the day's
    /// record time (`backfillSuwarCompletions`); no time is invented.
    private func suraCompletedAt(_ sura: RuqyahSura) -> Date? {
        completedSuwar[sura.id] ?? (isComplete(sura) ? completedAt : nil)
    }

    private func readings(in sura: RuqyahSura) -> Int {
        segments[sura.segments].reduce(0) { $0 + progress.count(for: $1) }
    }

    private func repeats(in sura: RuqyahSura) -> Int {
        segments[sura.segments].reduce(0) { $0 + $1.repeatCount }
    }

    /// `firstIncompleteIndex(sura)`: 0 when the sura is complete.
    private func firstIncompleteIndex(of sura: RuqyahSura) -> Int {
        (segments[sura.segments].firstIndex { !progress.isComplete($0) } ?? sura.segments.lowerBound)
            - sura.segments.lowerBound
    }

    /// `segmentMarkup`, `updateCard` and `segmentLabel` for the selected sura's segments, numbered within the sura.
    private func refresh() {
        let sura = selectedSura
        cards = zip(segments[sura.segments], contents[sura.segments]).enumerated().map { index, pair in
            let (segment, content) = pair
            let n = ArabicFormat.number(index + 1)
            let count = progress.count(for: segment)
            let complete = progress.isComplete(segment)
            let repeats = segment.repeatCount
            let status = repeats == 1
                ? (count > 0 ? "تمت القراءة" : "لم تُقرأ بعد")
                : "تم \(ArabicFormat.number(count)) من \(ArabicFormat.number(repeats))"
            let label = "المقطع \(n): \(content.surah) \(content.range). \(status)"
            return DeckCard(
                id: segment.id, number: index + 1, content: .ruqyah(content), count: count, target: repeats,
                requirement: Self.repeatLabel(repeats), targetOptions: nil,
                status: repeats == 1 ? .text(complete ? "تمت" : "اضغط بعد القراءة") : .numeric, isReview: false,
                progressLabel: label, tapLabel: complete ? "اكتمل. \(label)" : "تسجيل قراءة المقطع \(n). \(label)",
                resetLabel: "إعادة عداد المقطع \(n)", targetLabel: "")
        }
        currentIndex = max(0, min(currentIndex, cards.count - 1))
    }

    /// `repeatLabel(segment)`.
    private static func repeatLabel(_ repeats: Int) -> String {
        switch repeats {
        case 1: "مرة واحدة"
        case 2: "مرتان"
        default: "\(ArabicFormat.number(repeats)) مرات"
        }
    }
}

private extension HistoryRemoval {
    /// Whether the removal deletes the record of `localDate`.
    func includes(_ localDate: String) -> Bool {
        switch self {
        case let .dates(from, through): from <= localDate && localDate <= through
        case .all: true
        }
    }
}
