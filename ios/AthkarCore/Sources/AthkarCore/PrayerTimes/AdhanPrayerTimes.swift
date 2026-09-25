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
        let location = Coordinates(latitude: coordinates.latitude, longitude: coordinates.longitude)
        let parameters = Self.parameters(settings)
        func times(utcDay: Int64) -> PrayerTimes? {
            // Adhan returns all six times or none (no sunrise or sunset: polar day or night).
            PrayerTimes(coordinates: location, date: Self.utcComponents(utcDay), calculationParameters: parameters)
        }
        let guess = Self.meanTransitUTCDay(localDay: localDay, longitude: coordinates.longitude, zone: zone)
        var result = times(utcDay: guess)
        // Dhuhr is the true transit (equation of time, the offset in force at that instant, and any Dhuhr
        // adjustment included). If it lands on a neighbouring civil day, move the UTC date back by that difference.
        if let dhuhr = result?.dhuhr, case let dhuhrDay = Self.localDay(of: dhuhr, in: zone), dhuhrDay != localDay {
            result = times(utcDay: guess + localDay - dhuhrDay)
        }
        guard let result else {
            return PrayerSchedule(localDate: localDate, zone: zone, fajr: nil, sunrise: nil, dhuhr: nil, asr: nil,
                                  maghrib: nil, isha: nil)
        }
        // Where the noon Sun barely clears the horizon, Adhan's single correction step can put Asr before Dhuhr or
        // after Maghrib (even after Isha). Asr then ends at Maghrib (spec/prayer-times/README.md, P3).
        let asrInWindow = result.dhuhr < result.asr && result.asr <= result.maghrib
        return PrayerSchedule(localDate: localDate, zone: zone, fajr: result.fajr, sunrise: result.sunrise,
                              dhuhr: result.dhuhr, asr: asrInWindow ? result.asr : result.maghrib,
                              maghrib: result.maghrib, isha: result.isha, asrClamped: !asrInWindow)
    }

    /// Adhan computes the solar day around the transit on a UTC calendar date. First guess: the UTC date whose mean
    /// transit, 12:00 − longitude/15 h UTC, falls on `localDay` in `zone`. Where a zone's offset is about a day away
    /// from its longitude (Pacific/Kiritimati: UTC+14 at 157° W; Pacific/Apia: UTC+13 at 172° W) that is the
    /// previous UTC date. The guess ignores the equation of time (±16 min), so `schedule` checks it against Dhuhr.
    static func meanTransitUTCDay(localDay: Int64, longitude: Double, zone: TimeZone) -> Int64 {
        var transitUTCHours = (12 - longitude / 15).truncatingRemainder(dividingBy: 24)
        if transitUTCHours < 0 { transitUTCHours += 24 }
        // 12:00 UTC, not the transit: `schedule` corrects the rare guess this puts on the wrong side of midnight.
        let offsetSample = Date(timeIntervalSince1970: Double(localDay) * 86_400 + 43_200)
        let transitLocalHours = transitUTCHours + Double(zone.secondsFromGMT(for: offsetSample)) / 3600
        return localDay - Int64((transitLocalHours / 24).rounded(.down))
    }

    /// Days since 1970-01-01 of the civil date of `instant` in `zone`. Adhan's times are whole seconds.
    static func localDay(of instant: Date, in zone: TimeZone) -> Int64 {
        Int64(((instant.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: instant))) / 86_400).rounded(.down))
    }

    static func utcComponents(_ utcDay: Int64) -> DateComponents {
        utcCalendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(utcDay) * 86_400))
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
