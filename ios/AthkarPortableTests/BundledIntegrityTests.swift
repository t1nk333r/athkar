import AthkarCore
import Crypto
import Foundation
import GRDB
import XCTest
@testable import AthkarModels

/// The production loader and install recorder over a private copy of the repository's manifest and packs, edited per
/// test. A refusal must be a thrown error, which Release builds keep, and must leave every `content_installs` row as it
/// was, including rows for packs checked before the refused one.
final class BundledIntegrityTests: XCTestCase {
    private let earlier = Date(timeIntervalSince1970: 1_760_000_000)
    private let now = Date(timeIntervalSince1970: 1_760_400_000)

    func testUnchangedPacksLoadAndReplaceOlderInstalls() throws {
        let support = try PortableTestSupport()
        let (database, _) = try olderInstalls()
        try BundledContent.recordInstalls(from: support.bundle, manifest: support.content.manifest, in: database,
                                         now: now)
        let expected = try support.content.manifest.packs.sorted { $0.key < $1.key }.map { packId, pack in
            let url = try XCTUnwrap(support.bundle.url(forResource: pack.file, withExtension: nil))
            let data = try Data(contentsOf: url)
            return ContentInstall(packId: packId, version: pack.version, checksum: checksum(data), installedAt: now)
        }
        XCTAssertEqual(try database.contentInstalls.installs(), expected)
    }

    func testRefusedLaterRowLeavesEarlierInstallsUnchanged() throws {
        let support = try PortableTestSupport()
        let (database, before) = try olderInstalls()
        // The bundle is valid. SQLite refuses the ruqyah row, written after adhkar's, as a full or failing disk would:
        // test-only triggers on this private database. An upsert can reach the row through INSERT or UPDATE.
        try database.writer.write { db in
            for event in ["INSERT", "UPDATE"] {
                try db.execute(sql: """
                    CREATE TRIGGER reject_ruqyah_\(event.lowercased()) BEFORE \(event) ON content_installs
                    WHEN NEW.pack_id = 'ruqyah' BEGIN SELECT RAISE(ABORT, 'test rejects ruqyah'); END
                    """)
            }
        }
        XCTAssertThrowsError(try BundledContent.recordInstalls(from: support.bundle, manifest: support.content.manifest,
                                                               in: database, now: now)) {
            XCTAssertEqual(($0 as? DatabaseError)?.extendedResultCode, .SQLITE_CONSTRAINT_TRIGGER)
        }
        XCTAssertEqual(try database.contentInstalls.installs(), before)
    }

    func testChangedByteIsRefused() throws {
        let fixture = try ContentFixture()
        let pack = try XCTUnwrap(fixture.manifest().packs["adhkar"])
        // One indentation space becomes a tab. The pack still decodes, so only its digest can refuse it.
        var data = try fixture.read(pack.file)
        let space = try XCTUnwrap(data.firstIndex(of: UInt8(ascii: " ")))
        data[space] = UInt8(ascii: "\t")
        try fixture.write(data, to: pack.file)
        try assertRefused(fixture, .checksumMismatch(file: pack.file, expected: pack.sha256, actual: checksum(data)))

        try fixture.redigest("adhkar")
        XCTAssertNoThrow(try BundledContent.load(from: fixture.bundle()))
    }

    func testIncorrectDigestOfALaterPackLeavesEarlierInstallsUnchanged() throws {
        let fixture = try ContentFixture()
        let manifest = try fixture.manifest()
        let adhkar = try XCTUnwrap(manifest.packs["adhkar"])
        let ruqyah = try XCTUnwrap(manifest.packs["ruqyah"])
        // The adhkar pack is checked first and is newer than its installed row; only the ruqyah digest is wrong.
        try fixture.replaceFirst(ruqyah.sha256, with: adhkar.sha256, in: "manifest.json")
        try assertRefused(fixture, .checksumMismatch(file: ruqyah.file, expected: adhkar.sha256,
                                                     actual: ruqyah.sha256))
    }

