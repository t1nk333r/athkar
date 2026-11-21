import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

/// 2026-10-01T20:00:00Z, an earlier day's completion.
private let earlierCompletion = Date(timeIntervalSince1970: 1_790_884_800)

/// The reading decks «أذكار النوم» and «الصلاة على النبي ﷺ» (spec/sessions/deck-definition.md §12): one card per item
/// in pack order, counted and saved per local date, with their own history.
final class ReadingDeckModelTests: XCTestCase {
    /// One card per sleep item: thirteen counted, sleep-04 and sleep-06 three times, the four situational items
    /// uncounted with «عند الحاجة» in place of a counter; al-Mulk comes whole from the suwar pack.
    @MainActor
    func testSleepCardsFollowThePack() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeReading(.sleep)
        let sleep = support.content.sleep
        XCTAssertEqual(deck.definition.id, .sleep)
        XCTAssertEqual(deck.definition.title, "أذكار النوم")
        XCTAssertEqual(deck.cardsLabel, "بطاقات أذكار النوم")
        XCTAssertEqual(deck.definition.indexTitle, "فهرس الأذكار")
        XCTAssertEqual(deck.definition.indexHint, "يعرض فهرس الأذكار للانتقال إلى بطاقة")
        XCTAssertEqual(deck.definition.hint, "اسحب للتنقل؛ ويظهر التالي تلقائيًا بعد الإكمال.")
        XCTAssertTrue(deck.sections.isEmpty)
        XCTAssertEqual(deck.cards.map(\.id), sleep.items.map(\.id))
        XCTAssertEqual(deck.cards.count, 17)
        XCTAssertEqual(deck.cards.map(\.number), Array(1...17))
        XCTAssertEqual(deck.cards.filter { !$0.isUncounted }.count, 13)
        XCTAssertEqual(deck.cards.filter(\.isUncounted).map(\.id), ["sleep-14", "sleep-15", "sleep-16", "sleep-17"])
        XCTAssertEqual(deck.cards.filter { $0.target == 3 }.map(\.id), ["sleep-04", "sleep-06"])
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertEqual(deck.spokenPosition(0), "البطاقة ١ من ١٧")
        XCTAssertEqual(deck.summary, DeckSummary(copy: "٠ من ١٣", value: 0, total: 13, isComplete: false,
                                                 accessibilityLabel: "أذكار النوم: ٠ من ١٣"))
        XCTAssertEqual(deck.listSummary.copy, "قبل النوم وفي الليل")
        XCTAssertFalse(deck.isComplete)
        XCTAssertFalse(deck.canReset)

        let kursi = try XCTUnwrap(sleep.items.first)
        let passage = try XCTUnwrap(kursi.quran?.first)
        XCTAssertEqual(deck.cards[0], DeckCard(
            id: "sleep-01", number: 1,
            content: .reading(ReadingCardContent(
                title: "آية الكرسي",
                passages: [.init(basmala: passage.basmala ? sleep.basmala : nil, text: passage.text,
                                 citation: passage.citation)],
                note: kursi.note?.text)),
            count: 0, target: 1, requirement: "مرة واحدة", targetOptions: nil, status: .text("اضغط بعد القراءة"),
            isReview: false, progressLabel: "البطاقة ١، لم تُعلَّم كمقروءة",
            tapLabel: "تحديد كمقروءة، البطاقة ١. البطاقة ١، لم تُعلَّم كمقروءة", resetLabel: "إعادة عداد البطاقة ١",
            targetLabel: ""))
        XCTAssertEqual(deck.cards[3].requirement, "ثلاث مرات")
        XCTAssertEqual(deck.cards[3].status, .numeric)
        XCTAssertEqual(deck.cards[3].progressLabel, "البطاقة ٤، كُرّر ٠ من أصل ٣ مرات")
        XCTAssertEqual(deck.cards[3].tapLabel, "زيادة عداد البطاقة ٤. البطاقة ٤، كُرّر ٠ من أصل ٣ مرات")
        guard case let .reading(mulk) = deck.cards[11].content else { return XCTFail("al-Mulk is a reading card") }
        XCTAssertEqual(mulk.title, "سورة الملك")
        XCTAssertEqual(mulk.passages.count, 1)
        XCTAssertEqual(mulk.passages[0].citation, "الملك")
        XCTAssertEqual(mulk.passages[0].basmala, support.content.suwar.basmala)
        XCTAssertTrue(mulk.passages[0].text.hasSuffix("﴿٣٠﴾"), "the whole sura")
        guard case let .reading(steps) = deck.cards[15].content else { return XCTFail("sleep-16 is a reading card") }
        XCTAssertFalse(steps.steps.isEmpty)

