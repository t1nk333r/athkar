import AthkarCore
import Foundation
import Testing

struct CityIndexTests {
    /// `<repo>/data/cities.tsv`, the list the app bundles.
    static let index: CityIndex = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        let text = (try? String(contentsOf: url.appending(path: "data/cities.tsv"), encoding: .utf8)) ?? ""
        return CityIndex(tsv: text)
    }()

    @Test func loadsTheWholeList() {
        #expect(Self.index.cities.count > 30_000)
    }

    @Test(arguments: [
        ("الرياض", 108410), ("رياض", 108410), ("riyadh", 108410), ("Riyadh ", 108410),
        ("مكة", 104515), ("مكه", 104515), ("جده", 105343), ("jeddah", 105343),
        ("المدينة المنورة", 109223), ("hail", 106281), ("Ha’il", 106281), ("القاهره", 360630),
    ])
    func findsTheCityFirst(query: String, geonameid: Int) {
        let first = Self.index.search(query).first
        #expect(first?.id == geonameid, "\(query) → \(first?.displayName ?? "nothing")")
    }

    @Test func emptyAndUnknownQueriesFindNothing() {
        #expect(Self.index.search("  ").isEmpty)
        #expect(Self.index.search("qqzzxx").isEmpty)
    }

    @Test func nearestCityLabelsALocation() {
        #expect(Self.index.nearest(to: GeoCoordinates(latitude: 24.71, longitude: 46.68))?.id == 108410)
        #expect(Self.index.nearest(to: GeoCoordinates(latitude: 0, longitude: -140)) == nil, "mid-Pacific")
    }

    @Test func searchIsFastEnoughToRunOnEveryKeystroke() {
        let index = Self.index // built outside the timing
        let start = Date()
        for query in ["ا", "ال", "الر", "الري", "الريا", "الرياض", "d", "du", "dub", "duba", "dubai"] {
            _ = index.search(query)
        }
        let perSearch = Date().timeIntervalSince(start) / 11
        #expect(perSearch < 0.1, "\(Int(perSearch * 1000)) ms per search (debug build)")
    }
}
