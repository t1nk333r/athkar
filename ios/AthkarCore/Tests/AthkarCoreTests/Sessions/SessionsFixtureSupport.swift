import AthkarCore
import Foundation
import Testing

/// One case of a `spec/sessions/fixtures/*.json` file, with its effective input
/// (`{ ...defaultInput, ...case.input }`).
struct SessionsFixtureCase: Sendable, CustomTestStringConvertible {
    let file: String
    let name: String
    let input: SessionState.StoredValue
    let expected: SessionState.StoredValue

    var testDescription: String { "\(file): \(name)" }

    func input<Value: Decodable>(as type: Value.Type) throws -> Value {
        try SessionsFixtures.decode(type, from: input)
    }

    func expected<Value: Decodable>(as type: Value.Type) throws -> Value {
        try SessionsFixtures.decode(type, from: expected)
    }
}

enum SessionsFixtures {
    /// `<repo>/spec/sessions/fixtures`, found from this file's location
    /// (`<repo>/ios/AthkarCore/Tests/AthkarCoreTests/Sessions/`).
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appending(path: "spec/sessions/fixtures")
    }()

    /// Parses the file as `JSON.parse` would (the fixtures may contain lone surrogate escapes, which
    /// `JSONDecoder` rejects).
    static func cases(_ file: String) throws -> [SessionsFixtureCase] {
        let data = try Data(contentsOf: directory.appending(path: file))
        let root = try SessionState.StoredValue(parsingJSON: String(decoding: data, as: UTF8.self))
        guard case .object(let fixture) = root,
              case .object(let defaultInput)? = fixture["defaultInput"],
              case .array(let cases)? = fixture["cases"]
        else { throw FixtureError.malformed(file, "missing defaultInput or cases") }

        return try cases.map { entry in
            guard case .object(let fields) = entry,
                  case .string(let name)? = fields["name"],
                  case .object(let input)? = fields["input"],
                  let expected = fields["expected"]
            else { throw FixtureError.malformed(file, "case without name, input or expected") }
            return SessionsFixtureCase(
                file: file,
                name: name,
                input: .object(defaultInput.merging(input) { _, caseValue in caseValue }),
                expected: expected
            )
        }
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from value: SessionState.StoredValue) throws -> Value {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
    }

    /// `JSON.parse(JSON.stringify(value))`, as the generator records every expected state: non-finite
    /// numbers become `null`.
    static func plain<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    static func timeZone(_ identifier: String) throws -> TimeZone {
        guard let zone = TimeZone(identifier: identifier) else { throw FixtureError.unknownTimeZone(identifier) }
        return zone
    }

    /// Parses the fixtures' `YYYY-MM-DDTHH:mm:ss.sssZ` instants to exact milliseconds.
    static func instant(_ text: String) throws -> Date {
        let fields = text.split { !$0.isASCII || !$0.isNumber }.compactMap { Int64($0) }
        guard text.hasSuffix("Z"), fields.count == 7 else { throw FixtureError.badInstant(text) }
        let (year, month, day) = (fields[0], fields[1], fields[2])
        // H. Hinnant's days_from_civil.
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let epochDay = era * 146_097 + dayOfEra - 719_468
        let milliseconds = epochDay * 86_400_000 + fields[3] * 3_600_000 + fields[4] * 60_000 + fields[5] * 1000 + fields[6]
        return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    enum FixtureError: Error, CustomStringConvertible {
        case malformed(String, String)
        case unknownTimeZone(String)
        case badInstant(String)

        var description: String {
            switch self {
            case .malformed(let file, let reason): "\(file): \(reason)"
            case .unknownTimeZone(let identifier): "unknown time zone \(identifier)"
            case .badInstant(let text): "not a fixture instant: \(text)"
            }
        }
    }
}
