import Adhan
import Foundation

/// The production `PrayerTimesPort`, backed by adhan-swift (version pinned in Package.swift). This is the only file
/// that imports Adhan. Configuration choices and the parity results behind them: spec/prayer-times/README.md.
public struct AdhanPrayerTimes: PrayerTimesPort {
    public init() {}

    public func schedule(on localDate: String, at coordinates: GeoCoordinates, in zone: TimeZone,
                         settings: CalculationSettings) throws(PrayerTimesError) -> PrayerSchedule {
        guard (-90...90).contains(coordinates.latitude), (-180...180).contains(coordinates.longitude) else {
            throw .invalidCoordinates(coordinates)
        }
        guard let localDay = LocalDate.days(fromDateBytes: ArraySlice(localDate.utf8)) else {
            throw .invalidLocalDate(localDate)
        }
        // Adhan returns all six times or none (no sunrise or sunset: polar day or night).
        let times = PrayerTimes(
            coordinates: Coordinates(latitude: coordinates.latitude, longitude: coordinates.longitude),
            date: Self.solarDate(localDay: localDay, longitude: coordinates.longitude, zone: zone),
            calculationParameters: Self.parameters(settings))
        return PrayerSchedule(localDate: localDate, zone: zone, fajr: times?.fajr, sunrise: times?.sunrise,
                              dhuhr: times?.dhuhr, asr: times?.asr, maghrib: times?.maghrib, isha: times?.isha)
    }

    /// Adhan computes the solar day around the transit on a UTC calendar date, at about 12:00 − longitude/15 h UTC.
    /// Where a zone's offset is about a day away from its longitude (Pacific/Kiritimati: UTC+14 at 157° W;
    /// Pacific/Apia: UTC+13 at 172° W), that transit falls on the next civil day, so pick the UTC date whose transit
    /// falls on `localDay` in `zone`.
    static func solarDate(localDay: Int64, longitude: Double, zone: TimeZone) -> DateComponents {
        var transitUTCHours = (12 - longitude / 15).truncatingRemainder(dividingBy: 24)
        if transitUTCHours < 0 { transitUTCHours += 24 }
        let noon = Date(timeIntervalSince1970: Double(localDay) * 86_400 + 43_200)
        let transitLocalHours = transitUTCHours + Double(zone.secondsFromGMT(for: noon)) / 3600
        let utcDay = localDay - Int64((transitLocalHours / 24).rounded(.down))
        return utcCalendar.dateComponents([.year, .month, .day],
                                          from: Date(timeIntervalSince1970: Double(utcDay) * 86_400))
    }

    static func parameters(_ settings: CalculationSettings) -> CalculationParameters {
        var parameters = settings.method.adhan.params
        parameters.madhab = settings.asrSchool == .hanafi ? .hanafi : .shafi
        parameters.highLatitudeRule = settings.highLatitudeRule.adhan
        let minutes = settings.adjustments
        parameters.adjustments = Adhan.PrayerAdjustments(fajr: minutes.fajr, sunrise: minutes.sunrise,
                                                         dhuhr: minutes.dhuhr, asr: minutes.asr,
                                                         maghrib: minutes.maghrib, isha: minutes.isha)
        // `.nearest` is Adhan's default for every preset rather than part of a method. The port returns the
        // instant to the second, as the PWA did; display rounding is the view's. A preset that asks for `.up`
        // (Singapore) keeps it.
        if parameters.rounding == .nearest { parameters.rounding = .none }
        return parameters
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}

private extension CalculationMethod {
    var adhan: Adhan.CalculationMethod {
        switch self {
        case .mwl: .muslimWorldLeague
        case .ummAlQura: .ummAlQura
        case .egyptian: .egyptian
        case .karachi: .karachi
        case .northAmerica: .northAmerica
        case .dubai: .dubai
        case .moonsightingCommittee: .moonsightingCommittee
        case .kuwait: .kuwait
        case .qatar: .qatar
        case .singapore: .singapore
        case .tehran: .tehran
        case .turkey: .turkey
        }
    }
}

private extension HighLatitudeRule {
    var adhan: Adhan.HighLatitudeRule {
        switch self {
        case .middleOfTheNight: .middleOfTheNight
        case .seventhOfTheNight: .seventhOfTheNight
        case .twilightAngle: .twilightAngle
        }
    }
}
