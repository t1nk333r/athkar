import Foundation
import GRDB

/// The installed version of a bundled content pack (NATIVE_APP_PLAN.md §5.4).
public struct ContentInstall: Equatable, Sendable, StoredRecord {
    public static let databaseTableName = "content_installs"

    public var packId: String
    public var version: String
    /// Lowercase hex SHA-256 of the pack file, as in `content/manifest.json`.
    public var checksum: String
    public var installedAt: Date

    public init(packId: String, version: String, checksum: String, installedAt: Date) {
        self.packId = packId
        self.version = version
        self.checksum = checksum
        self.installedAt = installedAt
    }
}

public struct ContentInstallRepository: Sendable {
    let writer: any DatabaseWriter

    public func installs() throws -> [ContentInstall] {
        try writer.read { try ContentInstall.order(Column("pack_id")).fetchAll($0) }
    }

    /// Records `install` as the current version of its pack.
    public func record(_ install: ContentInstall) throws {
        try writer.write { try install.upsert($0) }
    }
}
