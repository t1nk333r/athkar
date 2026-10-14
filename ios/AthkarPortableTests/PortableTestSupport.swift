import AthkarCore
import Foundation
import XCTest
@testable import AthkarModels

/// The production loader reads a private bundle containing the repository's exact pack bytes.
final class PortableTestSupport {
    let database: AppDatabase
    let content: BundledContent
    let bundle: Bundle
    let today = "2026-10-14"
    let installedAt = Date(timeIntervalSince1970: 1_760_400_000)
    private let directory: URL

    init() throws {
        guard TestHooks.contentDirectory == nil else {
            throw CocoaError(.fileReadInvalidFileName,
                             userInfo: [NSLocalizedDescriptionKey: "Unset ATHKAR_UITEST_CONTENT_DIR for portable tests."])
        }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let parent = ProcessInfo.processInfo.environment["ATHKAR_TEST_TMP"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        directory = parent.appendingPathComponent("Athkar-content-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let manifestURL = repo.appendingPathComponent("content/manifest.json")
            let manifest = try JSONDecoder().decode(ContentManifest.self, from: Data(contentsOf: manifestURL))
            for name in ["manifest.json"] + manifest.packs.values.map(\.file) {
                try FileManager.default.copyItem(at: repo.appendingPathComponent("content/\(name)"),
                                                to: directory.appendingPathComponent(name))
            }
            let info = ["CFBundleIdentifier": "local.dev.athkar.portabletests", "CFBundlePackageType": "BNDL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: directory.appendingPathComponent("Info.plist"))
            bundle = try XCTUnwrap(Bundle(url: directory))
            content = try BundledContent.load(from: bundle)
            database = try AppDatabase.inMemory()
            try BundledContent.recordInstalls(from: bundle, manifest: content.manifest,
                                             in: database, now: installedAt)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    @MainActor
    func makeAdhkar(content override: BundledContent? = nil) throws -> AdhkarSessionModel {
        try AdhkarSessionModel(database: database, content: override ?? content, longAdhkarLast: false, today: today,
                              report: { XCTFail("Production database write failed: \($0)") })
    }

    @MainActor
    func makeRuqyah() throws -> RuqyahDeckModel {
        try RuqyahDeckModel(database: database, content: content, today: today,
                            report: { XCTFail("Production database write failed: \($0)") })
    }
}
