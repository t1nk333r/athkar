import AthkarCore
import CryptoKit
import Foundation

/// An adhkar item as the card shows it (`content/adhkar.v1.json`). The fields the rules read come from
/// `ContentPacks`; these are the text and presentation fields around them.
struct AdhkarItemContent: Decodable, Equatable, Sendable {
    var id: String
    var kind: String
    var text: String
    var prefix: String?
    var details: [String]
    var count: Int?
    var countLabel: String?
    var targetOptions: [Int]?
    var noteIndex: Int?

    var isQuran: Bool { kind == "quran" }
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
    var range: String
    var `repeat`: Int
    var basmala: Bool
    var ayahs: [Ayah]
}

/// The packs bundled with the app (NATIVE_APP_PLAN.md §5.4), read from the repository's `content/` at build time.
struct BundledContent: Sendable {
    /// What the session rules read.
    var packs: ContentPacks
    var adhkar: SessionPeriods<[AdhkarItemContent]>
    var ruqyah: [RuqyahSegmentContent]
    var manifest: ContentManifest

    static func load(from bundle: Bundle = .main) throws -> BundledContent {
        let manifest = try JSONDecoder().decode(ContentManifest.self, from: try resource("manifest.json", in: bundle))
        let adhkarData = try resource(try manifest.file(of: "adhkar"), in: bundle)
        let ruqyahData = try resource(try manifest.file(of: "ruqyah"), in: bundle)
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
    /// drawn. Fails at launch, naming the item, rather than at first render.
    func validate() throws {
        for period in Period.allCases {
            let texts = Dictionary(adhkar[period].map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            if let missing = packs.adhkar[period].first(where: { texts[$0.id] == nil }) {
                throw BundledContentError.missingContent(id: missing.id)
            }
        }
        for (index, segment) in packs.ruqyahSegments.enumerated() where ruqyah[safe: index]?.id != segment.id {
            throw BundledContentError.missingContent(id: segment.id)
        }
    }

    /// Records each bundled pack's version in `content_installs` when it differs from the installed one. The checksum
    /// is computed from the bundled file, so the row describes what is actually installed; it must equal the
    /// manifest's, which `tools/content-validate.mjs` guarantees for a release.
    static func recordInstalls(from bundle: Bundle = .main, manifest: ContentManifest, in database: AppDatabase,
                               now: Date = Date()) throws {
        let installed = Dictionary(uniqueKeysWithValues: try database.contentInstalls.installs().map { ($0.packId, $0) })
        for (packId, pack) in manifest.packs.sorted(by: { $0.key < $1.key }) {
            let digest = SHA256.hash(data: try resource(pack.file, in: bundle))
            let checksum = digest.map { String(format: "%02x", $0) }.joined()
            assert(checksum == pack.sha256, "\(pack.file) does not match content/manifest.json")
            if let current = installed[packId], current.version == pack.version, current.checksum == checksum {
                continue
            }
            try database.contentInstalls.record(ContentInstall(packId: packId, version: pack.version,
                                                               checksum: checksum, installedAt: now))
        }
    }

    private static func resource(_ name: String, in bundle: Bundle) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
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

    func file(of packId: String) throws -> String {
        guard let pack = packs[packId] else { throw CocoaError(.fileReadCorruptFile) }
        return pack.file
    }
}

enum BundledContentError: Error, CustomStringConvertible {
    /// A pack lists an item or segment with no card content.
    case missingContent(id: String)

    var description: String {
        switch self {
        case let .missingContent(id): "Bundled content has no card for \(id)"
        }
    }
}