    func testMissingPackFileIsRefused() throws {
        let fixture = try ContentFixture()
        let file = try XCTUnwrap(fixture.manifest().packs["ruqyah"]).file
        try fixture.remove(file)
        try assertRefused(fixture, .missingResource(name: file))
    }

    func testManifestWithoutARequiredPackIsRefused() throws {
        let fixture = try ContentFixture()
        try fixture.editManifestPacks { $0["ruqyah"] = nil }
        try assertRefused(fixture, .missingPack(id: "ruqyah"))
    }

    func testMissingLaterListedPackLeavesEarlierInstallsUnchanged() throws {
        let fixture = try ContentFixture()
        // The manifest lists the suwar pack, which sorts after the packs the app reads, but the bundle omits its file.
        let suwar = try Data(contentsOf: fixture.repositoryContent("suwar.v1.json"))
        try fixture.editManifestPacks {
            $0["suwar"] = ["file": "suwar.v1.json", "version": "1.0.0", "sha256": checksum(suwar)]
        }
        try assertRefused(fixture, .missingResource(name: "suwar.v1.json"))
    }

    func testMissingManifestIsRefused() throws {
        let fixture = try ContentFixture()
        try fixture.remove("manifest.json")
        let bundle = try fixture.bundle()
        XCTAssertThrowsError(try BundledContent.load(from: bundle)) {
            XCTAssertEqual($0 as? BundledContentError, .missingResource(name: "manifest.json"))
        }
    }

