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

    /// Property access `value[key]` on a parsed JSON value. Only objects have named members.
    func member(_ key: String) -> Self? {
        if case .object(let members) = self { members[key] } else { nil }
    }

    var stringValue: String? {
        if case .string(let text) = self { text } else { nil }
    }

    /// Entries of a value that passes the PWA's `value && typeof value === "object"` check, as a key → value
    /// map. Arrays are keyed by index, which is how property lookup by item id sees them.
    var objectEntries: [String: Self]? {
        switch self {
        case .object(let members):
            return members
        case .array(let elements):
            var members: [String: Self] = [:]
            members.reserveCapacity(elements.count)
            for (index, element) in elements.enumerated() { members[String(index)] = element }
            return members
        default:
            return nil
        }
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
