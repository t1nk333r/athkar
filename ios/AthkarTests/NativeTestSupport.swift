import AthkarCore
import Foundation
@testable import Athkar

/// Real bundled packs and a new migrated SQLite database for each test. Never opens Application Support.
struct NativeTestSupport {
    let database: AppDatabase
    let content: BundledContent
    let bundle: Bundle
    let today: String

    init(bundle: Bundle = .main, today: String = "2026-10-14",
         installedAt: Date = Date(timeIntervalSince1970: 1_760_400_000)) throws {
        // A UI-test override must not turn an app-bundle regression into a fixture-only check.
        guard TestHooks.contentDirectory == nil else {
            throw CocoaError(.fileReadInvalidFileName,
                             userInfo: [NSLocalizedDescriptionKey: "Unset ATHKAR_UITEST_CONTENT_DIR for app-unit tests."])
        }
        self.bundle = bundle
        self.today = today
        database = try AppDatabase.inMemory()
        content = try BundledContent.load(from: bundle)
        try BundledContent.recordInstalls(from: bundle, manifest: content.manifest, in: database, now: installedAt)
    }

    @MainActor
    func makeAppModel() throws -> AppModel {
        try AppModel(database: database, content: content, today: today)
    }
}
