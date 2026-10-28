import AthkarCore
import Crypto
import Foundation
import XCTest
@testable import AthkarModels

final class PortableModelTests: XCTestCase {
    func testBundledContentRecordsRealChecksumsAndPreservesInstallDate() throws {
        let support = try PortableTestSupport()
        let installs = try support.database.contentInstalls.installs()
        XCTAssertFalse(installs.isEmpty)
        XCTAssertEqual(Set(installs.map(\.packId)), Set(support.content.manifest.packs.keys))
        for install in installs {
            let pack = try XCTUnwrap(support.content.manifest.packs[install.packId])
            let url = try XCTUnwrap(support.bundle.url(forResource: pack.file, withExtension: nil))
            let digest = SHA256.hash(data: try Data(contentsOf: url))
            let checksum = digest.map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(install.version, pack.version)
            XCTAssertEqual(install.checksum, checksum)
            XCTAssertEqual(checksum, pack.sha256)
            XCTAssertEqual(install.installedAt, support.installedAt)
        }
        try BundledContent.recordInstalls(from: support.bundle, manifest: support.content.manifest,
                                         in: support.database, now: support.installedAt.addingTimeInterval(60))
        XCTAssertEqual(try support.database.contentInstalls.installs(), installs)
    }

    @MainActor
    func testAdhkarCountersPersistReloadAndRemainIsolated() throws {
        let first = try PortableTestSupport()
        let second = try PortableTestSupport()
        let session = try first.makeAdhkar()
        let deck = AdhkarDeckModel(period: .morning, session: session)
        XCTAssertEqual(deck.cards.map(\.id), first.content.adhkar.morning.map(\.id))
        let index = try XCTUnwrap(deck.cards.firstIndex { !$0.isReview && $0.target > 1 })
        let itemId = deck.cards[index].id
        XCTAssertNotNil(deck.tap(cardAt: index))
        XCTAssertEqual(deck.cards[index].count, 1)
        XCTAssertEqual(try first.database.adhkar.session(on: first.today, period: .morning).progress[itemId], 1)
        XCTAssertEqual(try first.makeAdhkar().cards.morning.first { $0.id == itemId }?.count, 1)
        XCTAssertEqual(try second.makeAdhkar().cards.morning.first { $0.id == itemId }?.count, 0)
        XCTAssertTrue(try second.database.adhkar.session(on: second.today, period: .morning).progress.isEmpty)
    }

    @MainActor
    func testAdhkarCompletionRequiresFinalTapAndRejectsFurtherTaps() throws {
        let support = try PortableTestSupport()
        let deck = AdhkarDeckModel(period: .morning, session: try support.makeAdhkar())
        let index = try XCTUnwrap(deck.cards.firstIndex { !$0.isReview && (2...5).contains($0.target) })
        let target = deck.cards[index].target
        for count in 1...target {
            let change = try XCTUnwrap(deck.tap(cardAt: index))
            XCTAssertEqual(change.completedCard, count == target)
            XCTAssertEqual(deck.cards[index].count, count)
        }
        XCTAssertTrue(deck.canMoveForward(from: index))
        XCTAssertNil(deck.tap(cardAt: index))
        XCTAssertEqual(try support.database.adhkar.session(on: support.today, period: .morning)
            .progress[deck.cards[index].id], target)
    }

    @MainActor
    func testInvalidIndicesAndReviewCardsDoNotPersistCounters() throws {
        let support = try PortableTestSupport()
        // The shipped pack has no review cards. Change only one in-memory item's review classification.
        var content = support.content
        _ = try XCTUnwrap(content.packs.adhkar.morning.first)
        content.packs.adhkar.morning[0].review = true
        content.adhkar.morning[0].kind = "review"
        let deck = AdhkarDeckModel(period: .morning, session: try support.makeAdhkar(content: content))
        let review = try XCTUnwrap(deck.cards.firstIndex(where: \.isReview))
        XCTAssertNil(deck.tap(cardAt: review))
        XCTAssertNil(deck.tap(cardAt: -1))
        XCTAssertNil(deck.tap(cardAt: deck.cards.count))
        XCTAssertNil(deck.setTarget(-1, forCardAt: 0))
        XCTAssertTrue(try support.database.adhkar.session(on: support.today, period: .morning).progress.isEmpty)
    }

    @MainActor
    func testRuqyahCountersPersistReloadAndRemainIsolated() throws {
        let first = try PortableTestSupport()
        let second = try PortableTestSupport()
        let deck = try first.makeRuqyah()
        // One section per sura, in pack order; together their cards are the pack's segments, each once.
        var ids: [String] = []
        for section in deck.sections {
            deck.selectSection(section.id)
            XCTAssertEqual(deck.cards.map(\.number), Array(1...deck.cards.count), "numbered within \(section.id)")
            ids += deck.cards.map(\.id)
        }
        XCTAssertEqual(ids, first.content.ruqyah.map(\.id))
        deck.selectSection("qaf")
        let index = try XCTUnwrap(deck.cards.firstIndex { $0.target > 1 })
        let itemId = deck.cards[index].id
        XCTAssertNotNil(deck.tap(cardAt: index))
        XCTAssertEqual(deck.cards[index].count, 1)
        XCTAssertEqual(try first.database.ruqyah.counts(on: first.today)[itemId], 1)
        XCTAssertEqual(try first.makeRuqyah().cards.first { $0.id == itemId }?.count, 1)
        XCTAssertEqual(try second.makeRuqyah().cards.first { $0.id == itemId }?.count, 0)
        XCTAssertTrue(try second.database.ruqyah.counts(on: second.today).isEmpty)
    }

    /// Each sura is recorded once its last reading is counted, and the day once every sura is; each completion opens
    /// a dialog, and every completed segment plays the haptic.
    @MainActor
    func testRuqyahRecordsCompletionOnlyAfterEveryRequiredReading() throws {
        let support = try PortableTestSupport()
        let deck = try support.makeRuqyah()
        XCTAssertFalse(deck.sections.isEmpty)
        for (position, section) in deck.sections.enumerated() {
            deck.selectSection(section.id)
            XCTAssertFalse(deck.cards.isEmpty)
            for index in deck.cards.indices {
                let target = deck.cards[index].target
                for count in 1...target {
                    let completesSura = index == deck.cards.count - 1 && count == target
                    let isLastReading = completesSura && position == deck.sections.count - 1
                    let change = try XCTUnwrap(deck.tap(cardAt: index))
                    XCTAssertEqual(change.completedCard, count == target)
                    XCTAssertEqual(change.haptic, count == target)
                    XCTAssertEqual(change.completedDeck, completesSura)
                    XCTAssertEqual(change.advance, count == target && !completesSura)
                    XCTAssertEqual(deck.isComplete, completesSura)
                    XCTAssertEqual(deck.isDayComplete, isLastReading)
                    XCTAssertEqual(try support.database.ruqyah.suraDays(on: support.today)[section.id] != nil,
                                   completesSura)
                    XCTAssertEqual(try support.database.ruqyah.day(on: support.today) != nil, isLastReading)
                }
                XCTAssertNil(deck.tap(cardAt: index))
            }
        }
        let day = try XCTUnwrap(support.database.ruqyah.day(on: support.today))
        XCTAssertEqual(day.completedAt.timeIntervalSince1970,
                       try XCTUnwrap(deck.completedAt).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(Set(try support.database.ruqyah.suraDays(on: support.today).keys),
                       Set(deck.sections.map(\.id)))
        XCTAssertTrue(try support.makeRuqyah().isDayComplete)
    }
}
