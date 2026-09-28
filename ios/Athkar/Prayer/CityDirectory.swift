import AthkarCore
import Foundation
import Observation

/// The bundled city list (`cities.tsv`), loaded once off the main thread when a screen first needs it.
@MainActor
@Observable
final class CityDirectory {
    static let shared = CityDirectory()

    private(set) var index: CityIndex?
    @ObservationIgnored private var loading: Task<CityIndex?, Never>?

    func load() async {
        if index != nil { return }
        let task = loading ?? Task.detached(priority: .userInitiated) { () -> CityIndex? in
            guard let url = Bundle.main.url(forResource: "cities", withExtension: "tsv"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return CityIndex(tsv: text)
        }
        loading = task
        index = await task.value
    }

    /// «الرياض، السعودية» for the city nearest the location, once the list is loaded.
    func nearestName(_ location: LocationProfile) -> String? {
        let place = GeoCoordinates(latitude: location.latitude, longitude: location.longitude)
        return index?.nearest(to: place).map(Self.label)
    }

    /// «الرياض، السعودية».
    static func label(_ city: City) -> String {
        let country = Locale(identifier: "ar").localizedString(forRegionCode: city.country) ?? city.country
        return "\(city.displayName)، \(country)"
    }
}
