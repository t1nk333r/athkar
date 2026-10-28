import AthkarCore
import CryptoKit
import Foundation
import XCTest
@testable import Athkar

final class TestInfrastructureTests: XCTestCase {
    func testBundledPacksRecordActualChecksumsAndVersions() throws {
        let installedAt = Date(timeIntervalSince1970: 1_760_400_000)
        let support = try NativeTestSupport(installedAt: installedAt)
        let installs = try support.database.contentInstalls.installs()
        XCTAssertFalse(installs.isEmpty)
        XCTAssertEqual(Set(installs.map(\.packId)), Set(support.content.manifest.packs.keys))

        for install in installs {
            let pack = try XCTUnwrap(support.content.manifest.packs[install.packId])
            let url = try XCTUnwrap(support.bundle.url(forResource: pack.file, withExtension: nil))
            let digest = SHA256.hash(data: try Data(contentsOf: url))
            let checksum = digest.map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(install.version, pack.version, install.packId)
            XCTAssertEqual(install.checksum, checksum, install.packId)
            XCTAssertEqual(install.checksum, pack.sha256, install.packId)
            XCTAssertEqual(install.installedAt, installedAt, install.packId)
        }

        // Loading identical shipped bytes again must preserve the original installation timestamp.
        try BundledContent.recordInstalls(from: support.bundle, manifest: support.content.manifest,
                                         in: support.database, now: installedAt.addingTimeInterval(60))
        XCTAssertEqual(try support.database.contentInstalls.installs(), installs)
    }

    @MainActor
    func testAppModelBuildsDecksFromBundledContent() throws {
        let support = try NativeTestSupport()
        let app = try support.makeAppModel()
        XCTAssertNil(app.failure)
        XCTAssertEqual(app.adhkar.state.date, support.today)
        XCTAssertEqual(app.ruqyah.progress.date, support.today)

        for period in Period.allCases {
            let deck = app.deck(period == .morning ? .morning : .evening)
            let expected = support.content.adhkar[period]
            XCTAssertFalse(expected.isEmpty)
            XCTAssertEqual(deck.cards.map(\.id), expected.map(\.id))
            for (card, content) in zip(deck.cards, expected) {
                XCTAssertEqual(card.content, .dhikr(content))
                XCTAssertEqual(card.count, 0)
            }
            XCTAssertFalse(deck.isComplete)
        }
        // The ruqyah deck shows one sura at a time; its sections together are the bundled pack, in order.
        XCTAssertFalse(support.content.ruqyah.isEmpty)
        XCTAssertEqual(app.ruqyah.sections.map(\.id), support.content.ruqyahSuwar.map(\.id))
        XCTAssertEqual(app.ruqyah.selectedSectionID, support.content.ruqyahSuwar.first?.id)
        var cards: [DeckCard] = []
        for section in app.ruqyah.sections {
            app.ruqyah.selectSection(section.id)
            cards += app.ruqyah.cards
            XCTAssertFalse(app.ruqyah.isComplete)
        }
        XCTAssertEqual(cards.map(\.id), support.content.ruqyah.map(\.id))
        for (card, content) in zip(cards, support.content.ruqyah) {
            XCTAssertEqual(card.content, .ruqyah(content))
            XCTAssertEqual(card.count, 0)
        }
        XCTAssertFalse(app.ruqyah.isDayComplete)
    }

    @MainActor
    func testInMemoryModelsPersistWithoutSharingDatabaseState() throws {
        let first = try NativeTestSupport()
        let second = try NativeTestSupport()
        let app = try first.makeAppModel()
        let index = try XCTUnwrap(app.morning.cards.firstIndex { !$0.isReview && $0.target > 1 })
        let itemId = app.morning.cards[index].id
        app.settings.theme = .dark
        XCTAssertNotNil(app.morning.tap(cardAt: index))
        XCTAssertNil(app.failure)
        XCTAssertEqual(app.morning.cards[index].count, 1)
        XCTAssertEqual(try first.database.settings.value(for: .theme), .dark)
        XCTAssertEqual(try first.database.adhkar.session(on: first.today, period: .morning).progress[itemId], 1)

        let reloaded = try first.makeAppModel()
        XCTAssertEqual(reloaded.settings.theme, .dark)
        XCTAssertEqual(try XCTUnwrap(reloaded.morning.cards.first { $0.id == itemId }).count, 1)

        let isolated = try second.makeAppModel()
        XCTAssertEqual(isolated.settings.theme, .system)
        XCTAssertEqual(try XCTUnwrap(isolated.morning.cards.first { $0.id == itemId }).count, 0)
        XCTAssertTrue(try second.database.adhkar.session(on: second.today, period: .morning).progress.isEmpty)
        XCTAssertEqual(try second.database.settings.value(for: .theme), .system)
    }
}
