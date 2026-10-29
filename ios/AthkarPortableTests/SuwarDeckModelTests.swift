import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

/// 2026-10-01T05:00:00Z, an earlier day's completion.
private let earlierReadAt = Date(timeIntervalSince1970: 1_790_830_800)

/// «سور» as the athkar PWA's «سور» tab reads it: one section per sura, one card per page, each page read once.
final class SuwarDeckModelTests: XCTestCase {
    /// `renderSuwarTabs` and `suraPageMarkup`: the five suras in pack order, each a chip, with its pages as cards
    /// numbered within the sura; the basmala heads a sura's first page only.
    @MainActor
    func testSectionsAndPagesFollowThePack() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeSuwar()
        XCTAssertEqual(deck.definition.id, .suwar)
        XCTAssertEqual(deck.definition.title, "سور")
        XCTAssertEqual(deck.sections.map(\.id), ["kahf", "yasin", "saffat", "waqiah", "mulk"])
        XCTAssertEqual(deck.sections.map(\.title), ["الكهف", "يس", "الصافات", "الواقعة", "الملك"])
        XCTAssertEqual(deck.sections.map(\.accessibilityLabel),
                       ["سورة الكهف", "سورة يس", "سورة الصافات", "سورة الواقعة", "سورة الملك"])
        XCTAssertEqual(deck.sections.filter(\.isComplete), [])
        XCTAssertEqual(deck.selectedSectionID, "kahf", "the setting's default")
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertEqual(deck.cardsLabel, "صفحات سورة الكهف")
        XCTAssertEqual(deck.summary, DeckSummary(copy: "٠ من ٣٤ صفحة", value: 0, total: 34, isComplete: false,
                                                 accessibilityLabel: "سورة الكهف: ٠ من ٣٤ صفحة مقروءة"))
        XCTAssertEqual(deck.listSummary, DeckSummary(copy: "٠ من ٥ سور", value: 0, total: 5, isComplete: false,
                                                     accessibilityLabel: "سور اليوم: ٠ من ٥ سور مكتملة"))
        XCTAssertFalse(deck.isComplete)
        XCTAssertFalse(deck.isDayComplete)
        XCTAssertFalse(deck.canReset)

        let kahf = try XCTUnwrap(support.content.suwar.suwar.first)
        let label = "الصفحة ١ من سورة الكهف، الآيات ١ – ٤، لم تُعلَّم كمقروءة"
        XCTAssertEqual(deck.cards[0], DeckCard(
            id: "kahf-1-4", number: 1,
            content: .page(kahf.pages[0], surah: "سورة الكهف", basmala: support.content.suwar.basmala),
            count: 0, target: 1, requirement: "الآيات ١ – ٤", targetOptions: nil,
            status: .text("اضغط بعد القراءة"), isReview: false, progressLabel: label,
            tapLabel: "تحديد كمقروءة، \(label)", resetLabel: "إعادة الصفحة ١", targetLabel: ""))
        XCTAssertFalse(support.content.suwar.basmala.isEmpty)
        XCTAssertEqual(deck.cards[1].content, .page(kahf.pages[1], surah: "سورة الكهف", basmala: nil))
        XCTAssertEqual(deck.spokenPosition(1), "الصفحة ٢ من ٣٤")

