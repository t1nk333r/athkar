import Foundation

/// The direction of the Kaaba from a place: the initial great-circle bearing from true north, clockwise, and the
/// great-circle distance. Same formula and Kaaba coordinates as adhan-swift's `Qibla` (which only
/// `AdhanPrayerTimes.swift` may import), checked against its test cities.
public enum Qibla {
    public static let kaaba = GeoCoordinates(latitude: 21.4225241, longitude: 39.8261818)
    /// Mean Earth radius (IUGG), for the distance only.
    static let earthRadiusKilometres = 6371.0088

    /// Degrees from true north, clockwise, in `0..<360`.
    public static func bearing(from place: GeoCoordinates) -> Double {
        let φ1 = radians(place.latitude), φ2 = radians(kaaba.latitude)
        let Δλ = radians(kaaba.longitude - place.longitude)
        let θ = atan2(sin(Δλ), cos(φ1) * tan(φ2) - sin(φ1) * cos(Δλ))
        return normalised(degrees(θ))
    }

    /// Great-circle distance to the Kaaba (haversine).
    public static func distanceKilometres(from place: GeoCoordinates) -> Double {
        let φ1 = radians(place.latitude), φ2 = radians(kaaba.latitude)
        let Δφ = φ2 - φ1, Δλ = radians(kaaba.longitude - place.longitude)
        let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * earthRadiusKilometres * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Where the Qibla is relative to where the device points (`heading`, degrees from north): in `-180..<180`,
    /// negative to the left, positive to the right.
    public static func offset(bearing: Double, heading: Double) -> Double {
        let difference = normalised(bearing - heading)
        return difference >= 180 ? difference - 360 : difference
    }

    /// Facing the Qibla: within `tolerance` degrees either side.
    public static func isAligned(bearing: Double, heading: Double, tolerance: Double = 3) -> Bool {
        abs(offset(bearing: bearing, heading: heading)) <= tolerance
    }

    static func normalised(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
