import AthkarCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// An adhkar item as the card shows it (`content/adhkar.v1.json`). The fields the rules read come from
/// `ContentPacks`; these are the text and presentation fields around them.
struct AdhkarItemContent: Decodable, Equatable, Sendable {
    var id: String
    var kind: String
    /// For Quran items: `alquran-cloud:quran-uthmani` (mushaf text, set in KFGQPC HAFS) or `simplified-rasm`.
    var edition: String?
    var text: String
    var prefix: String?
    var details: [String]
    var count: Int?
    var countLabel: String?
    var targetOptions: [Int]?
    var noteIndex: Int?
    /// A review item's card shows these instead of the text and footer (`cardMarkup` for `item.review`).
    var reviewTitle: String?
    var reviewCopy: String?

    var isQuran: Bool { kind == "quran" }
    /// Mushaf (Uthmani) text goes through `MushafEncoding.kfgqpc` into KFGQPC HAFS; a Quran item kept in the simplified
    /// (imla'i) text is set in Uthman Taha as written, since HAFS would draw its final ي undotted.
    var isMushafText: Bool { isQuran && edition != "simplified-rasm" }
    var isReview: Bool { kind == "review" }
    /// `isExplicitlyCounted(item)`: shows `count/target` rather than «اضغط بعد القراءة».
    var isCounted: Bool { (count ?? 0) != 0 || targetOptions != nil }

    /// Details shown on the card: all of them, or those before `noteIndex` when the rest open in a sheet.
    var visibleDetails: ArraySlice<String> {
        guard let noteIndex, noteIndex < details.count else { return details[...] }
        return details[..<noteIndex]
    }

    /// Whether the card has «المصدر والتفاصيل» (`hasExtendedDetails`).
    var hasExtendedDetails: Bool { noteIndex.map { $0 < details.count } ?? false }
}

/// A ruqyah segment as its page shows it (`content/ruqyah.v1.json`).
struct RuqyahSegmentContent: Decodable, Equatable, Sendable {
    struct Ayah: Decodable, Equatable, Sendable {
        var number: Int
        var text: String
    }

    var id: String
    var surah: String
    var surahNumber: Int
    var range: String
    var `repeat`: Int
    var basmala: Bool
    var ayahs: [Ayah]

    /// The sura the segment belongs to: its ID up to the first «-» (`qaf-1-8` → `qaf`).
    var suraID: String { String(id.prefix { $0 != "-" }) }
}

/// One sura of the ruqyah, as the ruqyah PWA groups the pack (`RUQYAH_SUWAR`, `ruqyahContentJs` in
/// `tools/content-lib.mjs`): its segments are consecutive in the pack and share their sura's name.
struct RuqyahSura: Equatable, Sendable {
    /// `qaf`, `jinn`, `takwir`, `kafirun`, `nas`: the deep-link and storage key.
    var id: String
    /// «سورة ق».
    var surah: String
    /// The segments' positions in the pack (``BundledContent/ruqyah`` and `packs.ruqyahSegments`).
    var segments: Range<Int>

    /// The chip's name, without «سورة » (`suraShortName`).
    var shortName: String { surah.hasPrefix("سورة ") ? String(surah.dropFirst(5)) : surah }
}

/// The packs bundled with the app (NATIVE_APP_PLAN.md §5.4), read from the repository's `content/` at build time.
struct BundledContent: Sendable {
    /// What the session rules read.
    var packs: ContentPacks
    var adhkar: SessionPeriods<[AdhkarItemContent]>
    var ruqyah: [RuqyahSegmentContent]
    var manifest: ContentManifest

    /// The ruqyah's suras in pack order.
    var ruqyahSuwar: [RuqyahSura] {
        var suwar: [RuqyahSura] = []
        for (index, segment) in ruqyah.enumerated() {
            if let last = suwar.last, last.id == segment.suraID {
                suwar[suwar.count - 1].segments = last.segments.lowerBound..<(index + 1)
            } else {
                suwar.append(RuqyahSura(id: segment.suraID, surah: segment.surah, segments: index..<(index + 1)))
            }
        }
        return suwar
    }

    static func load(from bundle: Bundle = .main) throws -> BundledContent {
        let manifest = try JSONDecoder().decode(ContentManifest.self, from: try resource("manifest.json", in: bundle))
        return try verified(manifest, in: bundle)
    }

    /// Checks every pack `manifest` lists against its SHA-256, then decodes and validates the packs the app reads.
    /// Each check throws, so a Release build refuses an inconsistent bundle as a Debug build does, before any pack is
    /// used or recorded.
    private static func verified(_ manifest: ContentManifest, in bundle: Bundle) throws -> BundledContent {
        var files: [String: Data] = [:]
        for (packId, pack) in manifest.packs.sorted(by: { $0.key < $1.key }) {
            let data = try resource(pack.file, in: bundle)
            let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard checksum == pack.sha256 else {
                throw BundledContentError.checksumMismatch(file: pack.file, expected: pack.sha256, actual: checksum)
            }
            files[packId] = data
        }
        guard let adhkarData = files["adhkar"] else { throw BundledContentError.missingPack(id: "adhkar") }
        guard let ruqyahData = files["ruqyah"] else { throw BundledContentError.missingPack(id: "ruqyah") }
        let adhkar = try JSONDecoder().decode(AdhkarPack.self, from: adhkarData)
        let ruqyah = try JSONDecoder().decode(RuqyahPack.self, from: ruqyahData)
        let content = BundledContent(
            packs: try ContentPacks(adhkarPack: adhkarData, ruqyahPack: ruqyahData),
            adhkar: SessionPeriods(morning: adhkar.periods.morning, evening: adhkar.periods.evening),
            ruqyah: ruqyah.segments,
            manifest: manifest)
        try content.validate()
        return content
    }

