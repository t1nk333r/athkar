import AthkarCore
import Testing

struct QiblaTests {
    /// adhan-swift's QiblaTests cities and directions (accuracy 0.001°).
    @Test(arguments: [
        (38.9072, -77.0369, 56.560), (40.7128, -74.0059, 58.481), (37.7749, -122.4194, 18.843),
        (61.2181, -149.9003, 350.883), (-33.8688, 151.2093, 277.499), (-36.8485, 174.7633, 261.197),
        (51.5074, -0.1278, 118.987), (48.8566, 2.3522, 119.163), (59.9139, 10.7522, 139.027),
        (33.7294, 73.0931, 255.882), (35.6895, 139.6917, 293.021),
    ])
    func matchesAdhan(latitude: Double, longitude: Double, direction: Double) {
        let bearing = Qibla.bearing(from: GeoCoordinates(latitude: latitude, longitude: longitude))
        #expect(abs(bearing - direction) < 0.001, "\(latitude), \(longitude): \(bearing)")
    }

    @Test func riyadhFacesWestAndIsAboutEightHundredKilometresAway() {
        let riyadh = GeoCoordinates(latitude: 24.71, longitude: 46.68)
        let bearing = Qibla.bearing(from: riyadh)
        #expect(bearing > 240 && bearing < 248, "\(bearing)")
        let distance = Qibla.distanceKilometres(from: riyadh)
        #expect(distance > 780 && distance < 800, "\(distance)")
        #expect(Qibla.distanceKilometres(from: Qibla.kaaba) < 0.001)
    }

    @Test func offsetIsSignedAndWrapsAroundNorth() {
        #expect(Qibla.offset(bearing: 10, heading: 350) == 20)
        #expect(Qibla.offset(bearing: 350, heading: 10) == -20)
        #expect(Qibla.offset(bearing: 90, heading: 270) == -180)
        #expect(Qibla.isAligned(bearing: 244, heading: 241.5))
        #expect(!Qibla.isAligned(bearing: 244, heading: 240))
        #expect(Qibla.isAligned(bearing: 1, heading: 359))
    }
}
