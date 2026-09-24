import AthkarCore
import Foundation
import Observation

/// The ruqyah deck: today's segment counters (`ruqyah-daily-v1.counts`) and whether today is recorded complete,
/// kept in `ruqyah_segment_progress` / `ruqyah_days` after every change.
@MainActor
@Observable
final class RuqyahDeckModel: DeckModel {
    let definition = DeckDefinition.ruqyah
    private(set) var cards: [DeckCard] = []
    private(set) var currentIndex = 0
    private(set) var progress: RuqyahProgress
    /// When today was recorded complete (`state.history[today].completedAt`).
    private(set) var completedAt: Date?
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
        completedAt = try repository.day(on: today)?.completedAt
        hasHistory = try repository.dayCount(.all) > 0
        currentIndex = progress.firstIncompleteIndex(in: segments)
        refresh()
    }

    /// `ensureCurrentDay`: a new day starts with that day's counters, on the first segment.
    func roll(to today: String) {
        guard today != progress.date else { return }
        reload(date: today)
        currentIndex = progress.firstIncompleteIndex(in: segments)
        refresh()
    }

    private var totalRepeats: Int { segments.reduce(0) { $0 + $1.repeatCount } }

    var summary: DeckSummary {
        let done = progress.readings(in: segments)
        let total = totalRepeats
        let copy = "\(ArabicFormat.number(done)) من \(ArabicFormat.number(total)) تكرارًا"
        return DeckSummary(
            copy: copy, value: done, total: total, isComplete: completedAt != nil || done >= total,
            accessibilityLabel: "تقدم رقية اليوم: \(copy)",
            status: completedAt.map { "تمت رقية اليوم في \(ArabicFormat.time($0))." } ?? "رقية اليوم لم تكتمل بعد.")
    }

    var isComplete: Bool { completedAt != nil }

    var completion: DeckCompletion {
        DeckCompletion(title: "تمت الرقية بحمد الله", message: "اكتملت جميع المقاطع بتكراراتها.", time: nil,
                       dismissTitle: "إغلاق", primaryTitle: "بدء رقية جديدة", primary: .restart)
    }

    func show(_ index: Int) {
        currentIndex = max(0, min(index, segments.count - 1))
    }

    /// The ruqyah deck never locks «التالي».
    func canMoveForward(from index: Int) -> Bool { index < segments.count - 1 }

    /// `countReading`: when every segment is complete, today is recorded (once) and the dialog opens.
    func tap(cardAt index: Int) -> DeckChange? {
        guard let segment = segments[safe: index], let next = progress.countReading(segment) else { return nil }
        let allComplete = progress.allComplete(segments)
        let now = Date()
        do {
            try repository.setCount(next, for: segment.id, on: progress.date,
                                    completingDayAt: allComplete ? now : nil, at: now)
        } catch {
            report(error)
        }
        if allComplete, completedAt == nil {
            completedAt = now
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
        progress.counts[segment.id] = 0
        do {
            try repository.setCount(0, for: segment.id, on: progress.date)
        } catch {
            report(error)
        }
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

    /// `resetDayProgress`, `resetWeek`, `resetEverything`; each starts again on the first segment.
    func reset(_ scope: ResetScope) {
        let now = Date()
        let removal: HistoryRemoval? = switch scope {
        case .day: nil
        case .week: .week(endingAt: now, in: .current)
        case .everything: .all
        }
        do {
            try repository.resetCounts(on: progress.date, removing: removal, at: now)
        } catch {
            report(error)
        }
        reload(date: progress.date)
        currentIndex = 0
        refresh()
    }

    // MARK: Private

    private func reload(date: String) {
        do {
            progress = RuqyahProgress(date: date, counts: try repository.counts(on: date))
            completedAt = try repository.day(on: date)?.completedAt
            hasHistory = try repository.dayCount(.all) > 0
        } catch {
            report(error)
            progress = RuqyahProgress(date: date)
            completedAt = nil
        }
    }

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