    /// Every item and segment the rules deal in has its card content, in the same order, so a card can always be
    /// drawn. IDs are unique across both packs and every `noteIndex` is the index of one of its item's details, as
    /// `tools/content-validate.mjs` requires. Fails at launch, naming the item, rather than at first render.
    func validate() throws {
        var ids = Set<String>()
        for id in (adhkar.morning + adhkar.evening).map(\.id) + ruqyah.map(\.id) {
            guard ids.insert(id).inserted else { throw BundledContentError.duplicateID(id: id) }
        }
        for item in adhkar.morning + adhkar.evening {
            if let noteIndex = item.noteIndex, !item.details.indices.contains(noteIndex) {
                throw BundledContentError.invalidNoteIndex(id: item.id, noteIndex: noteIndex)
            }
        }
        for period in Period.allCases {
            let texts = Dictionary(adhkar[period].map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            if let missing = packs.adhkar[period].first(where: { texts[$0.id] == nil }) {
                throw BundledContentError.missingContent(id: missing.id)
            }
        }
        for (index, segment) in packs.ruqyahSegments.enumerated() where ruqyah[safe: index]?.id != segment.id {
            throw BundledContentError.missingContent(id: segment.id)
        }
        // As `ruqyahContentJs`: every segment ID names its sura, whose segments are consecutive and share one name
        // and number, so the per-sura decks cover the pack exactly once.
        var suraIDs = Set<String>()
        for sura in ruqyahSuwar {
            let segments = ruqyah[sura.segments]
            guard !sura.id.isEmpty, sura.id.count < segments.first!.id.count, suraIDs.insert(sura.id).inserted,
                  segments.allSatisfy({ $0.surah == sura.surah && $0.surahNumber == segments.first!.surahNumber })
            else { throw BundledContentError.invalidSura(id: segments.first!.id) }
        }
    }

    /// Records each bundled pack's version in `content_installs` when it differs from the installed one. Every pack
    /// is first verified as `load(from:)` verifies it, and the changed rows are written in one transaction, so a
    /// refused bundle or row leaves every row as it was. A recorded checksum is the manifest's SHA-256, which the
    /// bundled file was just found to have.
    static func recordInstalls(from bundle: Bundle = .main, manifest: ContentManifest, in database: AppDatabase,
                               now: Date = Date()) throws {
        _ = try verified(manifest, in: bundle)
        let installed = Dictionary(uniqueKeysWithValues: try database.contentInstalls.installs().map { ($0.packId, $0) })
        var changed: [ContentInstall] = []
        for (packId, pack) in manifest.packs.sorted(by: { $0.key < $1.key }) {
            if let current = installed[packId], current.version == pack.version, current.checksum == pack.sha256 {
                continue
            }
            changed.append(ContentInstall(packId: packId, version: pack.version, checksum: pack.sha256,
                                          installedAt: now))
        }
        guard !changed.isEmpty else { return }
        try database.contentInstalls.record(changed)
    }

    private static func resource(_ name: String, in bundle: Bundle) throws -> Data {
        if let directory = TestHooks.contentDirectory {
            return try Data(contentsOf: directory.appendingPathComponent(name))
        }
        guard let url = bundle.url(forResource: name, withExtension: nil) else {
            throw BundledContentError.missingResource(name: name)
        }
        return try Data(contentsOf: url)
    }

    private struct AdhkarPack: Decodable {
        struct Periods: Decodable {
            var morning: [AdhkarItemContent]
            var evening: [AdhkarItemContent]
        }

        var periods: Periods
    }

    private struct RuqyahPack: Decodable {
        var segments: [RuqyahSegmentContent]
    }
}

/// `content/manifest.json`.
struct ContentManifest: Decodable, Sendable {
    struct Pack: Decodable, Sendable {
        var file: String
        var version: String
        var sha256: String
    }

    var packs: [String: Pack]
}

/// The launch failure view shows `localizedDescription`, which is `description`: it names the pack, file or item.
enum BundledContentError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// A pack lists an item or segment with no card content.
    case missingContent(id: String)
    /// The bundle has no file of this name.
    case missingResource(name: String)
    /// `manifest.json` does not list a pack the app reads.
    case missingPack(id: String)
    /// A pack's bytes do not have the SHA-256 that `manifest.json` gives for them.
    case checksumMismatch(file: String, expected: String, actual: String)
    /// Two items or segments share an ID, which progress and counts are keyed by.
    case duplicateID(id: String)
    /// An item's `noteIndex` is not the index of one of its details.
    case invalidNoteIndex(id: String, noteIndex: Int)
    /// A ruqyah segment's ID names no sura, or its sura's segments are not consecutive or disagree on its name.
    case invalidSura(id: String)

    var description: String {
        switch self {
        case let .missingContent(id): "Bundled content has no card for \(id)"
        case let .missingResource(name): "Bundled content has no \(name)"
        case let .missingPack(id): "content/manifest.json lists no \(id) pack"
        case let .checksumMismatch(file, expected, actual):
            "\(file) has SHA-256 \(actual), not \(expected) as content/manifest.json gives"
        case let .duplicateID(id): "Bundled content has more than one item or segment with the ID \(id)"
        case let .invalidNoteIndex(id, noteIndex): "\(id) has noteIndex \(noteIndex), outside its details"
        case let .invalidSura(id): "Ruqyah segment \(id) does not continue one sura of the pack"
        }
    }

    var errorDescription: String? { description }
}
