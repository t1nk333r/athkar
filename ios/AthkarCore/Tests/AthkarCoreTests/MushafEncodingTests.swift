import AthkarCore
import Foundation
import Testing

struct MushafEncodingTests {
    /// Converted, every ruqyah ayah is the King Fahd Complex's text scalar for scalar.
    @Test func ruqyahAyahsMatchTheComplexText() throws {
        let reference = try Self.object("content/reference/kfgqpc-hafs.ruqyah.json")
        let expected = try #require(reference["ayahs"] as? [String: String])
        let segments = try #require(try Self.object("content/ruqyah.v1.json")["segments"] as? [[String: Any]])

        var checked = 0
        for segment in segments {
            let surah = try #require(segment["surahNumber"] as? Int)
            for ayah in try #require(segment["ayahs"] as? [[String: Any]]) {
                let key = "\(surah):\(try #require(ayah["number"] as? Int))"
                let converted = MushafEncoding.kfgqpc(try #require(ayah["text"] as? String))
                #expect(Array(converted.unicodeScalars) == Array(try #require(expected[key]).unicodeScalars), "\(key)")
                checked += 1
            }
        }
        #expect(checked == 114)
    }

    @Test func basmalaMatchesTheComplexText() throws {
        let reference = try #require(try Self.object("content/reference/kfgqpc-hafs.ruqyah.json")["basmala"] as? String)
        let converted = MushafEncoding.kfgqpc("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
        #expect(Array(converted.unicodeScalars) == Array(reference.unicodeScalars))
    }

    @Test func rules() {
        func scalars(_ text: String) -> [UInt32] { text.unicodeScalars.map(\.value) }
        // Sukun and rounded zero trade places.
        #expect(scalars(MushafEncoding.kfgqpc("\u{0644}\u{0652}\u{0627}\u{06DF}")) == [0x0644, 0x06E1, 0x0627, 0x0652])
        // Open tanween and iqlab.
        #expect(scalars(MushafEncoding.kfgqpc("\u{064C}\u{06ED}\u{064D}\u{06E2}\u{064B}\u{06E2}")) == [0x08F1, 0x08F2, 0x064E, 0x06E2])
        // فِى → فِي; عَلَى and ذِكۡرَىٰ keep ى; شَىۡءٍ → شَيۡءٍ.
        #expect(scalars(MushafEncoding.kfgqpc("\u{0650}\u{0649}")) == [0x0650, 0x064A])
        #expect(scalars(MushafEncoding.kfgqpc("\u{064E}\u{0649} ")) == [0x064E, 0x0649, 0x0020])
        #expect(scalars(MushafEncoding.kfgqpc("\u{064E}\u{0649}\u{0670}")) == [0x064E, 0x0649, 0x0670])
        #expect(scalars(MushafEncoding.kfgqpc("\u{064E}\u{0649}\u{0652}")) == [0x064E, 0x064A, 0x06E1])
        // A waqf sign joins its word.
        #expect(scalars(MushafEncoding.kfgqpc("\u{0645} \u{06DA} \u{0648}")) == [0x0645, 0x06DA, 0x0020, 0x0648])
    }

    private static func object(_ path: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: RepoFile.data(path)) as? [String: Any])
    }
}
