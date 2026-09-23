extension SessionState {
    /// A JSON value exactly as the PWA stored it inside `progress`/`targets`.
    ///
    /// `athkar-progress-v2` is lenient: counters can be strings, negatives or fractions, and the rules
    /// coerce them with JavaScript's `Number()` on every read. Keeping the raw value (instead of an `Int`)
    /// lets ``numberValue`` reproduce that coercion and keeps imported state untouched.
    public enum StoredValue: Sendable, Hashable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([StoredValue])
        case object([String: StoredValue])
    }
}

// MARK: - JavaScript semantics

extension SessionState.StoredValue {
    /// JavaScript `Number(value)`.
    ///
    /// Objects convert to `NaN` (their string form is `"[object Object]"`). In JavaScript, a parsed object
    /// with an own `toString` key makes `Number()` throw instead; that path is not reproduced.
    public var numberValue: Double {
        switch self {
        case .null: 0
        case .bool(let value): value ? 1 : 0
        case .number(let value): value
        case .string(let text): Self.number(fromJavaScriptString: text)
        case .array(let elements): Self.number(ofArray: elements)
        case .object: .nan
        }
    }

    /// JavaScript truthiness (`Boolean(value)`).
    var isTruthy: Bool {
        switch self {
        case .null: false
        case .bool(let value): value
        case .number(let value): !(value == 0 || value.isNaN)
        case .string(let text): !text.isEmpty
        case .array, .object: true
        }
    }

    /// JavaScript property access `value[key]` on a parsed JSON value: an object's own member; an array's
    /// element at a canonical index (`"0"`, `"1"`, … but not `"01"`) or its `length`; otherwise `nil`
    /// (`undefined`). Inherited members (`toString`, …) are not modelled: every rule reads them as it reads
    /// `undefined` (`Number()` gives NaN, and none is a string).
    func property(_ key: String) -> Self? {
        switch self {
        case .object(let members): members[key]
        case .array(let elements): Self.arrayProperty(elements, key)
        default: nil
        }
    }

    static func arrayProperty(_ elements: [Self], _ key: String) -> Self? {
        if key == "length" { return .number(Double(elements.count)) }
        guard let index = arrayIndex(key), index < elements.count else { return nil }
        return elements[index]
    }

    /// ECMAScript array index: the canonical decimal form of an integer below 2³² − 1.
    static func arrayIndex(_ key: String) -> Int? {
        let digits = key.utf8
        guard let first = digits.first, digits.count <= 10, first != UInt8(ascii: "0") || digits.count == 1,
              digits.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
              let value = Int(key), value < 4_294_967_295
        else { return nil }
        return value
    }

    var stringValue: String? {
        if case .string(let text) = self { text } else { nil }
    }

    /// `Number(array)` is `Number(array.join(","))`: empty → `""` → 0; two or more elements contain a comma → NaN;
    /// one element → that element's string form converted back (numbers round-trip, `null` → `""` → 0).
    private static func number(ofArray elements: [Self]) -> Double {
        guard elements.count == 1, let element = elements.first else { return elements.isEmpty ? 0 : .nan }
        switch element {
        case .null: return 0
        case .bool, .object: return .nan
        case .number(let value): return value == 0 ? 0 : value
        case .string(let text): return number(fromJavaScriptString: text)
        case .array(let inner): return number(ofArray: inner)
        }
    }

    /// ECMAScript `StringToNumber`: trims JS whitespace; `""` is 0; accepts `Infinity`, signed decimal literals
    /// and unsigned `0x`/`0o`/`0b` integers; anything else is NaN.
    static func number(fromJavaScriptString text: String) -> Double {
        let scalars = text.unicodeScalars
        var lower = scalars.startIndex
        var upper = scalars.endIndex
        while lower < upper, isJavaScriptWhitespace(scalars[lower]) { lower = scalars.index(after: lower) }
        while lower < upper {
            let previous = scalars.index(before: upper)
            guard isJavaScriptWhitespace(scalars[previous]) else { break }
            upper = previous
        }
        var literal: [UInt8] = []
        for scalar in scalars[lower..<upper] {
            guard scalar.isASCII else { return .nan }
            literal.append(UInt8(scalar.value))
        }
        if literal.isEmpty { return 0 }
        if let value = nonDecimalInteger(literal) { return value }
        return decimal(literal)
    }

