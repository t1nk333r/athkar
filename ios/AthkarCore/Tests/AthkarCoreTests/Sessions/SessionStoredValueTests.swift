import AthkarCore
import Testing

struct SessionStoredValueTests {
    /// JavaScript `Number(string)` reads unsigned `0x`/`0o`/`0b` integers (either case, JS whitespace trimmed);
    /// a sign, an empty body, or a digit outside the base gives NaN.
    @Test(arguments: [
        ("0x1F", 31), ("0X1f", 31), (" 0x1F\n", 31), ("0o17", 15), ("0O17", 15), ("0b101", 5), ("0B101", 5),
        ("0x1fffffffffffff", 9_007_199_254_740_991),
    ] as [(String, Double)])
    func nonDecimalIntegerStrings(text: String, expected: Double) {
        #expect(SessionState.StoredValue.string(text).numberValue == expected)
    }

    @Test(arguments: ["-0x1F", "+0x1F", "0x", "0x1G", "0o8", "0b2", "0x1F.5", "0x1Fx"])
    func malformedNonDecimalStringsAreNaN(text: String) {
        #expect(SessionState.StoredValue.string(text).numberValue.isNaN)
    }

    /// `JSON.parse` rejects anything but whitespace after the value.
    @Test(arguments: ["{}x", "{} {}", "1 2", "[]]", "\"a\"b", "null,"])
    func trailingTextIsASyntaxError(text: String) {
        #expect(throws: SessionState.StoredValue.SyntaxError.self) { try SessionState.StoredValue(parsingJSON: text) }
    }

    @Test func trailingWhitespaceIsAccepted() throws {
        #expect(try SessionState.StoredValue(parsingJSON: "{} \t\r\n") == .object([:]))
    }
}