    func testDuplicateIDsAreRefused() throws {
        // Both periods' cards share one table keyed by ID.
        let adhkar = try ContentFixture()
        let adhkarFile = try XCTUnwrap(adhkar.manifest().packs["adhkar"]).file
        try adhkar.replaceFirst(#""id": "evening-01""#, with: #""id": "morning-01""#, in: adhkarFile)
        try adhkar.redigest("adhkar")
        try assertRefused(adhkar, .duplicateID(id: "morning-01"))

        let ruqyah = try ContentFixture()
        let segments = try BundledContent.load(from: ruqyah.bundle()).ruqyah
        let first = try XCTUnwrap(segments.first).id
        let second = try XCTUnwrap(segments.dropFirst().first).id
        let ruqyahFile = try XCTUnwrap(ruqyah.manifest().packs["ruqyah"]).file
        try ruqyah.replaceFirst(#""id": "\#(second)""#, with: #""id": "\#(first)""#, in: ruqyahFile)
        try ruqyah.redigest("ruqyah")
        try assertRefused(ruqyah, .duplicateID(id: first))
    }

    func testNoteIndexOutsideDetailsIsRefused() throws {
        let original = try ContentFixture()
        let morning = try BundledContent.load(from: original.bundle()).adhkar.morning
        let item = try XCTUnwrap(morning.first { $0.noteIndex != nil })
        let noteIndex = try XCTUnwrap(item.noteIndex)
        for invalid in [-1, item.details.count] {
            let fixture = try ContentFixture()
            let file = try XCTUnwrap(fixture.manifest().packs["adhkar"]).file
            try fixture.replaceFirst(#""noteIndex": \#(noteIndex)"#, with: #""noteIndex": \#(invalid)"#, in: file)
            try fixture.redigest("adhkar")
            try assertRefused(fixture, .invalidNoteIndex(id: item.id, noteIndex: invalid))
        }
    }

    /// `load(from:)` and `recordInstalls` both refuse the edited bundle with `expected`, and the older installs, which
    /// an accepted bundle replaces, keep every row as it was.
    private func assertRefused(_ fixture: ContentFixture, _ expected: BundledContentError,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let bundle = try fixture.bundle()
        XCTAssertThrowsError(try BundledContent.load(from: bundle), file: file, line: line) {
            XCTAssertEqual($0 as? BundledContentError, expected, file: file, line: line)
        }
        let manifest = try fixture.manifest()
        let (database, before) = try olderInstalls()
        XCTAssertThrowsError(try BundledContent.recordInstalls(from: bundle, manifest: manifest, in: database,
                                                               now: now), file: file, line: line) {
            XCTAssertEqual($0 as? BundledContentError, expected, file: file, line: line)
        }
        XCTAssertEqual(try database.contentInstalls.installs(), before, file: file, line: line)
    }

    /// Rows from an older install of both packs the app reads, which an accepted bundle replaces.
    private func olderInstalls() throws -> (AppDatabase, [ContentInstall]) {
        let database = try AppDatabase.inMemory()
        for packId in ["adhkar", "ruqyah"] {
            try database.contentInstalls.record(ContentInstall(packId: packId, version: "0.9.0",
                                                               checksum: String(repeating: "0", count: 64),
                                                               installedAt: earlier))
        }
        let installs = try database.contentInstalls.installs()
        XCTAssertEqual(installs.count, 2)
        return (database, installs)
    }
}

private func checksum(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// A private copy of the repository's `content/manifest.json` and the packs it lists, which a test edits before the
/// production loader reads it. Files are removed before `bundle()` is first called, since a bundle may cache its
/// directory listing.
private final class ContentFixture {
    private let directory: URL

    init() throws {
        guard TestHooks.contentDirectory == nil else {
            throw CocoaError(.fileReadInvalidFileName,
                             userInfo: [NSLocalizedDescriptionKey: "Unset ATHKAR_UITEST_CONTENT_DIR for portable tests."])
        }
        let parent = ProcessInfo.processInfo.environment["ATHKAR_TEST_TMP"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        directory = parent.appendingPathComponent("Athkar-integrity-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let manifest = try JSONDecoder().decode(ContentManifest.self,
                                                    from: Data(contentsOf: repositoryContent("manifest.json")))
            for name in ["manifest.json"] + manifest.packs.values.map(\.file) {
                try FileManager.default.copyItem(at: repositoryContent(name), to: url(name))
            }
            let info = ["CFBundleIdentifier": "local.dev.athkar.integritytests", "CFBundlePackageType": "BNDL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: url("Info.plist"))
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func repositoryContent(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("content/\(name)")
    }

    func bundle() throws -> Bundle { try XCTUnwrap(Bundle(url: directory)) }

    func manifest() throws -> ContentManifest {
        try JSONDecoder().decode(ContentManifest.self, from: read("manifest.json"))
    }

    func read(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }

    func write(_ data: Data, to name: String) throws { try data.write(to: url(name)) }

    func remove(_ name: String) throws { try FileManager.default.removeItem(at: url(name)) }

    /// Replaces the first occurrence of `target` in `name`, failing when there is none, so no edit misses silently.
    func replaceFirst(_ target: String, with replacement: String, in name: String) throws {
        let text = try XCTUnwrap(String(data: read(name), encoding: .utf8))
        let range = try XCTUnwrap(text.range(of: target), "\(name) has no \(target)")
        try write(Data(text.replacingCharacters(in: range, with: replacement).utf8), to: name)
    }

    func editManifestPacks(_ edit: (inout [String: Any]) throws -> Void) throws {
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: read("manifest.json")) as? [String: Any])
        var packs = try XCTUnwrap(manifest["packs"] as? [String: Any])
        try edit(&packs)
        manifest["packs"] = packs
        try write(JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]),
                  to: "manifest.json")
    }

    /// Gives `packId` the digest of its edited file, so only a structural check can refuse the edit.
    func redigest(_ packId: String) throws {
        let file = try XCTUnwrap(manifest().packs[packId]).file
        let digest = checksum(try read(file))
        try editManifestPacks { packs in
            var pack = try XCTUnwrap(packs[packId] as? [String: Any])
            pack["sha256"] = digest
            packs[packId] = pack
        }
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }
}
