import Foundation
import GRDB

/// The single location profile of 1.0 (`location_profiles` holds at most one row, `id = 1`).
/// Coordinates are stored rounded to two decimals (≈1 km, NATIVE_APP_PLAN.md §7.4).
public struct LocationProfile: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "location_profiles"

    public enum Source: String, Codable, Sendable, DatabaseValueConvertible {
        case device, manual
        case imported = "import"
    }

    private var id = 1
    public var label: String?
    public private(set) var latitude: Double
    public private(set) var longitude: Double
    /// IANA zone; `nil` means the device's current zone (the only 1.0 behaviour).
    public var zoneId: String?
    public var source: Source
    /// When the coordinates were obtained; `nil` if unknown (a PWA location without `updatedAt`).
    public var updatedAt: Date?

    public init(label: String? = nil, latitude: Double, longitude: Double, zoneId: String? = nil, source: Source,
                updatedAt: Date?) {
        self.label = label
        self.latitude = Self.rounded(latitude)
        self.longitude = Self.rounded(longitude)
        self.zoneId = zoneId
        self.source = source
        self.updatedAt = updatedAt
    }

    /// Two decimals, half away from zero.
    static func rounded(_ coordinate: Double) -> Double {
        (coordinate * 100).rounded() / 100
    }
}

public struct LocationRepository: Sendable {
    let writer: any DatabaseWriter

    public func profile() throws -> LocationProfile? {
        try writer.read { try LocationProfile.fetchOne($0) }
    }

    /// Replaces the profile.
    public func save(_ profile: LocationProfile) throws {
        try writer.write { try profile.upsert($0) }
    }

    public func delete() throws {
        try writer.write { _ = try LocationProfile.deleteAll($0) }
    }
}
