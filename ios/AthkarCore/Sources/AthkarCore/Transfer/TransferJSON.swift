import Foundation

/// A parsed transfer document, as JavaScript's `JSON.parse` builds it: duplicate keys keep the last value in the
/// first key's place, and objects list integer-like keys first in ascending order, then the rest in insertion order
/// (`Object.keys`). The validator reports the first failing path in that order, as the PWA does.
///
/// Containers nested deeper than ``inspectedDepth`` are parsed for syntax but not kept (``opaque``): the validator
/// never descends that far (the deepest value it reads is at depth 7), so a code nested 10 000 levels deep is refused
/// by the validator, as in the PWA, instead of by the parser or the stack.
indirect enum TransferJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([TransferJSON])
    case object([(key: String, value: TransferJSON)])
    /// A container below ``inspectedDepth``: well-formed, never inspected.
    case opaque

    static let inspectedDepth = 24

    static func == (lhs: TransferJSON, rhs: TransferJSON) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null), (.opaque, .opaque): true
        case let (.bool(a), .bool(b)): a == b
        case let (.number(a), .number(b)): a == b
        case let (.string(a), .string(b)): TasbihPhrase.same(a, b)
        case let (.array(a), .array(b)): a == b
        case let (.object(a), .object(b)):
            a.count == b.count && zip(a, b).allSatisfy { TasbihPhrase.same($0.key, $1.key) && $0.value == $1.value }
        default: false
        }
    }

    var members: [(key: String, value: TransferJSON)]? {
        if case let .object(members) = self { members } else { nil }
    }

    subscript(key: String) -> TransferJSON? {
        members?.first { TasbihPhrase.same($0.key, key) }?.value
    }

    var string: String? {
        if case let .string(text) = self { text } else { nil }
    }

    var number: Double? {
        if case let .number(value) = self { value } else { nil }
    }

    var bool: Bool? {
        if case let .bool(value) = self { value } else { nil }
    }

    var array: [TransferJSON]? {
        if case let .array(elements) = self { elements } else { nil }
    }

    /// `Number.isInteger(value)`.
    var integer: Int? {
        guard let value = number, value.isFinite, value.rounded(.towardZero) == value, abs(value) < 9.1e15 else {
            return nil
        }
        return Int(value)
    }

    struct SyntaxError: Error {}

    /// `JSON.parse(text)`. A lone surrogate escape becomes U+FFFD (Swift strings hold only scalars).
    static func parse(_ text: String) throws(SyntaxError) -> TransferJSON {
        var parser = Parser(bytes: Array(text.utf8))
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw SyntaxError() }
        return value
    }

    // MARK: Writing

    /// `JSON.stringify`, for tests and the fixtures' comparisons.
    var serialized: String {
        switch self {
        case .null, .opaque: return "null"
        case let .bool(value): return value ? "true" : "false"
        case let .number(value):
            if value.rounded(.towardZero) == value, abs(value) < 1e15 { return String(Int64(value)) }
            return "\(value)"
        case let .string(text): return Self.quoted(text)
        case let .array(elements): return "[" + elements.map(\.serialized).joined(separator: ",") + "]"
        case let .object(members):
            return "{" + members.map { Self.quoted($0.key) + ":" + $0.value.serialized }.joined(separator: ",") + "}"
        }
    }

    private static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0x0A: result += "\\n"
            case 0x0D: result += "\\r"
            case 0x09: result += "\\t"
            case 0x08: result += "\\b"
            case 0x0C: result += "\\f"
            case ..<0x20: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}