    private static func isJavaScriptWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0xFEFF, 0x2028, 0x2029: true
        default: scalar.properties.generalCategory == .spaceSeparator
        }
    }

    /// `0x…`, `0o…`, `0b…` (no sign). Returns nil when the literal has no such prefix.
    private static func nonDecimalInteger(_ literal: [UInt8]) -> Double? {
        guard literal.count >= 2, literal[0] == UInt8(ascii: "0") else { return nil }
        let bitsPerDigit: Int
        switch literal[1] | 0x20 {
        case UInt8(ascii: "x"): bitsPerDigit = 4
        case UInt8(ascii: "o"): bitsPerDigit = 3
        case UInt8(ascii: "b"): bitsPerDigit = 1
        default: return nil
        }
        let digits = literal.dropFirst(2)
        guard !digits.isEmpty else { return .nan }
        var values: [UInt8] = []
        values.reserveCapacity(digits.count)
        for byte in digits {
            guard let value = hexDigitValue(byte), value < (1 << bitsPerDigit) else { return .nan }
            values.append(value)
        }
        // Re-express the exact integer in hexadecimal so the platform parser rounds it correctly.
        var hex = "0x"
        if bitsPerDigit == 4 {
            hex.unicodeScalars.append(contentsOf: digits.map { Unicode.Scalar($0) })
        } else {
            var bits: [UInt8] = []
            for value in values {
                for shift in stride(from: bitsPerDigit - 1, through: 0, by: -1) { bits.append((value >> shift) & 1) }
            }
            let padding = (4 - bits.count % 4) % 4
            bits.insert(contentsOf: repeatElement(0, count: padding), at: 0)
            let alphabet = Array("0123456789abcdef".unicodeScalars)
            for start in stride(from: 0, to: bits.count, by: 4) {
                let nibble = bits[start] << 3 | bits[start + 1] << 2 | bits[start + 2] << 1 | bits[start + 3]
                hex.unicodeScalars.append(alphabet[Int(nibble)])
            }
        }
        return Double(hex) ?? .nan
    }

    private static func hexDigitValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    /// `StrDecimalLiteral`: `[+-]? (Infinity | digits [. digits?] [exp] | . digits [exp])`.
    private static func decimal(_ literal: [UInt8]) -> Double {
        var index = 0
        var negative = false
        if literal[index] == UInt8(ascii: "+") || literal[index] == UInt8(ascii: "-") {
            negative = literal[index] == UInt8(ascii: "-")
            index += 1
        }
        if literal[index...].elementsEqual("Infinity".utf8) { return negative ? -.infinity : .infinity }

        func digits() -> ArraySlice<UInt8> {
            let start = index
            while index < literal.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(literal[index]) { index += 1 }
            return literal[start..<index]
        }
        let integer = digits()
        var fraction: ArraySlice<UInt8> = []
        if index < literal.count, literal[index] == UInt8(ascii: ".") {
            index += 1
            fraction = digits()
        }
        guard !integer.isEmpty || !fraction.isEmpty else { return .nan }
        var exponentNegative = false
        var exponent: ArraySlice<UInt8> = []
        if index < literal.count, literal[index] | 0x20 == UInt8(ascii: "e") {
            index += 1
            if index < literal.count, literal[index] == UInt8(ascii: "+") || literal[index] == UInt8(ascii: "-") {
                exponentNegative = literal[index] == UInt8(ascii: "-")
                index += 1
            }
            exponent = digits()
            guard !exponent.isEmpty else { return .nan }
        }
        guard index == literal.count else { return .nan }

        // Canonical form the platform parser always accepts; it rounds to nearest like JavaScript.
        var canonical = negative ? "-" : ""
        canonical += integer.isEmpty ? "0" : String(decoding: integer, as: UTF8.self)
        canonical += "."
        canonical += fraction.isEmpty ? "0" : String(decoding: fraction, as: UTF8.self)
        canonical += exponentNegative ? "e-" : "e"
        canonical += exponent.isEmpty ? "0" : String(decoding: exponent, as: UTF8.self)
        return Double(canonical) ?? .nan
    }
}