        let night = deck.cards[13]
        XCTAssertTrue(night.isUncounted)
        XCTAssertTrue(night.isComplete)
        XCTAssertEqual(night.status, .text("عند الحاجة"))
        XCTAssertEqual(night.requirement, "")
        XCTAssertEqual(night.progressLabel, "البطاقة ١٤، عند الحاجة")
        XCTAssertTrue(deck.canMoveForward(from: 13), "an uncounted card never locks")
        XCTAssertFalse(deck.canMoveForward(from: 16), "the last card has no next")
        XCTAssertNil(deck.tap(cardAt: 13), "never counted")
        XCTAssertTrue(try support.database.reading.counts(.sleep, on: support.today).isEmpty)
    }

    /// Salawat opens with al-Ahzab 56 and the Friday virtue under the Friday pill, an uncounted card with «اقرأ ثم
    /// اسحب»; then one card per salawat, each read once. The deck opens on its first incomplete counted card.
    @MainActor
    func testSalawatHasAnUncountedOpeningCard() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeReading(.salawat)
        let salawat = support.content.salawat
        XCTAssertEqual(deck.definition.title, "الصلاة على النبي ﷺ")
        XCTAssertEqual(deck.cardsLabel, "بطاقات الصلاة على النبي ﷺ")
        XCTAssertEqual(deck.cards.map(\.id), ["salawat-quran", "salawat-01", "salawat-02"])
        XCTAssertEqual(deck.cards[0], DeckCard(
            id: "salawat-quran", number: 1,
            content: .reading(ReadingCardContent(
                passages: [.init(basmala: nil, text: salawat.quran.text, citation: "الأحزاب ٥٦")],
                note: salawat.virtue.text, showsFridayPill: true)),
            count: 0, target: 1, requirement: "", targetOptions: nil, status: .text("اقرأ ثم اسحب"), isReview: false,
            progressLabel: "البطاقة ١، الآية والفضل", tapLabel: "اكتمل، البطاقة ١. البطاقة ١، الآية والفضل",
            resetLabel: "إعادة عداد البطاقة ١", targetLabel: "", isUncounted: true))
        XCTAssertEqual(deck.cards[1].content, .reading(ReadingCardContent(
            title: "الصلاة على النبي ﷺ", text: salawat.items[0].text, note: salawat.items[0].note?.text)))
        XCTAssertEqual(deck.cards[1].requirement, "مرة واحدة")
        XCTAssertEqual(deck.cards.map(\.target), [1, 1, 1])
        XCTAssertEqual(deck.currentIndex, 0, "card 1 while nothing is counted today")
        XCTAssertTrue(deck.canMoveForward(from: 0))
        XCTAssertFalse(deck.canMoveForward(from: 1))
        XCTAssertNil(deck.tap(cardAt: 0))
        XCTAssertEqual(deck.summary.copy, "٠ من ٢")
        XCTAssertEqual(deck.listSummary.copy, "صيغتان")
    }

    /// Each tap counts one, saved; the haptic plays when a card reaches its target, whatever the target, and the deck
    /// then moves on. A complete card counts nothing more, and «التالي» waits for the card on screen.
    @MainActor
    func testCountingToTheTargetThenAdvancing() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeReading(.sleep)
        XCTAssertFalse(deck.canMoveForward(from: 0))
        XCTAssertEqual(deck.tap(cardAt: 0), DeckChange(completedCard: true, advance: true, haptic: true))
        XCTAssertNil(deck.tap(cardAt: 0))
        XCTAssertEqual(deck.currentIndex, 0, "taps do not move the deck; the view advances it")
        XCTAssertTrue(deck.canMoveForward(from: 0))
        XCTAssertEqual(deck.cards[0].status, .text("تمت القراءة"))
        XCTAssertEqual(deck.cards[0].progressLabel, "البطاقة ١، قُرئت")
        XCTAssertEqual(deck.cards[0].tapLabel, "اكتمل، البطاقة ١. البطاقة ١، قُرئت")
        XCTAssertEqual(deck.listSummary.copy, "١ من ١٣", "the summary once today has a count")

        XCTAssertEqual(deck.tap(cardAt: 3), DeckChange())
        XCTAssertEqual(deck.tap(cardAt: 3), DeckChange())
        XCTAssertFalse(deck.canMoveForward(from: 3))
        XCTAssertEqual(deck.cards[3].count, 2)
        XCTAssertEqual(deck.cards[3].progressLabel, "البطاقة ٤، كُرّر ٢ من أصل ٣ مرات")
        XCTAssertEqual(deck.tap(cardAt: 3), DeckChange(completedCard: true, advance: true, haptic: true))
        XCTAssertNil(deck.tap(cardAt: 3))
        XCTAssertEqual(deck.cards[3].progressLabel, "البطاقة ٤، كُرّر ٣ من أصل ٣ مرات، اكتمل")
        XCTAssertEqual(deck.cards[3].tapLabel, "اكتمل، البطاقة ٤. البطاقة ٤، كُرّر ٣ من أصل ٣ مرات، اكتمل")
        XCTAssertTrue(deck.canMoveForward(from: 3))
        XCTAssertEqual(try support.database.reading.counts(.sleep, on: support.today),
                       ["sleep-01": 1, "sleep-04": 3])
        XCTAssertEqual(deck.summary.copy, "٢ من ١٣")
        XCTAssertNil(deck.setTarget(10, forCardAt: 3))
        XCTAssertNil(deck.tap(cardAt: -1))
        XCTAssertNil(deck.tap(cardAt: deck.cards.count))
        XCTAssertTrue(deck.canReset)
        XCTAssertNil(try support.database.reading.day(.sleep, on: support.today))
    }

    /// The reading that completes the day records it in the same write, once, and opens the dialog with «تم» alone;
    /// a card reset deletes the record, and completing again records a new time.
    @MainActor
    func testCompletingTheDayRecordsItOnceAndACardResetClearsIt() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeReading(.salawat)
        XCTAssertEqual(deck.tap(cardAt: 1), DeckChange(completedCard: true, advance: true, haptic: true))
        let started = Date()
        XCTAssertEqual(deck.tap(cardAt: 2), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        let day = try XCTUnwrap(support.database.reading.day(.salawat, on: support.today))
        XCTAssertGreaterThanOrEqual(day.completedAt.timeIntervalSince1970, started.timeIntervalSince1970 - 0.001)
        XCTAssertTrue(deck.isComplete)
        XCTAssertTrue(deck.isDayComplete)
        XCTAssertEqual(deck.summary, DeckSummary(copy: "اكتملت الصلاة على النبي ﷺ اليوم", value: 2, total: 2,
                                                 isComplete: true, accessibilityLabel: "الصلاة على النبي ﷺ: ٢ من ٢"))
        XCTAssertTrue(deck.listSummary.isComplete)
        XCTAssertEqual(deck.completion, DeckCompletion(
            title: "تمت الصلاة على النبي ﷺ بحمد الله", message: "حُفظ إكمال اليوم على هذا الجهاز.",
            time: "وقت الإكمال: \(ArabicFormat.time(day.completedAt))", dismissTitle: "تم", primary: nil))
        let reopened = try support.makeReading(.salawat)
        XCTAssertTrue(reopened.isComplete)
        XCTAssertEqual(reopened.currentIndex, 2, "the last card when the day is complete")

        XCTAssertNil(deck.resetConfirmation(forCardAt: 2), "a card reset never asks")
        XCTAssertEqual(deck.cards[2].resetLabel, "إعادة عداد البطاقة ٣")
        deck.resetCard(at: 2)
        XCTAssertFalse(deck.isComplete)
        XCTAssertFalse(deck.cards[2].isComplete)
        XCTAssertNil(try support.database.reading.day(.salawat, on: support.today))
        XCTAssertEqual(try support.database.reading.counts(.salawat, on: support.today),
                       ["salawat-01": 1, "salawat-02": 0])
        XCTAssertEqual(deck.summary.copy, "١ من ٢")
        deck.resetCard(at: 0)
        deck.resetCard(at: 2)
        XCTAssertEqual(try support.database.reading.counts(.salawat, on: support.today)["salawat-02"], 0,
                       "an uncounted or unread card resets nothing")

        let again = Date()
        XCTAssertEqual(deck.tap(cardAt: 2), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        let recorded = try XCTUnwrap(support.database.reading.day(.salawat, on: support.today))
        XCTAssertGreaterThanOrEqual(recorded.completedAt.timeIntervalSince1970, again.timeIntervalSince1970 - 0.001)

        let sleep = try support.makeReading(.sleep)
        XCTAssertFalse(sleep.isComplete, "each deck has its own record")
        XCTAssertFalse(sleep.canReset)
    }

    /// The sleep day is complete once its thirteen counted cards are; the situational cards are never needed.
    @MainActor
    func testSleepDayNeedsOnlyItsCountedCards() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeReading(.sleep)
        var changes: [DeckChange] = []
        for (index, card) in deck.cards.enumerated() where !card.isUncounted {
            for _ in 0..<card.target { changes.append(try XCTUnwrap(deck.tap(cardAt: index))) }
        }
        XCTAssertEqual(changes.filter(\.completedDeck).count, 1)
        XCTAssertEqual(changes.last, DeckChange(completedCard: true, completedDeck: true, haptic: true))
        XCTAssertEqual(changes.filter(\.haptic).count, 13)
        XCTAssertTrue(deck.isComplete)
        XCTAssertEqual(deck.summary.copy, "اكتملت أذكار النوم اليوم")
        XCTAssertEqual(deck.completion.title, "تمت أذكار النوم بحمد الله")
        XCTAssertEqual(try support.makeReading(.sleep).currentIndex, 16)
    }

    /// Counts are clamped to the installed pack's target, and a count for an item it does not count is ignored.
    @MainActor
    func testStoredCountsAreReadAgainstThePack() throws {
        let support = try PortableTestSupport()
        let reading = support.database.reading
        try reading.setCount(9, for: "sleep-04", in: .sleep, on: support.today)
        try reading.setCount(2, for: "sleep-14", in: .sleep, on: support.today)
        try reading.setCount(2, for: "sleep-99", in: .sleep, on: support.today)
        let deck = try support.makeReading(.sleep)
        XCTAssertEqual(deck.cards[3].count, 3)
        XCTAssertEqual(deck.cards[13].count, 0)
        XCTAssertEqual(deck.summary.value, 1)
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertNil(deck.tap(cardAt: 3), "already at its target")
    }

    /// `ensureCurrentDay`: a new date starts with no counts and opens on its first card; the previous date
    /// stays in history. The last card shown is kept until then.
    @MainActor
    func testDayRolloverStartsANewDateAndKeepsTheLastOneAsHistory() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeReading(.salawat)
        XCTAssertNotNil(deck.tap(cardAt: 1))
        XCTAssertNotNil(deck.tap(cardAt: 2))
        deck.show(0)
        XCTAssertEqual(deck.currentIndex, 0, "the last card shown")
        deck.roll(to: support.today)
        XCTAssertEqual(deck.currentIndex, 0, "the same day does not roll")

        deck.roll(to: "2026-10-15")
        XCTAssertEqual(deck.date, "2026-10-15")
        XCTAssertEqual(deck.currentIndex, 0, "the opening card on a day with no counts")
        XCTAssertFalse(deck.isComplete)
        XCTAssertEqual(deck.cards.map(\.count), [0, 0, 0])
        XCTAssertEqual(deck.listSummary.copy, "صيغتان")
        XCTAssertTrue(deck.hasHistory)
        XCTAssertTrue(deck.canReset, "yesterday's record")
        XCTAssertEqual(deck.confirmation(for: .everything)?.message,
                       "ستُعاد العدادات وسيُحذف السجل كاملًا (يوم واحد). لا يمكن التراجع.")
        XCTAssertNotNil(deck.tap(cardAt: 1))
        XCTAssertEqual(try support.database.reading.counts(.salawat, on: "2026-10-15"), ["salawat-01": 1])
        XCTAssertNotNil(try support.database.reading.day(.salawat, on: support.today))
    }

    /// تقدم اليوم deletes today's counts and record and keeps earlier days; هذا الأسبوع and كل شيء also delete the
    /// deck's history in scope. The confirmations count the earlier days with a record, and the other deck stays.
    @MainActor
    func testScopedResetsAndTheirConfirmations() throws {
        let support = try PortableTestSupport()
        let reading = support.database.reading
        try reading.setCount(1, for: "sleep-01", in: .sleep, on: "2026-10-01", completingDayAt: earlierCompletion,
                             at: earlierCompletion)
        try reading.setCount(1, for: "sleep-01", in: .sleep, on: "2026-10-10", completingDayAt: earlierCompletion,
                             at: earlierCompletion)
        try reading.setCount(1, for: "salawat-01", in: .salawat, on: "2026-10-10", at: earlierCompletion)
        let deck = try support.makeReading(.sleep)
        XCTAssertTrue(deck.hasHistory)
        XCTAssertTrue(deck.canReset, "history alone is resettable")
        XCTAssertNil(deck.confirmation(for: .day))
        XCTAssertEqual(deck.confirmation(for: .everything), DeckConfirmation(
            title: "حذف كل شيء؟", message: "ستُعاد العدادات وسيُحذف السجل كاملًا (يومين). لا يمكن التراجع."))

        for (index, card) in deck.cards.enumerated() where !card.isUncounted {
            for _ in 0..<card.target { XCTAssertNotNil(deck.tap(cardAt: index)) }
        }
        XCTAssertTrue(deck.isComplete)
        XCTAssertEqual(deck.confirmation(for: .everything)?.message,
                       "ستُعاد العدادات وسيُحذف السجل كاملًا (يومين). لا يمكن التراجع.",
                       "today's record is today's progress")
        deck.show(14)

        XCTAssertTrue(deck.reset(.day))
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertFalse(deck.isComplete)
        XCTAssertEqual(deck.summary.value, 0)
        XCTAssertTrue(deck.hasHistory)
        XCTAssertTrue(deck.canReset)
        XCTAssertTrue(try reading.counts(.sleep, on: support.today).isEmpty)
        XCTAssertNil(try reading.day(.sleep, on: support.today))
        XCTAssertEqual(try reading.recordedDayCount(.sleep, .all, before: support.today), 2, "earlier days stay")

        XCTAssertNotNil(deck.tap(cardAt: 0))
        XCTAssertTrue(deck.reset(.everything))
        XCTAssertFalse(deck.hasHistory)
        XCTAssertFalse(deck.canReset)
        XCTAssertEqual(try reading.recordedDayCount(.sleep, .all, before: "9999-12-31"), 0)
        XCTAssertTrue(try reading.counts(.sleep, on: "2026-10-01").isEmpty)
        XCTAssertEqual(deck.confirmation(for: .everything)?.message,
                       "ستُعاد العدادات وسيُحذف السجل كاملًا. لا يمكن التراجع.")
        XCTAssertEqual(try reading.counts(.salawat, on: "2026-10-10"), ["salawat-01": 1], "the other deck stays")

        XCTAssertNotNil(deck.tap(cardAt: 0))
        XCTAssertTrue(deck.reset(.week))
        XCTAssertTrue(try reading.counts(.sleep, on: support.today).isEmpty)
        XCTAssertFalse(deck.canReset)
    }
}