private struct Parser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    mutating func value(depth: Int) throws(TransferJSON.SyntaxError) -> TransferJSON {
        guard index < bytes.count else { throw TransferJSON.SyntaxError() }
        switch bytes[index] {
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            if depth >= TransferJSON.inspectedDepth {
                try skipContainer()
                return .opaque
            }
            return bytes[index] == UInt8(ascii: "{") ? try object(depth: depth + 1) : try array(depth: depth + 1)
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try number())
        default: throw TransferJSON.SyntaxError()
        }
    }

    private mutating func object(depth: Int) throws(TransferJSON.SyntaxError) -> TransferJSON {
        index += 1
        var keys: [String] = []
        var values: [String: TransferJSON] = [:]
        skipWhitespace()
        if !consume(UInt8(ascii: "}")) {
            while true {
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw TransferJSON.SyntaxError() }
                let key = try string()
                skipWhitespace()
                guard consume(UInt8(ascii: ":")) else { throw TransferJSON.SyntaxError() }
                skipWhitespace()
                let member = try value(depth: depth)
                // Keyed by code units: two keys that are only canonically equivalent are two properties in JavaScript.
                let unitKey = Self.unitKey(key)
                if values[unitKey] == nil { keys.append(key) }
                values[unitKey] = member
                skipWhitespace()
                if consume(UInt8(ascii: "}")) { break }
                guard consume(UInt8(ascii: ",")) else { throw TransferJSON.SyntaxError() }
                skipWhitespace()
            }
        }
        // `Object.keys` order: array indices ascending, then the other keys in insertion order.
        let indices = keys.compactMap { key in SessionState.StoredValue.arrayIndex(key).map { (key, $0) } }
            .sorted { $0.1 < $1.1 }.map(\.0)
        let others = keys.filter { SessionState.StoredValue.arrayIndex($0) == nil }
        return .object((indices + others).map { ($0, values[Self.unitKey($0)]!) })
    }

    private static func unitKey(_ key: String) -> String {
        key.utf16.map { String($0, radix: 16) }.joined(separator: ".")
    }

    private mutating func array(depth: Int) throws(TransferJSON.SyntaxError) -> TransferJSON {
        index += 1
        var elements: [TransferJSON] = []
        skipWhitespace()
        if consume(UInt8(ascii: "]")) { return .array(elements) }
        while true {
            elements.append(try value(depth: depth))
            skipWhitespace()
            if consume(UInt8(ascii: "]")) { return .array(elements) }
            guard consume(UInt8(ascii: ",")) else { throw TransferJSON.SyntaxError() }
            skipWhitespace()
        }
    }

    /// Checks a container's syntax without recursion or keeping it: a stack of the open containers' kinds.
    private mutating func skipContainer() throws(TransferJSON.SyntaxError) {
        var open: [UInt8] = []
        // `true` when a value (or, in an object, a key) is expected next.
        var expectingValue = true
        repeat {
            skipWhitespace()
            guard index < bytes.count else { throw TransferJSON.SyntaxError() }
            let byte = bytes[index]
            if expectingValue {
                if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") {
                    open.append(byte)
                    index += 1
                    skipWhitespace()
                    let close = byte == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
                    if consume(close) {
                        open.removeLast()
                        expectingValue = false
                    } else if byte == UInt8(ascii: "{") {
                        try key()
                    }
                    continue
                }
                _ = try scalar()
                expectingValue = false
            } else {
                guard let top = open.last else { break }
                if consume(UInt8(ascii: ",")) {
                    expectingValue = true
                    if top == UInt8(ascii: "{") {
                        skipWhitespace()
                        try key()
                    }
                } else if consume(top == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")) {
                    open.removeLast()
                } else {
                    throw TransferJSON.SyntaxError()
                }
            }
        } while !open.isEmpty || expectingValue
    }

    /// An object key and its colon, inside ``skipContainer()``.
    private mutating func key() throws(TransferJSON.SyntaxError) {
        guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw TransferJSON.SyntaxError() }
        _ = try string()
        skipWhitespace()
        guard consume(UInt8(ascii: ":")) else { throw TransferJSON.SyntaxError() }
    }

    private mutating func scalar() throws(TransferJSON.SyntaxError) -> TransferJSON {
        switch bytes[index] {
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try number())
        default: throw TransferJSON.SyntaxError()
        }
    }

    private mutating func literal(_ word: String) throws(TransferJSON.SyntaxError) {
        let expected = Array(word.utf8)
        guard index + expected.count <= bytes.count, Array(bytes[index..<(index + expected.count)]) == expected
        else { throw TransferJSON.SyntaxError() }
        index += expected.count
    }

    private mutating func digits() -> Int {
        let start = index
        while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
        return index - start
    }

    private mutating func number() throws(TransferJSON.SyntaxError) -> Double {
        let start = index
        _ = consume(UInt8(ascii: "-"))
        if !consume(UInt8(ascii: "0")), digits() == 0 { throw TransferJSON.SyntaxError() }
        if consume(UInt8(ascii: ".")), digits() == 0 { throw TransferJSON.SyntaxError() }
        if index < bytes.count, bytes[index] | 0x20 == UInt8(ascii: "e") {
            index += 1
            if !consume(UInt8(ascii: "+")) { _ = consume(UInt8(ascii: "-")) }
            if digits() == 0 { throw TransferJSON.SyntaxError() }
        }
        // Valid Swift floating-point syntax; overflow gives ±infinity and underflow 0, as in JavaScript.
        guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
            throw TransferJSON.SyntaxError()
        }
        return value
    }

    private mutating func string() throws(TransferJSON.SyntaxError) -> String {
        index += 1
        var units: [UInt16] = []
        var start = index
        func flush(_ end: Int) {
            units.append(contentsOf: String(decoding: bytes[start..<end], as: UTF8.self).utf16)
        }
        while true {
            guard index < bytes.count else { throw TransferJSON.SyntaxError() }
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                flush(index)
                index += 1
                break
            }
            guard byte >= 0x20 else { throw TransferJSON.SyntaxError() }
            if byte != UInt8(ascii: "\\") {
                index += 1
                continue
            }
            flush(index)
            index += 1
            guard index < bytes.count else { throw TransferJSON.SyntaxError() }
            let escape = bytes[index]
            index += 1
            switch escape {
            case UInt8(ascii: "\""): units.append(0x22)
            case UInt8(ascii: "\\"): units.append(0x5C)
            case UInt8(ascii: "/"): units.append(0x2F)
            case UInt8(ascii: "b"): units.append(0x08)
            case UInt8(ascii: "f"): units.append(0x0C)
            case UInt8(ascii: "n"): units.append(0x0A)
            case UInt8(ascii: "r"): units.append(0x0D)
            case UInt8(ascii: "t"): units.append(0x09)
            case UInt8(ascii: "u"):
                guard index + 4 <= bytes.count,
                      let unit = UInt16(String(decoding: bytes[index..<(index + 4)], as: UTF8.self), radix: 16),
                      bytes[index..<(index + 4)].allSatisfy({ $0 != UInt8(ascii: "+") && $0 != UInt8(ascii: "-") })
                else { throw TransferJSON.SyntaxError() }
                units.append(unit)
                index += 4
            default: throw TransferJSON.SyntaxError()
            }
            start = index
        }
        // Lone surrogates decode to U+FFFD.
        return String(decoding: units, as: UTF16.self)
    }
}
