import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

/// The quick index's rules (spec §4, "Native quick index") on the production deck models and database: which rows
/// open their card, and where a choice leads once the sheet has closed.
final class DeckIndexReachabilityTests: XCTestCase {
    private let nextDay = "2026-10-15"

    @MainActor
    func testAdhkarIndexOpensEarlierAndCurrentCardsButNoneBeyondAnUnreadOne() throws {
        let support = try PortableTestSupport()
        let deck = AdhkarDeckModel(period: .morning, session: try support.makeAdhkar())
        let count = deck.cards.count
        XCTAssertGreaterThan(count, 3)
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertFalse(deck.cards[0].isComplete)
        XCTAssertTrue(deck.canReach(0))
        XCTAssertEqual((1..<count).filter { deck.canReach($0) }, [], "every later card waits for the first")

        read(deck, 0)
        XCTAssertTrue(deck.canReach(1))
        XCTAssertFalse(deck.cards[1].isComplete)
        XCTAssertFalse(deck.canReach(2))

        deck.show(1)
        XCTAssertTrue(deck.canReach(0), "an earlier card")
        XCTAssertTrue(deck.canReach(1), "the current card")
        XCTAssertFalse(deck.canReach(2))
        XCTAssertFalse(deck.canReach(-1))
        XCTAssertFalse(deck.canReach(count))
    }

    @MainActor
    func testAdhkarIndexNeedsEveryCardBeforeTheRowRead() throws {
        let support = try PortableTestSupport()
        let deck = AdhkarDeckModel(period: .morning, session: try support.makeAdhkar())
        for index in [0, 1, 3] { read(deck, index) }
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertTrue(deck.canReach(2))
        XCTAssertTrue(deck.cards[3].isComplete)
        XCTAssertFalse(deck.canReach(3), "a read card behind an unread one stays closed")
        XCTAssertFalse(deck.canReach(4))

        read(deck, 2)
        XCTAssertTrue(deck.canReach(3))
        XCTAssertTrue(deck.canReach(4))
        XCTAssertFalse(deck.cards[4].isComplete)
        XCTAssertFalse(deck.canReach(5))
    }

    /// From any card, the rows the index opens are the cards «التالي» reaches one step at a time.
    @MainActor
    func testIndexMatchesWhatNextCanReach() throws {
        let support = try PortableTestSupport()
        let session = try support.makeAdhkar()
        let deck = AdhkarDeckModel(period: .morning, session: session)
        for index in [0, 1, 2, 4, 5] { read(deck, index) }
        session.applyLongOrder(true, active: .morning)
        for start in deck.cards.indices {
            deck.show(start)
            var reached = Set(0...start)
            var index = start
            while index < deck.cards.count - 1, deck.canMoveForward(from: index) {
                index += 1
                reached.insert(index)
            }
            XCTAssertEqual(Set(deck.cards.indices.filter { deck.canReach($0) }), reached, "from card \(start + 1)")
        }
    }

    @MainActor
    func testManualCompletionOpensEveryAdhkarCardWithoutCompletingAny() throws {
        let support = try PortableTestSupport()
        let session = try support.makeAdhkar()
        let morning = AdhkarDeckModel(period: .morning, session: session)
        let evening = AdhkarDeckModel(period: .evening, session: session)
        XCTAssertTrue(session.setManualCompletion(.morning, completed: true))
        XCTAssertEqual(morning.cards.indices.filter { !morning.canReach($0) }, [])
        XCTAssertEqual(morning.cards.filter(\.isComplete).map(\.id), [], "rows keep their counters")
        XCTAssertFalse(evening.canReach(1), "the other period keeps its lock")

        let reloaded = AdhkarDeckModel(period: .morning, session: try support.makeAdhkar())
        XCTAssertTrue(reloaded.canReach(reloaded.cards.count - 1), "the saved manual completion")

        XCTAssertTrue(session.setManualCompletion(.morning, completed: false))
        XCTAssertFalse(morning.canReach(1))
    }

    @MainActor
    func testReviewItemsNeverCloseTheIndex() throws {
        let support = try PortableTestSupport()
        var content = support.content
        content.packs.adhkar.morning[1].review = true
        content.adhkar.morning[1].kind = "review"
        let deck = AdhkarDeckModel(period: .morning, session: try support.makeAdhkar(content: content))
        XCTAssertTrue(deck.cards[1].isReview)
        read(deck, 0)
        XCTAssertTrue(deck.canReach(1))
        XCTAssertTrue(deck.canReach(2), "past the review item")
        XCTAssertFalse(deck.canReach(3))
    }

    /// As «التالي» in the ruqyah PWA's `updateDeckNavigation`: a segment opens once the one before it is read.
    @MainActor
    func testRuqyahIndexOpensEachSegmentOnceTheOneBeforeIsRead() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeRuqyah()
        XCTAssertEqual(deck.selectedSectionID, "qaf")
        XCTAssertGreaterThan(deck.cards.count, 2)
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertEqual(deck.cards.filter(\.isComplete).map(\.id), [])
        XCTAssertEqual(deck.cards.indices.filter { deck.canReach($0) }, [0], "every later segment waits for the first")

        read(deck, 0)
        XCTAssertTrue(deck.canReach(1))
        XCTAssertFalse(deck.cards[1].isComplete)
        XCTAssertFalse(deck.canReach(2))