// MARK: - JSON.parse

extension SessionState.StoredValue {
    /// Rejection by ``init(parsingJSON:)``, where `JSON.parse` would throw a `SyntaxError`.
    public struct SyntaxError: Error, Sendable, Equatable, CustomStringConvertible {
        /// UTF-8 byte offset of the offending input.
        public let offset: Int
        public let reason: String

        public var description: String { "JSON syntax error at byte \(offset): \(reason)" }
    }

    /// Deepest nesting of arrays and objects accepted by ``init(parsingJSON:)``.
    public static let maximumNestingDepth = 64

    /// Parses `text` as JavaScript's `JSON.parse` does (RFC 8259 grammar; no byte-order mark, comments or
    /// trailing commas). Numbers beyond the `Double` range become ±infinity (`1e400`), duplicate keys keep
    /// the last value.
    ///
    /// Two differences are unavoidable in Swift:
    /// - A lone surrogate escape (`"\ud800"`) cannot live in a Swift `String`; it becomes U+FFFD. Escaped
    ///   surrogate pairs combine as usual.
    /// - Nesting deeper than ``maximumNestingDepth`` is rejected (`JSON.parse` has no limit). Every operation on
    ///   a value (parsing, `==`, `Codable`, release) recurses once per level, and `JSONEncoder` overflows a
    ///   512 KB thread stack at 256 levels in debug builds. `athkar-progress-v2` nests three levels deep.
    public init(parsingJSON text: String) throws(SyntaxError) {
        var parser = JSONTextParser(bytes: Array(text.utf8))
        self = try parser.document()
    }
}

private struct JSONTextParser {
    typealias Value = SessionState.StoredValue

    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func document() throws(Value.SyntaxError) -> Value {
        skipWhitespace()
        let result = try value(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw failure("unexpected text after the value") }
        return result
    }

