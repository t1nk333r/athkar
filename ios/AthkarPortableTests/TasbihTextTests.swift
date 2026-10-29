import Foundation
import XCTest
@testable import AthkarModels

/// ``TasbihText`` against `spec/sessions/fixtures/tasbih-text.json`, which records what the athkar PWA's functions
/// return. Strings compare as UTF-16 code units, as JavaScript's `===` compares them.
final class TasbihTextTests: XCTestCase {
    func testEveryFixtureCaseMatchesThePWA() throws {
        let cases = try Self.cases()
        XCTAssertGreaterThan(cases.count, 60)
        var functions: Set<String> = []
        for entry in cases {
            let name = try XCTUnwrap(entry["name"] as? String)
            let input = try XCTUnwrap(entry["input"] as? [String: Any], name)
            let function = try XCTUnwrap(input["function"] as? String, name)
            functions.insert(function)
            let expected = entry["expected"]
            switch function {
            case "tasbihMatchKey":
                try assertSame(TasbihText.matchKey(string(input["text"], name)), expected, name)
            case "cleanTasbihPhrase":
                try assertSame(TasbihText.cleanPhrase(string(input["text"], name)), expected, name)
            case "findTasbihPhrase":
                let custom = try XCTUnwrap(input["custom"] as? [String], name)
                try assertSame(TasbihText.findPhrase(string(input["text"], name), custom: custom), expected, name)
            case "tasbihIdentity":
                try assertSame(TasbihText.identity(string(input["key"], name)), expected, name)
            case "parseTasbihTarget":
                let parsed = try TasbihText.parseTarget(string(input["value"], name))
                let wanted = expected as? Int
                XCTAssertEqual(parsed, wanted, name)
                if wanted == nil { XCTAssertTrue(expected is NSNull, name) }
            case "tasbihStatusText":
                let count = try XCTUnwrap(input["count"] as? Int, name)
                let target = input["target"] as? Int
                let status = TasbihText.status(count: count, target: target)
                let wanted = try XCTUnwrap(expected as? [String: Any], name)
                try assertSame(status.text, wanted["text"], name)
                XCTAssertEqual(status.check, wanted["check"] as? Bool, name)
            default:
                XCTFail("\(name): unknown function \(function)")
            }
        }
        XCTAssertEqual(functions, ["tasbihMatchKey", "cleanTasbihPhrase", "findTasbihPhrase", "tasbihIdentity",
                                   "parseTasbihTarget", "tasbihStatusText"])
    }

    /// `tasbihPresets`, in picker order, and `tasbihPhrase`.
    func testPresetsAndPhrases() {
        XCTAssertEqual(TasbihText.presets.map(\.id), ["subhan", "hamd", "takbir", "tahlil", "istighfar",
                                                     "subhan-bihamdih", "hawqala", "salawat"])
        for preset in TasbihText.presets {
            XCTAssertEqual(TasbihText.findPhrase(preset.label, custom: []), preset.id)
            XCTAssertEqual(TasbihText.findPhrase(preset.short, custom: []), preset.id)
            XCTAssertEqual(TasbihText.stripTashkeel(preset.label), preset.short)
        }
        XCTAssertEqual(TasbihText.phrase("hamd").short, "الحمد لله")
        let saved = TasbihText.phrase("c:يَا رَبّ")
        XCTAssertEqual(saved.label, "يَا رَبّ")
        XCTAssertEqual(saved.short, "يا رب")
        XCTAssertTrue(TasbihText.isCustomKey("c:يا رب"))
        XCTAssertFalse(TasbihText.isCustomKey("subhan"))
    }

    /// A saved phrase may begin with a combining mark, which Swift joins to the key's colon: the key is still read in
    /// code units, and spellings Swift equates by canonical equivalence stay apart.
    func testKeysAreReadInCodeUnits() {
        let key = "c:\u{064E}ب"
        XCTAssertTrue(TasbihText.isCustomKey(key))
        XCTAssertEqual(Array(TasbihText.savedText(of: key).utf16), [0x064E, 0x0628])
        let fathaShadda = "ب\u{064E}\u{0651}"
        let shaddaFatha = "ب\u{0651}\u{064E}"
        XCTAssertEqual(fathaShadda, shaddaFatha)
        XCTAssertFalse(TasbihText.same(fathaShadda, shaddaFatha))
        XCTAssertTrue(TasbihText.same(TasbihText.matchKey(fathaShadda), TasbihText.matchKey(shaddaFatha)))
    }

    /// Where the 60-unit cut would split a surrogate pair, the PWA keeps its first half alone; the native rule drops
    /// it, so no saved phrase holds a lone surrogate (`spec/sessions/tasbih.md`).
    func testTheCutNeverLeavesALoneSurrogate() {
        let text = String(repeating: "ب", count: 59) + "😀"
        XCTAssertEqual(text.utf16.count, 61)
        XCTAssertEqual(TasbihText.cleanPhrase(text), String(repeating: "ب", count: 59))
        let fits = String(repeating: "ب", count: 58) + "😀"
        XCTAssertEqual(TasbihText.cleanPhrase(fits), fits)
    }

    private func assertSame(_ actual: String?, _ expected: Any?, _ name: String,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        if expected is NSNull {
            XCTAssertNil(actual, name, file: file, line: line)
            return
        }
        let wanted = try XCTUnwrap(expected as? String, name, file: file, line: line)
        let got = try XCTUnwrap(actual, name, file: file, line: line)
        XCTAssertEqual(Array(got.utf16), Array(wanted.utf16), "\(name): \(got) ≠ \(wanted)", file: file, line: line)
    }

    private func string(_ value: Any?, _ name: String) throws -> String {
        try XCTUnwrap(value as? String, name)
    }

    private static func cases() throws -> [[String: Any]] {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repo.appendingPathComponent("spec/sessions/fixtures/tasbih-text.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["cases"] as? [[String: Any]])
    }
}
