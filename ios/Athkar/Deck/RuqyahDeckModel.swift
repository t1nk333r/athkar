import AthkarCore
import Foundation
import Observation

/// The ruqyah deck: today's segment counters (`ruqyah-daily-v1.counts`) and whether today is recorded complete,
/// as stored in `ruqyah_segment_progress` / `ruqyah_days`. A change is shown only once its transaction is stored,
/// and a day only once it has been read.
@MainActor
@Observable
final class RuqyahDeckModel: DeckModel {
    let definition = DeckDefinition.ruqyah
    private(set) var cards: [DeckCard] = []
    private(set) var currentIndex = 0
    private(set) var progress: RuqyahProgress
    /// Today's `ruqyah_days` row (`state.history[today]`). The row alone records the day complete.
    private(set) var completedDay: RuqyahDay?
    private(set) var hasHistory: Bool

    @ObservationIgnored private let segments: [RuqyahSegment]
    @ObservationIgnored private let contents: [RuqyahSegmentContent]
    @ObservationIgnored private let repository: RuqyahRepository
    @ObservationIgnored private let report: (any Error) -> Void

    init(database: AppDatabase, content: BundledContent, today: String, report: @escaping (any Error) -> Void) throws {
        segments = content.packs.ruqyahSegments
        contents = content.ruqyah
        repository = database.ruqyah
        self.report = report
        progress = RuqyahProgress(date: today, counts: try repository.counts(on: today))
        completedDay = try repository.day(on: today)
        hasHistory = try repository.dayCount(.all) > 0
        currentIndex = progress.firstIncompleteIndex(in: segments)
        refresh()
    }

    /// `ensureCurrentDay`: a new day starts with that day's counters, on the first segment. A day that cannot be
    /// read is not shown: the deck keeps its day, so the next `ensureCurrentDay` tries again.
    func roll(to today: String) {
        guard today != progress.date else { return }
        do {
            let counts = try repository.counts(on: today)
            let day = try repository.day(on: today)
            let hasHistory = try repository.dayCount(.all) > 0
            progress = RuqyahProgress(date: today, counts: counts)
            completedDay = day
            self.hasHistory = hasHistory
        } catch {
            report(error)
            return
        }
        currentIndex = progress.firstIncompleteIndex(in: segments)
        refresh()
    }

    private var totalRepeats: Int { segments.reduce(0) { $0 + $1.repeatCount } }

    var summary: DeckSummary {
        let done = progress.readings(in: segments)
        let total = totalRepeats
        let copy = "\(ArabicFormat.number(done)) من \(ArabicFormat.number(total)) تكرارًا"
        return DeckSummary(
            copy: copy, value: done, total: total, isComplete: isComplete,
            accessibilityLabel: "تقدم رقية اليوم: \(copy)",
            status: completedAt.map { "تمت رقية اليوم في \(ArabicFormat.time($0))." } ?? "رقية اليوم لم تكتمل بعد.")
    }

    var isComplete: Bool { completedDay != nil }

    /// When today was recorded complete (`state.history[today].completedAt`).
    var completedAt: Date? { completedDay?.completedAt }

    var completion: DeckCompletion {
        DeckCompletion(title: "تمت الرقية بحمد الله", message: "اكتملت جميع المقاطع بتكراراتها.", time: nil,
                       dismissTitle: "إغلاق", primaryTitle: "بدء رقية جديدة", primary: .restart)
    }

    func show(_ index: Int) {
        currentIndex = max(0, min(index, segments.count - 1))
    }

    /// The ruqyah deck never locks «التالي».
    func canMoveForward(from index: Int) -> Bool { index < segments.count - 1 }

    /// `countReading`: when every segment is complete, today is recorded (once) and the dialog opens. A reading
    /// that is not stored is not counted: `nil`, as for a complete segment.
    func tap(cardAt index: Int) -> DeckChange? {
        var counted = progress
        guard let segment = segments[safe: index], let next = counted.countReading(segment) else { return nil }
        let allComplete = counted.allComplete(segments)
        let now = Date()
        do {
            try repository.setCount(next, for: segment.id, on: counted.date,
                                    completingDayAt: allComplete ? now : nil, at: now)
        } catch {
            report(error)
            return nil
        }
        progress = counted
        if allComplete, completedDay == nil {
            // The same transaction inserted the row; an existing row keeps its first time.
            completedDay = RuqyahDay(localDate: counted.date, completedAt: now, completionOrigin: .counters)
            hasHistory = true
        }
        refresh()
        let completesSegment = next >= segment.repeatCount
        return DeckChange(completedCard: completesSegment, completedDeck: allComplete,
                          advance: completesSegment && !allComplete)
    }

    func setTarget(_ target: Int, forCardAt index: Int) -> DeckChange? { nil }

    /// `resetSegment` always asks.
    func resetConfirmation(forCardAt index: Int) -> DeckConfirmation? {
        guard let segment = segments[safe: index], progress.count(for: segment) > 0 else { return nil }
        let content = contents[index]
        return DeckConfirmation(title: "إعادة العداد؟", message: "سيعود عداد \(content.surah) \(content.range) إلى الصفر.")
    }

    func resetCard(at index: Int) {
        guard let segment = segments[safe: index], progress.count(for: segment) > 0 else { return }
        do {
            try repository.setCount(0, for: segment.id, on: progress.date)
        } catch {
            report(error)
            return
        }
        progress.counts[segment.id] = 0
        refresh()
    }

    var canReset: Bool { progress.readings(in: segments) > 0 || hasHistory }

    func confirmation(for scope: ResetScope) -> DeckConfirmation? {
        let removal: HistoryRemoval
        switch scope {
        case .day: return nil
        case .week: removal = .week(endingAt: Date(), in: .current)
        case .everything: removal = .all
        }
        return scope.confirmation(recordedDays: (try? repository.dayCount(removal)) ?? 0)
    }

    /// `resetDayProgress`, `resetWeek`, `resetEverything`; each starts again on the first segment. تقدم اليوم (and
    /// «بدء رقية جديدة») keeps today's record. A reset that is not stored changes nothing.
    func reset(_ scope: ResetScope) {
        let now = Date()
        let removal: HistoryRemoval? = switch scope {
        case .day: nil
        case .week: .week(endingAt: now, in: .current)
        case .everything: .all
        }
        let keepsHistory: Bool
        do {
            // Read first, so that once the transaction is stored nothing is left to fail.
            keepsHistory = try removal.map { try repository.dayCount(.all) > repository.dayCount($0) } ?? hasHistory
            try repository.resetCounts(on: progress.date, removing: removal, at: now)
        } catch {
            report(error)
            return
        }
        // What the transaction stored: every counter of the day is 0, and the days `removal` covers are gone.
        progress.counts = progress.counts.mapValues { _ in 0 }
        if let removal, removal.includes(progress.date) { completedDay = nil }
        hasHistory = keepsHistory
        currentIndex = 0
        refresh()
    }

    // MARK: Private

    /// `segmentMarkup`, `updateCard` and `segmentLabel` for every segment.
    private func refresh() {
        cards = zip(segments, contents).enumerated().map { index, pair in
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
        currentIndex = max(0, min(currentIndex, segments.count - 1))
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
