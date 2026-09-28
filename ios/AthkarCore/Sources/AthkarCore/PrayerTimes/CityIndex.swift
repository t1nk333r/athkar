import Foundation

/// A place from the bundled city list (`data/cities.tsv`, GeoNames, CC BY 4.0).
public struct City: Equatable, Hashable, Sendable, Identifiable {
    public let id: Int
    /// ISO 3166-1 alpha-2.
    public let country: String
    public let coordinates: GeoCoordinates
    public let population: Int
    /// Arabic names, the preferred one first; empty where GeoNames has none.
    public let arabicNames: [String]
    /// The GeoNames name, then its ASCII form when it differs.
    public let englishNames: [String]

    /// The name to show: Arabic when there is one.
    public var displayName: String { arabicNames.first ?? englishNames.first ?? "" }
}

/// Offline city search for manual location, and the nearest city for a location label. Nothing leaves the device.
/// Matching ignores case, Arabic diacritics and letter variants (أ إ آ ٱ → ا, ة → ه, ى → ي, ؤ → و, ئ → ي), Latin
/// accents and apostrophes, and a leading «ال» in Arabic (so «رياض» finds الرياض).
public struct CityIndex: Sendable {
    public let cities: [City]
    /// Every city's normalised names and their words, as UTF-8 in one buffer, so a search is a pass of `memcmp` and
    /// `memmem` over it: fast enough to run on every keystroke, in debug builds too.
    private let storage: [UInt8]
    private let keys: [Key]

    private struct Key: Sendable {
        var start: Int32
        var length: Int32
        var city: Int32
        /// 0 for a city's preferred name.
        var position: Int16
    }

    public init(cities: [City]) {
        self.cities = cities
        var storage: [UInt8] = []
        var keys: [Key] = []
        for (index, city) in cities.enumerated() {
            var texts: [String] = []
            for name in city.arabicNames + city.englishNames {
                let full = Self.normalise(name)
                guard !full.isEmpty else { continue }
                texts.append(full)
                let words = full.split(separator: " ").map(String.init)
                guard words.count > 1 || full.hasPrefix("ال") else { continue }
                for word in words {
                    if words.count > 1 { texts.append(word) }
                    if word.hasPrefix("ال"), word.count > 3 { texts.append(String(word.dropFirst(2))) }
                }
            }
            for (position, text) in texts.enumerated() {
                keys.append(Key(start: Int32(storage.count), length: Int32(text.utf8.count), city: Int32(index),
                                position: Int16(min(position, Int(Int16.max)))))
                storage.append(contentsOf: text.utf8)
            }
        }
        self.storage = storage
        self.keys = keys
    }

    /// Parses `data/cities.tsv`: `#` comments, then geonameid, country, latitude, longitude, population, Arabic names
    /// and English names (each `|` separated), tab-separated.
    public init(tsv: String) {
        var cities: [City] = []
        cities.reserveCapacity(36_000)
        for line in tsv.split(separator: "\n", omittingEmptySubsequences: true) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 7, let id = Int(fields[0]), let latitude = Double(fields[2]),
                  let longitude = Double(fields[3]) else { continue }
            func names(_ field: Substring) -> [String] {
                field.split(separator: "|").map(String.init).filter { !$0.isEmpty }
            }
            cities.append(City(id: id, country: String(fields[1]),
                               coordinates: GeoCoordinates(latitude: latitude, longitude: longitude),
                               population: Int(fields[4]) ?? 0, arabicNames: names(fields[5]),
                               englishNames: names(fields[6])))
        }
        self.init(cities: cities)
    }

    /// Cities whose name matches `query`: a whole name first, then a name or a word that starts with it, then any that
    /// contain it; within each, larger cities first.
    public func search(_ query: String, limit: Int = 25) -> [City] {
        let normalised = Self.normalise(query)
        let needle = Array(normalised.utf8)
        guard !needle.isEmpty else { return [] }
        let allowContains = normalised.count >= 3
        var best = [Int](repeating: .max, count: cities.count)
        storage.withUnsafeBufferPointer { buffer in
            needle.withUnsafeBufferPointer { needleBuffer in
                guard let base = buffer.baseAddress, let needleBase = needleBuffer.baseAddress else { return }
                let count = needle.count
                for key in keys {
                    let length = Int(key.length)
                    guard length >= count else { continue }
                    let start = base + Int(key.start)
                    let rank: Int
                    if memcmp(start, needleBase, count) == 0 {
                        rank = length == count ? 0 : 1
                    } else if allowContains, memmem(start, length, needleBase, count) != nil {
                        rank = 3
                    } else {
                        continue
                    }
                    // A match on the preferred (first) name ranks above one on an alternate or a word.
                    let score = key.position == 0 ? rank : rank + 1
                    let city = Int(key.city)
                    if score < best[city] { best[city] = score }
                }
            }
        }
        var ranked: [(rank: Int, index: Int)] = []
        for (index, rank) in best.enumerated() where rank != .max { ranked.append((rank, index)) }
        ranked.sort { ($0.rank, cities[$1.index].population, $0.index) < ($1.rank, cities[$0.index].population, $1.index) }
        return ranked.prefix(limit).map { cities[$0.index] }
    }

    /// The city nearest `place`, if one is within `maximumKilometres`.
    public func nearest(to place: GeoCoordinates, maximumKilometres: Double = 40) -> City? {
        var best: (city: City, distance: Double)?
        let latitudeRadians = place.latitude * .pi / 180
        for city in cities {
            // Equirectangular: exact enough at these distances, and cheap over the whole list.
            let x = (city.coordinates.longitude - place.longitude) * cos(latitudeRadians)
            let y = city.coordinates.latitude - place.latitude
            let distance = (x * x + y * y).squareRoot() * 111.195
            if distance <= maximumKilometres, distance < (best?.distance ?? .infinity) { best = (city, distance) }
        }
        return best?.city
    }

    static func normalise(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            let mapped: Unicode.Scalar?
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x0640, 0x06D6...0x06ED: mapped = nil // harakat, superscript alef, tatweel
            case 0x0623, 0x0625, 0x0622, 0x0671: mapped = "ا"
            case 0x0629: mapped = "ه"
            case 0x0649, 0x0626: mapped = "ي"
            case 0x0624: mapped = "و"
            case 0x0027, 0x2018, 0x2019, 0x02BB, 0x02BC, 0x02BF, 0x02BE, 0x0060, 0x00B4: mapped = nil
            case 0x002D, 0x2010, 0x2011, 0x2013, 0x2014, 0x005F, 0x002C, 0x060C, 0x002E: mapped = " "
            default: mapped = scalar
            }
            guard let mapped else { continue }
            if mapped.properties.isWhitespace {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.unicodeScalars.append(mapped)
                lastWasSpace = false
            }
        }
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }
}