        deck.show(1)
        XCTAssertTrue(deck.canReach(0), "an earlier segment")
        XCTAssertTrue(deck.canReach(1), "the current segment")
        XCTAssertFalse(deck.canMoveForward(from: 1))
        XCTAssertFalse(deck.canReach(2))
        XCTAssertFalse(deck.canReach(-1))
        XCTAssertFalse(deck.canReach(deck.cards.count))
    }

    /// Each sura's chip opens that sura on its first segment, and reading its segments in order through «التالي»
    /// reaches each of them; together the suras reach every segment of the pack, once and in order.
    @MainActor
    func testEverySegmentIsReachedThroughItsSuraChip() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeRuqyah()
        XCTAssertEqual(deck.sections.map(\.id), ["qaf", "jinn", "takwir", "kafirun", "nas"])
        var reached: [String] = []
        for section in deck.sections {
            deck.selectSection(section.id)
            XCTAssertEqual(deck.selectedSectionID, section.id)
            XCTAssertEqual(deck.currentIndex, 0)
            while true {
                let index = deck.currentIndex
                XCTAssertTrue(deck.canReach(index))
                reached.append(deck.cards[index].id)
                read(deck, index)
                XCTAssertEqual(deck.canMoveForward(from: index), index < deck.cards.count - 1)
                guard deck.canMoveForward(from: index) else { break }
                deck.show(index + 1)
            }
            XCTAssertEqual(deck.sections.first { $0.id == section.id }?.isComplete, true)
        }
        XCTAssertEqual(reached, support.content.packs.ruqyahSegments.map(\.id))
    }

    /// With long adhkar last, rows follow the deck order and keep their numbers; reading the cards in that order
    /// opens the next row, whatever its number.
    @MainActor
    func testLongOrderIndexFollowsDeckOrderAndKeepsNumbers() throws {
        let support = try PortableTestSupport()
        let session = try support.makeAdhkar()
        session.applyLongOrder(true, active: .morning)
        let deck = AdhkarDeckModel(period: .morning, session: session)
        let numbers = deck.cards.map(\.number)
        XCTAssertEqual(numbers.sorted(), Array(1...numbers.count))
        let moved = try XCTUnwrap(numbers.indices.first { numbers[$0] != $0 + 1 }, "long-order moved no card")
        XCTAssertEqual(deck.currentIndex, 0)

        for index in 0..<moved { read(deck, index) }
        XCTAssertTrue(deck.canReach(moved))
        XCTAssertFalse(deck.canReach(moved + 1))
        read(deck, moved)
        XCTAssertTrue(deck.canReach(moved + 1), "card \(numbers[moved + 1]) at position \(moved + 2)")
    }

    @MainActor
    func testChoiceLeadsToAReachableCardWhileTheDeckIsUnchanged() throws {
        let support = try PortableTestSupport()
        let deck = AdhkarDeckModel(period: .morning, session: try support.makeAdhkar())
        read(deck, 0)
        read(deck, 1)
        deck.show(1)
        let ids = deck.cards.map(\.id)
        XCTAssertEqual(deck.destination(of: deck.indexChoice(of: ids[0])), 0)
        XCTAssertEqual(deck.destination(of: deck.indexChoice(of: ids[1])), 1)
        XCTAssertEqual(deck.destination(of: deck.indexChoice(of: ids[2])), 2)
        XCTAssertNil(deck.destination(of: deck.indexChoice(of: ids[3])), "behind the unread card 3")
        XCTAssertNil(deck.destination(of: deck.indexChoice(of: "missing")))
    }

    @MainActor
    func testChoiceStaysOnTheCurrentCardAfterADayRollover() throws {
        let support = try PortableTestSupport()
        let session = try support.makeAdhkar()
        let deck = AdhkarDeckModel(period: .morning, session: session)
        read(deck, 0)
        read(deck, 1)
        deck.show(1)
        let choice = deck.indexChoice(of: deck.cards[0].id)
        session.roll(to: nextDay)
        XCTAssertEqual(deck.currentIndex, 0)
        XCTAssertTrue(deck.canReach(0))
        XCTAssertNil(deck.destination(of: choice), "chosen from the earlier day's deck")

        let ruqyah = try support.makeRuqyah()
        XCTAssertNotNil(ruqyah.tap(cardAt: 0))
        ruqyah.show(2)
        let segment = ruqyah.indexChoice(of: ruqyah.cards[0].id)
        ruqyah.roll(to: nextDay)
        XCTAssertNil(ruqyah.destination(of: segment))
    }

    @MainActor
    func testChoiceStaysWhenTheDeckChangedOrTheCardClosed() throws {
        let support = try PortableTestSupport()
        let session = try support.makeAdhkar()
        let deck = AdhkarDeckModel(period: .morning, session: session)
        read(deck, 0)
        let reset = deck.indexChoice(of: deck.cards[1].id)
        deck.resetCard(at: 0)
        XCTAssertNil(deck.destination(of: reset), "counters changed after the choice")

        XCTAssertTrue(session.setManualCompletion(.morning, completed: true))
        let last = deck.cards.count - 1
        let far = deck.indexChoice(of: deck.cards[last].id)
        XCTAssertEqual(deck.destination(of: far), last)
        let reordered = deck.indexChoice(of: deck.cards[last].id)
        session.applyLongOrder(true, active: .morning)
        XCTAssertNil(deck.destination(of: reordered), "the order changed after the choice")

        session.applyLongOrder(false, active: .morning)
        let locked = deck.indexChoice(of: deck.cards[last].id)
        XCTAssertTrue(session.setManualCompletion(.morning, completed: false))
        XCTAssertEqual(deck.cards, locked.cards, "manual completion leaves the rows as they were")
        XCTAssertNil(deck.destination(of: locked), "no longer reachable")
    }

    /// Taps the card until its counter is complete, as a reader would.
    @MainActor
    private func read(_ deck: some DeckModel, _ index: Int, file: StaticString = #filePath, line: UInt = #line) {
        while !deck.cards[index].isComplete {
            guard deck.tap(cardAt: index) != nil else {
                return XCTFail("card \(index + 1) did not count", file: file, line: line)
            }
        }
    }
}
