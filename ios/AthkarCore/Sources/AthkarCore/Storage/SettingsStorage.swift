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

/// The PWA's `prayerCalculationMethods` keys.
public enum CalculationMethod: String, Codable, Sendable, CaseIterable {
    case mwl
    case ummAlQura = "umm-al-qura"
    case egyptian
    case karachi
    case northAmerica = "north-america"
}

/// The PWA's `asrShadowFactors` keys.
public enum AsrSchool: String, Codable, Sendable, CaseIterable {
    case standard, hanafi
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

extension SettingKey where Value == Bool {
    public static var haptics: Self { Self(name: "haptics", defaultValue: true) }
    public static var longOrderPromptAnswered: Self { Self(name: "long_order_prompt_answered", defaultValue: false) }
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

    private static func json<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
