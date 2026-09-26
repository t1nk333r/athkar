import AthkarCore
import Foundation
import Observation

/// The prayer-times section (NATIVE_APP_PLAN.md §7.3–7.4): the location profile, the calculation settings, and the
/// schedule of the day on screen. Every choice is written to SQLite at once, the default included, so a later PWA
/// import cannot override it.
@MainActor
@Observable
final class PrayerTimesModel {
    private(set) var location: LocationProfile?
    private(set) var settings: CalculationSettings
    /// Days from today of the schedule on screen.
    private(set) var dayOffset = 0
    private(set) var isLocating = false
    /// Why the last «تحديد الموقع» failed, as shown under the button.
    private(set) var locationProblem: String?

    private let locations: LocationRepository
    private let settingsRepository: SettingsRepository
    private let port: any PrayerTimesPort
    private let report: (any Error) -> Void
    private let deviceLocation = DeviceLocation()

    init(database: AppDatabase, port: any PrayerTimesPort = AdhanPrayerTimes(), report: @escaping (any Error) -> Void)
        throws {
        locations = database.location
        settingsRepository = database.settings
        self.port = port
        self.report = report
        let location = try locations.profile()
        self.location = location
        settings = try settingsRepository.calculationSettings(latitude: location?.latitude)
    }

    // MARK: Schedules

    /// The device's current zone: the only 1.0 behaviour (§7.4).
    var zone: TimeZone { location?.zoneId.flatMap(TimeZone.init(identifier:)) ?? .current }

    /// The schedule `offset` days from today, or `nil` without a location.
    func schedule(dayOffset offset: Int, now: Date = Date()) -> PrayerSchedule? {
        guard let location else { return nil }
        let date = Self.localDate(daysFromToday: offset, now: now, in: zone)
        return try? port.schedule(on: date, at: GeoCoordinates(latitude: location.latitude,
                                                               longitude: location.longitude),
                                  in: zone, settings: settings)
    }

    var shownSchedule: PrayerSchedule? { schedule(dayOffset: dayOffset) }

    /// The countdown's target: today's next prayer, or tomorrow's Fajr.
    func nextPrayer(now: Date = Date()) -> NextPrayer? {
        guard let today = schedule(dayOffset: 0, now: now) else { return nil }
        return NextPrayer.after(now, today: today, tomorrow: schedule(dayOffset: 1, now: now))
    }

    func showDay(_ offset: Int) {
        dayOffset = max(-30, min(30, offset))
    }

    static func localDate(daysFromToday offset: Int, now: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        return SessionCalendar.localDate(of: day, in: zone)
    }

    // MARK: Location

    /// «تحديد الموقع»: one fix, rounded to two decimals, saved as the only profile.
    func locate() async {
        guard !isLocating else { return }
        isLocating = true
        locationProblem = nil
        defer { isLocating = false }
        do {
            let coordinates = try await deviceLocation.currentCoordinates()
            save(LocationProfile(latitude: coordinates.latitude, longitude: coordinates.longitude, source: .device,
                                 updatedAt: Date()))
        } catch {
            locationProblem = switch error {
            case .denied: "لم يُسمح للتطبيق بالوصول إلى الموقع. يمكنك السماح به من الإعدادات، أو إدخال الإحداثيات يدويًا."
            case .restricted: "الوصول إلى الموقع مقيّد على هذا الجهاز. أدخل الإحداثيات يدويًا."
            case .unavailable: "تعذّر تحديد الموقع الآن. حاول مرة أخرى، أو أدخل الإحداثيات يدويًا."
            case .busy, .cancelled: nil
            }
        }
    }

    /// Manual coordinates (§7.4), for users who deny location.
    func setManualLocation(latitude: Double, longitude: Double) {
        locationProblem = nil
        save(LocationProfile(latitude: latitude, longitude: longitude, source: .manual, updatedAt: Date()))
    }

    private func save(_ profile: LocationProfile) {
        do {
            try locations.save(profile)
            location = profile
            // An unset method follows the latitude (Umm al-Qura except beyond 48°).
            settings = try settingsRepository.calculationSettings(latitude: profile.latitude)
        } catch {
            report(error)
        }
    }

    // MARK: Settings

    func setMethod(_ method: CalculationMethod) { write(method, .calculationMethod) { $0.method = method } }
    func setAsrSchool(_ school: AsrSchool) { write(school, .asrSchool) { $0.asrSchool = school } }
    func setHighLatitudeRule(_ rule: HighLatitudeRule) {
        write(rule, .highLatitudeRule) { $0.highLatitudeRule = rule }
    }
    func setAdjustments(_ adjustments: PrayerAdjustments) {
        write(adjustments, .prayerAdjustments) { $0.adjustments = adjustments }
    }
    func setHijriOffset(_ offset: Int) { write(offset, .hijriOffset) { $0.hijriOffset = offset } }

    private func write<Value>(_ value: Value, _ key: SettingKey<Value>, apply: (inout CalculationSettings) -> Void) {
        do {
            try settingsRepository.set(value, for: key)
            apply(&settings)
        } catch {
            report(error)
        }
    }
}
