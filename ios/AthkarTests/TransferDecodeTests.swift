import AthkarCore
import Foundation
import XCTest

/// The transfer code decoded on iOS, where zlib goes through Apple's Compression framework rather than the portable
/// inflater the Linux suites run: every `spec/transfer/fixtures/codec.json` case reads as the PWA reads it, bombs
/// included.
final class TransferDecodeTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func fixture() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.repo.appendingPathComponent("spec/transfer/fixtures/codec.json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEveryCodecCaseDecodesAsThePWA() throws {
        let cases = try XCTUnwrap(try fixture()["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 58)
        for entry in cases {
            let name = try XCTUnwrap(entry["name"] as? String)
            let input = try XCTUnwrap(entry["input"] as? [String: Any])
            let expected = try XCTUnwrap(entry["result"] as? [String: Any])
            let result: Result<TransferContainer, TransferError>
            if let code = input["code"] as? String {
                result = TransferCodec.decode(text: code)
            } else if let frames = input["frames"] as? [String] {
                result = TransferCodec.decode(frames: frames)
            } else {
                result = TransferCodec.decode(fileText: try XCTUnwrap(input["file"] as? String))
            }
            switch result {
            case let .success(container):
                XCTAssertEqual(expected["ok"] as? Bool, true, name)
                XCTAssertEqual(container.source.rawValue, expected["source"] as? String, name)
            case let .failure(error):
                XCTAssertEqual(expected["ok"] as? Bool, false, name)
                XCTAssertEqual(error.kind.rawValue, expected["error"] as? String, name)
                XCTAssertEqual(error.reason, expected["reason"] as? String, name)
                XCTAssertEqual(error.path, expected["path"] as? String, name)
            }
        }
    }

    /// The typical code's container: its date and counts survive Compression.
    func testTheTypicalCodeKeepsItsProgress() throws {
        let cases = try XCTUnwrap(try fixture()["cases"] as? [[String: Any]])
        let first = try XCTUnwrap(cases.first?["input"] as? [String: Any])
        let container = try TransferCodec.decode(text: try XCTUnwrap(first["code"] as? String)).get()
        XCTAssertEqual(container.date, "2026-10-04")
        XCTAssertEqual(container.envelope.adhkar?.today.progress.morning["morning-01"], 1)
        XCTAssertEqual(container.athkar?.tasbih.counts.first?.count, 33)
        XCTAssertNil(container.envelope.reminders?.location)
    }
}
