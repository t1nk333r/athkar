import Foundation

/// A ruqyah segment as the rules need it: its ID and how many times it is read (`repeat`).
public struct RuqyahSegment: Sendable, Hashable {
    public var id: String
    public var repeatCount: Int

    public init(id: String, repeatCount: Int) {
        self.id = id
        self.repeatCount = repeatCount
    }
}

/// The parts of the bundled content packs (`content/adhkar.v1.json`, `content/ruqyah.v1.json`) that the
/// domain rules read. Text, sources and review metadata are the UI's business.
public struct ContentPacks: Sendable {
    /// Adhkar items per period, in content order.
    public var adhkar: SessionCollections
    /// Ruqyah segments in reading order.
    public var ruqyahSegments: [RuqyahSegment]

    public init(adhkar: SessionCollections, ruqyahSegments: [RuqyahSegment]) {
        self.adhkar = adhkar
        self.ruqyahSegments = ruqyahSegments
    }

    /// Decodes both packs from their JSON files.
    public init(adhkarPack: Data, ruqyahPack: Data) throws {
        self.init(adhkar: try Self.adhkar(from: adhkarPack), ruqyahSegments: try Self.ruqyahSegments(from: ruqyahPack))
    }

    /// `content/adhkar.v1.json` → items with `id`, `count`, `targetOptions`, `defaultTarget`, and
    /// `review = (kind == "review")`.
    public static func adhkar(from data: Data) throws -> SessionCollections {
        try checkPack(data, is: "adhkar")
        let pack = try JSONDecoder().decode(AdhkarPack.self, from: data)
        return SessionCollections(morning: pack.periods.morning.map(\.sessionItem),
                                  evening: pack.periods.evening.map(\.sessionItem))
    }

    /// `content/ruqyah.v1.json` → segments with `id` and `repeat`, in pack order.
    public static func ruqyahSegments(from data: Data) throws -> [RuqyahSegment] {
        try checkPack(data, is: "ruqyah")
        let pack = try JSONDecoder().decode(RuqyahPack.self, from: data)
        return pack.segments.map { RuqyahSegment(id: $0.id, repeatCount: $0.repeat) }
    }

    /// Reads the `pack` field first, so passing the wrong file reports as such rather than as a shape error.
    private static func checkPack(_ data: Data, is expected: String) throws {
        struct Probe: Decodable { var pack: String }
        let found = try JSONDecoder().decode(Probe.self, from: data).pack
        guard found == expected else { throw ContentPackError.wrongPack(expected: expected, found: found) }
    }

    private struct AdhkarPack: Decodable {
        struct Item: Decodable {
            var id: String
            var kind: String
            var count: Int?
            var targetOptions: [Int]?
            var defaultTarget: Int?

            var sessionItem: SessionItem {
                SessionItem(id: id, count: count, targetOptions: targetOptions, defaultTarget: defaultTarget,
                            review: kind == "review")
            }
        }

        struct Periods: Decodable {
            var morning: [Item]
            var evening: [Item]
        }

        var periods: Periods
    }

    private struct RuqyahPack: Decodable {
        struct Segment: Decodable {
            var id: String
            var `repeat`: Int
        }

        var segments: [Segment]
    }
}

public enum ContentPackError: Error, Equatable, Sendable {
    /// The file's `pack` field names a different pack.
    case wrongPack(expected: String, found: String)
}
