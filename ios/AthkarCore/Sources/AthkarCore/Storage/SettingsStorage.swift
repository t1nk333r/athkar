import Foundation
import GRDB

public enum Theme: String, Codable, Sendable, CaseIterable {
    case system, light, dark
}

public enum TextSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large
}

public enum LineSpacing: String, Codable, Sendable, CaseIterable {
    case compact, comfortable, wide
}

/// Deck order for long adhkar (the PWA's `athkar-long-order-v1`).
public enum LongOrder: String, Codable, Sendable, CaseIterable {
    case last, original
}

/// A typed `settings` key. `defaultValue` is what readers get when no row exists; it is never written.
public struct SettingKey<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value

    public init(name: String, defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

// Defaults are the PWAs' effective values when nothing is stored.
extension SettingKey where Value == Theme {
    public static var theme: Self { Self(name: "theme", defaultValue: .system) }
}

extension SettingKey where Value == TextSize {
    public static var textSize: Self { Self(name: "text_size", defaultValue: .medium) }
}

extension SettingKey where Value == LineSpacing {
    public static var lineSpacing: Self { Self(name: "line_spacing", defaultValue: .comfortable) }
}

extension SettingKey where Value == LongOrder {
    public static var longOrder: Self { Self(name: "long_order", defaultValue: .original) }
}

extension SettingKey where Value == CalculationMethod {
    public static var calculationMethod: Self { Self(name: "calculation_method", defaultValue: .mwl) }
}

extension SettingKey where Value == AsrSchool {
    public static var asrSchool: Self { Self(name: "asr_school", defaultValue: .standard) }
}

extension SettingKey where Value == HighLatitudeRule {
    /// The PWA's fixed Fajr clamp, and the closest rule to it in P1 (spec/prayer-times/README.md).
    public static var highLatitudeRule: Self { Self(name: "high_latitude_rule", defaultValue: .twilightAngle) }
}

extension SettingKey where Value == PrayerAdjustments {
    public static var prayerAdjustments: Self { Self(name: "prayer_adjustments", defaultValue: PrayerAdjustments()) }
}

extension SettingKey where Value == Int {
    public static var hijriOffset: Self { Self(name: "hijri_offset", defaultValue: 0) }
    /// The «مسبحة» target (`athkar-tasbih-v1.target`): 1…9999, or 0 for «بلا هدف» (the PWA's `null`). A preference:
    /// resets keep it.
    public static var tasbihTarget: Self { Self(name: "tasbih_target", defaultValue: 33) }
}

extension SettingKey where Value == Bool {
    public static var haptics: Self { Self(name: "haptics", defaultValue: true) }
    public static var longOrderPromptAnswered: Self { Self(name: "long_order_prompt_answered", defaultValue: false) }
    /// The home header shows the prayer row (current prayer, Hijri date, next prayer) instead of the title.
    public static var homePrayerRow: Self { Self(name: "home_prayer_row", defaultValue: true) }
}

extension SettingKey where Value == String {
    /// The «سور» sura shown (`athkar-suwar-v1.selected`). A preference: resets keep it.
    public static var suwarSelectedSura: Self { Self(name: "suwar_selected_sura", defaultValue: "kahf") }
    /// The «مسبحة» phrase counted (`athkar-tasbih-v1.selected`): a preset ID, or `c:` and a saved phrase. A
    /// preference: resets keep it.
    public static var tasbihSelected: Self { Self(name: "tasbih_selected", defaultValue: "subhan") }
}

extension SettingKey where Value == [String] {
    /// The «مسبحة» saved phrases (`athkar-tasbih-v1.custom`), newest first, at most eight. A preference: resets keep
    /// them.
    public static var tasbihCustomPhrases: Self { Self(name: "tasbih_custom_phrases", defaultValue: []) }
}

/// Who wrote a `settings` row. Import precedence: native > athkar-pwa > ruqyah-pwa; ties keep the existing row.
enum SettingOrigin: String, Codable, Sendable, DatabaseValueConvertible {
    case native
    case athkarPWA = "athkar-pwa"
    case ruqyahPWA = "ruqyah-pwa"

    var precedence: Int {
        switch self {
        case .native: 2
        case .athkarPWA: 1
        case .ruqyahPWA: 0
        }
    }
}

struct Setting: Equatable, StoredRecord {
    static let databaseTableName = "settings"

    var key: String
    var valueJson: String
    var origin: SettingOrigin
    var updatedAt: Date
}

public struct SettingsRepository: Sendable {
    let writer: any DatabaseWriter

    /// The stored value, or `key.defaultValue` when there is no row.
    public func value<Value>(for key: SettingKey<Value>) throws -> Value {
        try writer.read { try Self.value(in: $0, for: key) } ?? key.defaultValue
    }

    /// Writes a value chosen in the app. Native rows are never overwritten by an import.
    public func set<Value>(_ value: Value, for key: SettingKey<Value>, at now: Date = Date()) throws {
        let json = try Self.json(value)
        try writer.write { db in
            try Setting(key: key.name, valueJson: json, origin: .native, updatedAt: now).upsert(db)
        }
    }

    /// Writes the answer to the one-time long-order question: the chosen order and the answered flag commit in one
    /// transaction, or neither row changes.
    public func setLongOrderDecision(_ value: LongOrder, at now: Date = Date()) throws {
        let order = try Self.json(value)
        let answered = try Self.json(true)
        try writer.write { db in
            try Setting(key: SettingKey<LongOrder>.longOrder.name, valueJson: order, origin: .native,
                        updatedAt: now).upsert(db)
            try Setting(key: SettingKey<Bool>.longOrderPromptAnswered.name, valueJson: answered, origin: .native,
                        updatedAt: now).upsert(db)
        }
    }

    public func removeValue<Value>(for key: SettingKey<Value>) throws {
        try writer.write { _ = try Setting.deleteOne($0, key: key.name) }
    }

    static func value<Value>(in db: Database, for key: SettingKey<Value>) throws -> Value? {
        guard let row = try Setting.fetchOne(db, key: key.name) else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(row.valueJson.utf8))
    }

    /// Writes an imported value unless the existing row's origin takes precedence (or ties).
    static func importValue<Value>(_ value: Value, for key: SettingKey<Value>, in db: Database,
                                   origin: SettingOrigin, updatedAt: Date) throws {
        if let existing = try Setting.fetchOne(db, key: key.name), existing.origin.precedence >= origin.precedence {
            return
        }
        try Setting(key: key.name, valueJson: try json(value), origin: origin, updatedAt: updatedAt).upsert(db)
    }

    static func json<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
