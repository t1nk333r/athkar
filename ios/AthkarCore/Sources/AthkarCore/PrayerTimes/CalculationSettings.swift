import Foundation
import GRDB

/// Calculation methods (NATIVE_APP_PLAN.md §7.3). The PWA's `prayerCalculationMethods` keys come first and are
/// surfaced first; the rest are the adhan-swift presets the PWA does not offer. Parameters per method, including
/// Isha, are listed in spec/prayer-times/README.md.
public enum CalculationMethod: String, Codable, Sendable, CaseIterable {
    case mwl
    case ummAlQura = "umm-al-qura"
    case egyptian
    case karachi
    case northAmerica = "north-america"
    case dubai
    case moonsightingCommittee = "moonsighting-committee"
    case kuwait
    case qatar
    case singapore
    case tehran
    case turkey

    /// The methods the PWA offers; backup envelope v1 carries only these.
    public var isPWAMethod: Bool {
        switch self {
        case .mwl, .ummAlQura, .egyptian, .karachi, .northAmerica: true
        case .dubai, .moonsightingCommittee, .kuwait, .qatar, .singapore, .tehran, .turkey: false
        }
    }
}

/// The PWA's `asrShadowFactors` keys: shadow factor 1 (standard) or 2 (hanafi).
public enum AsrSchool: String, Codable, Sendable, CaseIterable {
    case standard, hanafi
}

/// How Fajr and Isha are bounded when twilight is long or never ends: Fajr is never earlier than sunrise minus a
/// portion of the night, Isha never later than sunset plus a portion (adhan-swift's three rules).
public enum HighLatitudeRule: String, Codable, Sendable, CaseIterable {
    /// Portion 1/2.
    case middleOfTheNight = "middle-of-the-night"
    /// Portion 1/7.
    case seventhOfTheNight = "seventh-of-the-night"
    /// Portion angle/60: the PWA's fixed Fajr clamp (spec/prayer-times/README.md).
    case twilightAngle = "twilight-angle"
}

/// Whole minutes added to each computed time; negative is earlier.
public struct PrayerAdjustments: Codable, Equatable, Sendable {
    public var fajr: Int
    public var sunrise: Int
    public var dhuhr: Int
    public var asr: Int
    public var maghrib: Int
    public var isha: Int

    public init(fajr: Int = 0, sunrise: Int = 0, dhuhr: Int = 0, asr: Int = 0, maghrib: Int = 0, isha: Int = 0) {
        self.fajr = fajr
        self.sunrise = sunrise
        self.dhuhr = dhuhr
        self.asr = asr
        self.maghrib = maghrib
        self.isha = isha
    }
}

/// The calculation profile (§7.3). Each field is its own `settings` key (spec/schema.md), so a PWA import that
/// carries only `calculation_method` and `asr_school` leaves the others alone.
public struct CalculationSettings: Codable, Equatable, Sendable {
    public var method: CalculationMethod
    public var asrSchool: AsrSchool
    public var highLatitudeRule: HighLatitudeRule
    public var adjustments: PrayerAdjustments
    /// Days added to the computed Hijri date. Display only; prayer times ignore it.
    public var hijriOffset: Int

    /// Defaults are the settings keys' defaults: the PWA's behaviour.
    public init(method: CalculationMethod = SettingKey.calculationMethod.defaultValue,
                asrSchool: AsrSchool = SettingKey.asrSchool.defaultValue,
                highLatitudeRule: HighLatitudeRule = SettingKey.highLatitudeRule.defaultValue,
                adjustments: PrayerAdjustments = SettingKey.prayerAdjustments.defaultValue,
                hijriOffset: Int = SettingKey.hijriOffset.defaultValue) {
        self.method = method
        self.asrSchool = asrSchool
        self.highLatitudeRule = highLatitudeRule
        self.adjustments = adjustments
        self.hijriOffset = hijriOffset
    }
}

extension SettingsRepository {
    /// The stored profile, with each key's default where no row exists.
    public func calculationSettings() throws -> CalculationSettings {
        try writer.read { db in
            func value<Value>(_ key: SettingKey<Value>) throws -> Value {
                try Self.value(in: db, for: key) ?? key.defaultValue
            }
            return CalculationSettings(method: try value(.calculationMethod), asrSchool: try value(.asrSchool),
                                       highLatitudeRule: try value(.highLatitudeRule),
                                       adjustments: try value(.prayerAdjustments),
                                       hijriOffset: try value(.hijriOffset))
        }
    }

    /// Writes, in one transaction, only the fields that differ from what `calculationSettings()` returns, so an
    /// untouched field never gains a `native` row that would shadow a later import.
    public func setCalculationSettings(_ settings: CalculationSettings, at now: Date = Date()) throws {
        try writer.write { db in
            func write<Value: Equatable>(_ value: Value, for key: SettingKey<Value>) throws {
                guard value != (try Self.value(in: db, for: key) ?? key.defaultValue) else { return }
                try Setting(key: key.name, valueJson: try Self.json(value), origin: .native, updatedAt: now).upsert(db)
            }
            try write(settings.method, for: .calculationMethod)
            try write(settings.asrSchool, for: .asrSchool)
            try write(settings.highLatitudeRule, for: .highLatitudeRule)
            try write(settings.adjustments, for: .prayerAdjustments)
            try write(settings.hijriOffset, for: .hijriOffset)
        }
    }
}
