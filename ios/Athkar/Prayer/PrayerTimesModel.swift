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
    /// Minutes from each adhan to its iqama, which the counters count to after the adhan.
    private(set) var iqama: IqamaDelays
    /// Days from today of the schedule on screen.
    private(set) var dayOffset = 0
    private(set) var isLocating = false
    /// Why the last «تحديد الموقع» failed, as shown under the button.
    private(set) var locationProblem: String?

    private let locations: LocationRepository
    private let settingsRepository: SettingsRepository
    private let port: any PrayerTimesPort
    private let widget: any PrayerWidgetPublisher
    private let report: (any Error) -> Void
    private let deviceLocation = DeviceLocation()

    init(database: AppDatabase, port: any PrayerTimesPort = AdhanPrayerTimes(),
         widget: any PrayerWidgetPublisher = KeychainPrayerWidget(), report: @escaping (any Error) -> Void) throws {
        locations = database.location
        settingsRepository = database.settings
        self.port = port
        self.widget = widget
        self.report = report
        let location = try locations.profile()
        self.location = location
        settings = try settingsRepository.calculationSettings(latitude: location?.latitude)
        iqama = try settingsRepository.value(for: .iqamaDelays)
        publishWidget()
    }

    // MARK: Schedules

    /// The device's current zone: the only 1.0 behaviour (§7.4).
    var zone: TimeZone { location?.zoneId.flatMap(TimeZone.init(identifier:)) ?? .current }

    /// The schedule `offset` days from today, or `nil` without a location.
    func schedule(dayOffset offset: Int, now: Date = Date()) -> PrayerSchedule? {
        schedule(on: Self.localDate(daysFromToday: offset, now: now, in: zone))
    }

    /// The schedule of a civil date (`YYYY-MM-DD`) in `zone`, or `nil` without a location.
    func schedule(on localDate: String) -> PrayerSchedule? {
        guard let location else { return nil }
        return try? port.schedule(on: localDate, at: GeoCoordinates(latitude: location.latitude,
                                                                    longitude: location.longitude),
                                  in: zone, settings: settings)
    }

    var shownSchedule: PrayerSchedule? { schedule(dayOffset: dayOffset) }

    /// The countdown's target: today's next prayer, or tomorrow's Fajr.
    func nextPrayer(now: Date = Date()) -> NextPrayer? {
        upcoming(now: now)?.next
    }

    /// The next prayer with its calculation date, taken by civil date so a DST change names the right day
    /// (``NextPrayer/upcoming(after:in:schedule:)``).
    func upcoming(now: Date = Date()) -> UpcomingPrayer? {
        guard location != nil else { return nil }
        return NextPrayer.upcoming(after: now, in: zone) { schedule(on: $0) }
    }

    /// What the counters count to: the iqama of the prayer whose adhan has sounded, then the next adhan
    /// (``PrayerCountdown``).
    func countdown(now: Date = Date()) -> PrayerCountdown? {
        guard location != nil else { return nil }
        return PrayerCountdown.at(now, in: zone, delays: iqama) { schedule(on: $0) }
    }

    func showDay(_ offset: Int) {
        dayOffset = max(-30, min(30, offset))
    }

    /// The lock-screen widget's times (``PrayerWidgetSnapshot``): yesterday's and those of the next
    /// ``PrayerWidgetSnapshot/days`` days, or none without a location. After every change to the location, the
    /// calculation or the iqama, and when the day changes, so the days ahead stay filled.
    func publishWidget(now: Date = Date()) {
        guard location != nil else {
            widget.publish(nil)
            return
        }
        let schedules = (-1..<PrayerWidgetSnapshot.days).compactMap { schedule(dayOffset: $0, now: now) }
        widget.publish(PrayerWidgetSnapshot(zone: zone, schedules: schedules, delays: iqama))
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
        publishWidget()
    }

    // MARK: Settings

    /// After a transfer import (``TransferImportModel``): the calculation settings are read again.
    func reloadSettings() {
        do {
            settings = try settingsRepository.calculationSettings(latitude: location?.latitude)
            iqama = try settingsRepository.value(for: .iqamaDelays)
        } catch {
            report(error)
        }
        publishWidget()
    }

    /// After a backup import or «حذف كل البيانات»: the location, the calculation settings and the iqama delays are
    /// read again.
    func reload() {
        do {
            let location = try locations.profile()
            self.location = location
            settings = try settingsRepository.calculationSettings(latitude: location?.latitude)
            iqama = try settingsRepository.value(for: .iqamaDelays)
            locationProblem = nil
        } catch {
            report(error)
        }
        publishWidget()
    }

    func setMethod(_ method: CalculationMethod) { write(method, .calculationMethod) { $0.method = method } }
    func setAsrSchool(_ school: AsrSchool) { write(school, .asrSchool) { $0.asrSchool = school } }
    func setHighLatitudeRule(_ rule: HighLatitudeRule) {
        write(rule, .highLatitudeRule) { $0.highLatitudeRule = rule }
    }
    func setAdjustments(_ adjustments: PrayerAdjustments) {
        write(adjustments, .prayerAdjustments) { $0.adjustments = adjustments }
    }
    func setHijriOffset(_ offset: Int) { write(offset, .hijriOffset) { $0.hijriOffset = offset } }

    /// One prayer's iqama delay; the five are stored together, so the others are written as they read.
    func setIqama(_ minutes: Int, for prayer: ObligatoryPrayer) {
        var delays = iqama
        delays[prayer] = minutes
        do {
            try settingsRepository.set(delays, for: .iqamaDelays)
            iqama = delays
        } catch {
            report(error)
        }
        publishWidget()
    }

    private func write<Value>(_ value: Value, _ key: SettingKey<Value>, apply: (inout CalculationSettings) -> Void) {
        do {
            try settingsRepository.set(value, for: key)
            apply(&settings)
        } catch {
            report(error)
        }
        publishWidget()
    }
}