    private mutating func value(depth: Int) throws(Value.SyntaxError) -> Value {
        guard index < bytes.count else { throw failure("unexpected end of input") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try object(depth: depth + 1)
        case UInt8(ascii: "["): return try array(depth: depth + 1)
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try number())
        default: throw failure("unexpected character")
        }
    }

    private mutating func object(depth: Int) throws(Value.SyntaxError) -> Value {
        guard depth <= Value.maximumNestingDepth else { throw failure("nesting too deep") }
        index += 1
        var members: [String: Value] = [:]
        skipWhitespace()
        if consume(UInt8(ascii: "}")) { return .object(members) }
        while true {
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw failure("expected a key") }
            let key = try string()
            skipWhitespace()
            guard consume(UInt8(ascii: ":")) else { throw failure("expected ':'") }
            skipWhitespace()
            members[key] = try value(depth: depth)
            skipWhitespace()
            if consume(UInt8(ascii: "}")) { return .object(members) }
            guard consume(UInt8(ascii: ",")) else { throw failure("expected ',' or '}'") }
            skipWhitespace()
        }
    }

    private mutating func array(depth: Int) throws(Value.SyntaxError) -> Value {
        guard depth <= Value.maximumNestingDepth else { throw failure("nesting too deep") }
        index += 1
        var elements: [Value] = []
        skipWhitespace()
        if consume(UInt8(ascii: "]")) { return .array(elements) }
        while true {
            elements.append(try value(depth: depth))
            skipWhitespace()
            if consume(UInt8(ascii: "]")) { return .array(elements) }
            guard consume(UInt8(ascii: ",")) else { throw failure("expected ',' or ']'") }
            skipWhitespace()
        }
    }

    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`, converted with correct rounding.
    private mutating func number() throws(Value.SyntaxError) -> Double {
        let start = index
        _ = consume(UInt8(ascii: "-"))
        if consume(UInt8(ascii: "0")) {
            // A leading zero stands alone; any digit after it is rejected by the caller.
        } else if digits() == 0 {
            throw failure("expected a digit")
        }
        if consume(UInt8(ascii: ".")), digits() == 0 { throw failure("expected a digit after '.'") }
        if index < bytes.count, bytes[index] | 0x20 == UInt8(ascii: "e") {
            index += 1
            if !consume(UInt8(ascii: "+")) { _ = consume(UInt8(ascii: "-")) }
            if digits() == 0 { throw failure("expected an exponent digit") }
        }
        // The literal is valid Swift floating-point syntax; overflow gives ±infinity, as in JavaScript.
        guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
            throw failure("unreadable number")
        }
        return value
    }

    private mutating func digits() -> Int {
        let start = index
        while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
        return index - start
    }

    private mutating func string() throws(Value.SyntaxError) -> String {
        index += 1
        var utf8: [UInt8] = []
        while true {
            guard index < bytes.count else { throw failure("unterminated string") }
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "\""):
                index += 1
                return String(decoding: utf8, as: UTF8.self)
            case UInt8(ascii: "\\"):
                index += 1
                try escape(into: &utf8)
            case 0x00..<0x20:
                throw failure("control character in string")
            default:
                // Input comes from a Swift `String`, so it is valid UTF-8; copy it through.
                utf8.append(byte)
                index += 1
            }
        }
    }

    private mutating func escape(into utf8: inout [UInt8]) throws(Value.SyntaxError) {
        guard index < bytes.count else { throw failure("unterminated escape") }
        let byte = bytes[index]
        index += 1
        let simple: UInt8? = switch byte {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): byte
        case UInt8(ascii: "b"): 0x08
        case UInt8(ascii: "f"): 0x0C
        case UInt8(ascii: "n"): 0x0A
        case UInt8(ascii: "r"): 0x0D
        case UInt8(ascii: "t"): 0x09
        default: nil
        }
        if let simple {
            utf8.append(simple)
            return
        }
        guard byte == UInt8(ascii: "u") else { throw failure("invalid escape") }
        let unit = try hexCodeUnit()
        var scalar = Unicode.Scalar(unit)
        if (0xD800...0xDBFF).contains(unit), let low = lowSurrogateEscape() {
            scalar = Unicode.Scalar(0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(low) - 0xDC00))
        }
        // A lone surrogate has no `Unicode.Scalar`; U+FFFD stands in for it.
        utf8.append(contentsOf: Unicode.UTF8.encode(scalar ?? "\u{FFFD}")!)
    }

    /// Consumes a following `\uDC00`…`\uDFFF` escape, completing a surrogate pair.
    private mutating func lowSurrogateEscape() -> UInt16? {
        guard index + 6 <= bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u")
        else { return nil }
        let saved = index
        index += 2
        if let unit = try? hexCodeUnit(), (0xDC00...0xDFFF).contains(unit) { return unit }
        index = saved
        return nil
    }

    private mutating func hexCodeUnit() throws(Value.SyntaxError) -> UInt16 {
        guard index + 4 <= bytes.count else { throw failure("incomplete \\u escape") }
        var unit: UInt16 = 0
        for byte in bytes[index..<index + 4] {
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
            default: throw failure("invalid \\u escape")
            }
            unit = unit << 4 | UInt16(digit)
        }
        index += 4
        return unit
    }

    private mutating func literal(_ word: StaticString) throws(Value.SyntaxError) {
        let count = word.utf8CodeUnitCount
        guard index + count <= bytes.count,
              bytes[index..<index + count].elementsEqual(UnsafeBufferPointer(start: word.utf8Start, count: count))
        else { throw failure("invalid literal") }
        index += count
    }

    /// JSON whitespace only: space, tab, line feed, carriage return (not U+FEFF).
    private mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D: index += 1
            default: return
            }
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private func failure(_ reason: String) -> Value.SyntaxError {
        Value.SyntaxError(offset: index, reason: reason)
    }
}

// MARK: - Codable

extension SessionState.StoredValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Self].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: Self].self))
        }
    }

    /// Writes numbers as `JSON.stringify` does: integral values without a fraction (`-0` as `0`),
    /// non-finite values as `null`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            if !value.isFinite {
                try container.encodeNil()
            } else if value.rounded(.towardZero) == value, value.magnitude <= 9_007_199_254_740_991 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}