        var ids: [String] = []
        for section in deck.sections {
            deck.selectSection(section.id)
            XCTAssertEqual(deck.selectedSectionID, section.id)
            let sura = try XCTUnwrap(support.content.suwar.suwar.first { $0.id == section.id })
            XCTAssertEqual(deck.cardsLabel, "صفحات \(sura.surah)")
            XCTAssertEqual(deck.cards.map(\.number), Array(1...deck.cards.count), "numbered within \(section.id)")
            XCTAssertEqual(deck.cards.map(\.target), Array(repeating: 1, count: deck.cards.count))
            XCTAssertEqual(deck.cards.map(\.requirement), sura.pages.map(\.range))
            for (index, card) in deck.cards.enumerated() {
                XCTAssertEqual(card.content, .page(sura.pages[index], surah: sura.surah,
                                                   basmala: index == 0 ? support.content.suwar.basmala : nil))
            }
            ids += deck.cards.map(\.id)
        }
        XCTAssertEqual(ids, support.content.suwar.suwar.flatMap { $0.pages.map(\.id) })
        XCTAssertEqual(ids.count, 86)
    }

    /// `markPageRead`: each page counts once, plays the haptic, and moves the deck on; «التالي» waits for the shown
    /// page, and a read page counts nothing more.
    @MainActor
    func testReadingAPageRecordsItOnceAndOpensTheNext() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeSuwar()
        XCTAssertFalse(deck.canMoveForward(from: 0), "«التالي» waits for the shown page")
        XCTAssertEqual(deck.tap(cardAt: 0), DeckChange(completedCard: true, advance: true, haptic: true))
        XCTAssertNil(deck.tap(cardAt: 0), "a read page counts nothing more")
        XCTAssertEqual(deck.currentIndex, 0, "taps do not move the deck; the view advances it")
        XCTAssertTrue(deck.canMoveForward(from: 0))
        XCTAssertFalse(deck.canMoveForward(from: 1))
        XCTAssertTrue(deck.cards[0].isComplete)
        XCTAssertEqual(deck.cards[0].count, 1)
        XCTAssertEqual(deck.cards[0].status, .text("تمت القراءة"))
        let label = "الصفحة ١ من سورة الكهف، الآيات ١ – ٤، تمت قراءتها"
        XCTAssertEqual(deck.cards[0].progressLabel, label)
        XCTAssertEqual(deck.cards[0].tapLabel, "اكتملت، \(label)")
        XCTAssertEqual(deck.summary.copy, "١ من ٣٤ صفحة")
        XCTAssertEqual(deck.summary.accessibilityLabel, "سورة الكهف: ١ من ٣٤ صفحة مقروءة")
        XCTAssertEqual(deck.readPages, ["kahf-1-4"])
        XCTAssertEqual(try support.database.suwar.readPages(on: support.today), ["kahf-1-4"])
        XCTAssertTrue(try support.database.suwar.suraDays(on: support.today).isEmpty)
        XCTAssertTrue(deck.canReset)

        XCTAssertNil(deck.tap(cardAt: -1))
        XCTAssertNil(deck.tap(cardAt: deck.cards.count))
        XCTAssertNil(deck.setTarget(3, forCardAt: 1))
        XCTAssertEqual(try support.database.suwar.readPages(on: support.today), ["kahf-1-4"])
    }

    /// `openSuraCompletionDialog` for «سور»: the last unread page completes the sura, records it once and opens its
    /// dialog with «تم» alone; the chip, the summary and the أخرى line follow.
    @MainActor
    func testCompletingASuraOpensItsDialogWithoutASecondButton() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeSuwar()
        deck.selectSection("mulk")
        XCTAssertEqual(deck.cards.count, 7)
        let started = Date()
        for index in 0..<6 {
            XCTAssertEqual(deck.tap(cardAt: index), DeckChange(completedCard: true, advance: true, haptic: true))
            XCTAssertFalse(deck.isComplete)
        }
        XCTAssertFalse(deck.canMoveForward(from: 6), "the last page has no next")
        XCTAssertEqual(deck.tap(cardAt: 6), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        let mulk = try XCTUnwrap(support.database.suwar.suraDays(on: support.today)["mulk"])
        XCTAssertGreaterThanOrEqual(mulk.timeIntervalSince1970, started.timeIntervalSince1970 - 0.001)
        XCTAssertFalse(deck.canMoveForward(from: 6))
        XCTAssertTrue(deck.isComplete)
        XCTAssertFalse(deck.isDayComplete)
        XCTAssertEqual(deck.summary, DeckSummary(copy: "اكتملت سورة الملك اليوم", value: 7, total: 7, isComplete: true,
                                                 accessibilityLabel: "سورة الملك: ٧ من ٧ صفحة مقروءة"))
        XCTAssertEqual(deck.listSummary.copy, "١ من ٥ سور")
        XCTAssertEqual(deck.listSummary.accessibilityLabel, "سور اليوم: ١ من ٥ سور مكتملة")
        XCTAssertFalse(deck.listSummary.isComplete)
        XCTAssertEqual(deck.sections[4], DeckSection(id: "mulk", title: "الملك", isComplete: true,
                                                     accessibilityLabel: "سورة الملك، مكتملة اليوم"))
        XCTAssertEqual(deck.completion, DeckCompletion(
            title: "اكتملت قراءة سورة الملك بحمد الله", message: "تم حفظ إكمال اليوم محليًا على هذا الجهاز.",
            time: "وقت الإكمال: \(ArabicFormat.time(mulk))", dismissTitle: "تم", primary: nil))

        // A sura completed out of order is complete once its last unread page is read.
        deck.selectSection("waqiah")
        for index in [8, 0, 1, 2, 3, 4, 5, 6] {
            XCTAssertEqual(deck.tap(cardAt: index)?.completedDeck, false)
        }
        XCTAssertEqual(deck.tap(cardAt: 7), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        XCTAssertEqual(Set(try support.database.suwar.suraDays(on: support.today).keys), ["mulk", "waqiah"])
        XCTAssertEqual(deck.listSummary.value, 2)
    }

    /// Every sura read completes the day: the أخرى cell's ✓.
    @MainActor
    func testReadingEverySuraCompletesTheList() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeSuwar()
        for (position, section) in deck.sections.enumerated() {
            deck.selectSection(section.id)
            for index in deck.cards.indices {
                let completesSura = index == deck.cards.count - 1
                let change = try XCTUnwrap(deck.tap(cardAt: index))
                XCTAssertEqual(change, DeckChange(completedCard: true, completedDeck: completesSura,
                                                  advance: !completesSura, haptic: true))
                XCTAssertEqual(deck.isDayComplete, completesSura && position == deck.sections.count - 1)
            }
            XCTAssertEqual(deck.listSummary.value, position + 1)
        }
        XCTAssertTrue(deck.isDayComplete)
        XCTAssertTrue(deck.listSummary.isComplete)
        XCTAssertEqual(deck.listSummary.copy, "٥ من ٥ سور")
        XCTAssertEqual(deck.sections.map(\.isComplete), Array(repeating: true, count: 5))
        XCTAssertEqual(try support.database.suwar.readPages(on: support.today).count, 86)
        XCTAssertTrue(try support.makeSuwar().isDayComplete)
    }

    /// `resetSuraPage` asks nothing: the page is unread again and its sura no longer complete today; reading it
    /// again records a new completion.
    @MainActor
    func testPageResetClearsThePageAndItsSura() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeSuwar()
        deck.selectSection("mulk")
        for index in deck.cards.indices { XCTAssertNotNil(deck.tap(cardAt: index)) }
        XCTAssertNil(deck.resetConfirmation(forCardAt: 2))
        XCTAssertEqual(deck.cards[2].resetLabel, "إعادة الصفحة ٣")
        deck.resetCard(at: 2)
        XCTAssertFalse(deck.cards[2].isComplete)
        XCTAssertEqual(deck.cards[2].status, .text("اضغط بعد القراءة"))
        XCTAssertFalse(deck.isComplete)
        XCTAssertFalse(deck.canMoveForward(from: 2))
        XCTAssertTrue(deck.canMoveForward(from: 1))
        XCTAssertEqual(deck.sections[4].isComplete, false)
        XCTAssertNil(deck.completedSuwar["mulk"])
        XCTAssertTrue(try support.database.suwar.suraDays(on: support.today).isEmpty)
        XCTAssertFalse(try support.database.suwar.readPages(on: support.today).contains("mulk-9-13"))
        XCTAssertEqual(deck.summary.copy, "٦ من ٧ صفحة")
        deck.resetCard(at: 2)
        XCTAssertEqual(try support.database.suwar.readPages(on: support.today).count, 6,
                       "an unread page resets nothing")

        let again = Date()
        XCTAssertEqual(deck.tap(cardAt: 2), DeckChange(completedCard: true, completedDeck: true, haptic: true))
        let mulk = try XCTUnwrap(support.database.suwar.suraDays(on: support.today)["mulk"])
        XCTAssertGreaterThanOrEqual(mulk.timeIntervalSince1970, again.timeIntervalSince1970 - 0.001)
    }

    /// `selectSura` stores the choice, so the app reopens on it; a stored sura the pack does not have opens the
    /// first sura.
    @MainActor
    func testTheSelectedSuraIsKeptAcrossLaunches() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeSuwar()
        XCTAssertEqual(try support.database.settings.value(for: .suwarSelectedSura), "kahf")
        deck.selectSection("yasin")
        XCTAssertEqual(deck.selectedSectionID, "yasin")
        XCTAssertEqual(try support.database.settings.value(for: .suwarSelectedSura), "yasin")
        XCTAssertEqual(try support.makeSuwar().selectedSectionID, "yasin")
        XCTAssertEqual(try support.makeSuwar().cardsLabel, "صفحات سورة يس")

        deck.selectSection("missing")
        XCTAssertEqual(deck.selectedSectionID, "yasin")
        XCTAssertEqual(try support.database.settings.value(for: .suwarSelectedSura), "yasin")

        try support.database.settings.set("baqarah", for: .suwarSelectedSura)
        let unknown = try support.makeSuwar()
        XCTAssertEqual(unknown.selectedSectionID, "kahf")
        XCTAssertEqual(unknown.cards.first?.id, "kahf-1-4")
    }

    /// `renderSuraPages`: a sura opens where the reader left it since the deck opened, otherwise on its first unread
    /// page, or its last page when every page is read; a new day forgets the positions and keeps the sura.
    @MainActor
    func testEachSuraOpensWhereItWasLeftOrOnItsFirstUnreadPage() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeSuwar()
        XCTAssertNotNil(deck.tap(cardAt: 0))
        XCTAssertNotNil(deck.tap(cardAt: 1))
        deck.show(2)
        deck.selectSection("mulk")
        XCTAssertEqual(deck.currentIndex, 0)
        for index in deck.cards.indices { XCTAssertNotNil(deck.tap(cardAt: index)) }
        deck.show(4)
        deck.selectSection("kahf")
        XCTAssertEqual(deck.currentIndex, 2)
        deck.show(1)
        deck.selectSection("mulk")
        XCTAssertEqual(deck.currentIndex, 4)
        deck.selectSection("kahf")
        XCTAssertEqual(deck.currentIndex, 1)
        deck.show(99)
        XCTAssertEqual(deck.currentIndex, 33)
        deck.show(-4)
        XCTAssertEqual(deck.currentIndex, 0)

        // A new launch opens each sura on its first unread page, or a complete sura on its last.
        let reopened = try support.makeSuwar()
        XCTAssertEqual(reopened.selectedSectionID, "kahf")
        XCTAssertEqual(reopened.currentIndex, 2)
        reopened.selectSection("mulk")
        XCTAssertEqual(reopened.currentIndex, 6)
        reopened.selectSection("yasin")
        XCTAssertEqual(reopened.currentIndex, 0)

        // `ensureCurrentDay` clears `suwarIndices` and keeps `selected`.
        deck.selectSection("mulk")
        deck.show(3)
        deck.roll(to: "2026-10-15")
        XCTAssertEqual(deck.date, "2026-10-15")
        XCTAssertEqual(deck.selectedSectionID, "mulk")
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertTrue(deck.readPages.isEmpty)
        XCTAssertTrue(deck.completedSuwar.isEmpty)
        XCTAssertFalse(deck.isComplete)
        XCTAssertTrue(deck.hasHistory, "yesterday's completed sura")
        deck.selectSection("kahf")
        XCTAssertEqual(deck.currentIndex, 0)
        deck.roll(to: "2026-10-15")
        XCTAssertEqual(deck.selectedSectionID, "kahf", "the same day does not roll")
    }

    /// `resetSuwarProgress` and `deleteSuwarHistory`: today's pages and completions are cleared and every sura
    /// reopens on its first page; the selected sura stays. The confirmations count the earlier days with a
    /// completed sura.
    @MainActor
    func testScopedResetsKeepTheSelectedSura() throws {
        let support = try PortableTestSupport()
        try support.database.suwar.markRead("mulk-27-30", of: "mulk", on: "2026-10-01", completingSura: true,
                                            at: earlierReadAt)
        try support.database.suwar.markRead("mulk-1-4", of: "mulk", on: "2026-10-02", at: earlierReadAt)
        let deck = try support.makeSuwar()
        XCTAssertTrue(deck.hasHistory)
        XCTAssertTrue(deck.canReset, "history alone is resettable")
        XCTAssertNil(deck.confirmation(for: .day))
        XCTAssertEqual(deck.confirmation(for: .everything), DeckConfirmation(
            title: "حذف كل شيء؟", message: "ستُعاد العدادات وسيُحذف السجل كاملًا (يوم واحد). لا يمكن التراجع."))

        deck.selectSection("waqiah")
        for index in deck.cards.indices { XCTAssertNotNil(deck.tap(cardAt: index)) }
        deck.selectSection("yasin")
        XCTAssertNotNil(deck.tap(cardAt: 0))
        deck.show(1)
        XCTAssertEqual(deck.confirmation(for: .everything)?.message,
                       "ستُعاد العدادات وسيُحذف السجل كاملًا (يوم واحد). لا يمكن التراجع.",
                       "today's completed sura is today's progress")

        XCTAssertTrue(deck.reset(.day))
        XCTAssertEqual(deck.selectedSectionID, "yasin")
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertTrue(deck.readPages.isEmpty)
        XCTAssertTrue(deck.completedSuwar.isEmpty)
        XCTAssertEqual(deck.listSummary.value, 0)
        XCTAssertTrue(deck.hasHistory)
        XCTAssertTrue(deck.canReset)
        XCTAssertTrue(try support.database.suwar.readPages(on: support.today).isEmpty)
        XCTAssertTrue(try support.database.suwar.suraDays(on: support.today).isEmpty)
        XCTAssertEqual(try support.database.suwar.readPages(on: "2026-10-02"), ["mulk-1-4"], "earlier days stay")
        XCTAssertEqual(try support.database.settings.value(for: .suwarSelectedSura), "yasin")
        deck.selectSection("waqiah")
        XCTAssertEqual(deck.currentIndex, 0, "every sura reopens on its first page")

        XCTAssertNotNil(deck.tap(cardAt: 0))
        XCTAssertTrue(deck.reset(.everything))
        XCTAssertEqual(deck.selectedSectionID, "waqiah")
        XCTAssertFalse(deck.hasHistory)
        XCTAssertFalse(deck.canReset)
        XCTAssertEqual(try support.database.suwar.recordedDayCount(.all, before: "9999-12-31"), 0)
        XCTAssertTrue(try support.database.suwar.readPages(on: "2026-10-02").isEmpty)
        XCTAssertEqual(deck.confirmation(for: .everything)?.message,
                       "ستُعاد العدادات وسيُحذف السجل كاملًا. لا يمكن التراجع.")

        XCTAssertNotNil(deck.tap(cardAt: 0))
        XCTAssertTrue(deck.reset(.week))
        XCTAssertTrue(deck.readPages.isEmpty)
        XCTAssertEqual(deck.selectedSectionID, "waqiah")
        XCTAssertFalse(deck.canReset)
    }
}
