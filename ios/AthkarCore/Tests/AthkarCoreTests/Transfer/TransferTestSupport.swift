@testable import AthkarCore
import Foundation

/// `spec/transfer/fixtures/*.json`, read as `JSON.parse` reads them (key order kept, lone surrogates allowed).
enum TransferFixtures {
    static func load(_ file: String) throws -> TransferJSON {
        let text = String(decoding: try RepoFile.data("spec/transfer/fixtures/\(file)"), as: UTF8.self)
        return try TransferJSON.parse(text)
    }

    /// The «سور» suras and pages as the app's outline gives them from content/suwar.v1.json (sura ID, name, each
    /// page's verse range). Written out here so the core tests do not read the bundled pack.
    static let suwar: [SuwarOutline] = [
        ("kahf", "سورة الكهف", "1-4 5-8 9-12 13-15 16-17 18-18 19-19 20-21 22-23 24-26 27-28 29-30 31-32 33-36 37-40 41-44 45-47 48-49 50-52 53-55 56-57 58-61 62-65 66-70 71-74 75-77 78-81 82-84 85-89 90-94 95-98 99-103 104-107 108-110"),
        ("yasin", "سورة يس", "1-8 9-12 13-17 18-22 23-28 29-33 34-38 39-43 44-47 48-52 53-58 59-64 65-68 69-73 74-78 79-83"),
        ("saffat", "سورة الصافات", "1-9 10-17 18-25 26-33 34-41 42-52 53-61 62-70 71-79 80-90 91-99 100-105 106-114 115-123 124-133 134-143 144-151 152-161 162-171 172-182"),
        ("waqiah", "سورة الواقعة", "1-11 12-23 24-36 37-47 48-58 59-66 67-75 76-85 86-96"),
        ("mulk", "سورة الملك", "1-4 5-8 9-13 14-17 18-21 22-26 27-30"),
    ].map { id, name, pages in
        SuwarOutline(id: id, name: name, pageIDs: pages.split(separator: " ").map { "\(id)-\($0)" })
    }
}

/// A small zlib writer for the tests: greedy LZ77 with the fixed Huffman code (RFC 1951 §3.2.6), enough to build codes
/// as compact as the PWA's within the text limit, and deflate bombs.
enum TestDeflate {
    private struct BitWriter {
        var bytes: [UInt8] = []
        var buffer: UInt32 = 0
        var count = 0

        mutating func write(_ value: Int, bits: Int) {
            buffer |= UInt32(value) << count
            count += bits
            while count >= 8 {
                bytes.append(UInt8(buffer & 0xFF))
                buffer >>= 8
                count -= 8
            }
        }

        /// A Huffman code, most significant bit first.
        mutating func code(_ value: Int, bits: Int) {
            var reversed = 0
            for index in 0..<bits where value & (1 << index) != 0 { reversed |= 1 << (bits - 1 - index) }
            write(reversed, bits: bits)
        }

        mutating func finish() -> [UInt8] {
            if count > 0 { bytes.append(UInt8(buffer & 0xFF)) }
            buffer = 0
            count = 0
            return bytes
        }
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
                                     131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025,
                                       1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12,
                                        12, 13, 13]

    private static func literal(_ value: Int, into writer: inout BitWriter) {
        switch value {
        case 0...143: writer.code(0x30 + value, bits: 8)
        case 144...255: writer.code(0x190 + value - 144, bits: 9)
        case 256...279: writer.code(value - 256, bits: 7)
        default: writer.code(0xC0 + value - 280, bits: 8)
        }
    }

    private static func match(length: Int, distance: Int, into writer: inout BitWriter) {
        let lengthCode = lengthBase.lastIndex { $0 <= length }!
        literal(257 + lengthCode, into: &writer)
        writer.write(length - lengthBase[lengthCode], bits: lengthExtra[lengthCode])
        let distanceCode = distanceBase.lastIndex { $0 <= distance }!
        writer.code(distanceCode, bits: 5)
        writer.write(distance - distanceBase[distanceCode], bits: distanceExtra[distanceCode])
    }

    private static func wrap(_ deflated: [UInt8], adler: UInt32) -> [UInt8] {
        [0x78, 0x01] + deflated + [UInt8(adler >> 24), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF),
                                   UInt8(adler & 0xFF)]
    }

    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var low: UInt32 = 1
        var high: UInt32 = 0
        for byte in bytes {
            low = (low + UInt32(byte)) % 65521
            high = (high + low) % 65521
        }
        return high << 16 | low
    }

    /// `bytes` as one fixed-Huffman block in a zlib stream.
    static func zlib(_ bytes: [UInt8]) -> [UInt8] {
        var writer = BitWriter()
        writer.write(1, bits: 1)
        writer.write(1, bits: 2)
        var heads: [Int: [Int]] = [:]
        var index = 0
        func hash(_ at: Int) -> Int { Int(bytes[at]) << 16 | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) }
        while index < bytes.count {
            var bestLength = 0
            var bestDistance = 0
            if index + 3 <= bytes.count {
                for candidate in (heads[hash(index)] ?? []).reversed().prefix(64) where index - candidate <= 32768 {
                    var length = 0
                    while length < 258, index + length < bytes.count, bytes[candidate + length] == bytes[index + length] {
                        length += 1
                    }
                    if length > bestLength {
                        bestLength = length
                        bestDistance = index - candidate
                    }
                }
            }
            let step = bestLength >= 3 ? bestLength : 1
            if bestLength >= 3 {
                match(length: bestLength, distance: bestDistance, into: &writer)
            } else {
                literal(Int(bytes[index]), into: &writer)
            }
            for position in index..<(index + step) where position + 3 <= bytes.count {
                heads[hash(position), default: []].append(position)
            }
            index += step
        }
        literal(256, into: &writer)
        return wrap(writer.finish(), adler: adler32(bytes))
    }

    /// `count` zero bytes (`count` ≥ 4), as runs of 258 at distance 1: a deflate bomb.
    static func zeros(_ count: Int) -> [UInt8] {
        var writer = BitWriter()
        writer.write(1, bits: 1)
        writer.write(1, bits: 2)
        literal(0, into: &writer)
        var left = count - 1
        while left > 0 {
            var length = min(258, left)
            if (1...2).contains(left - length) { length -= 3 }
            match(length: length, distance: 1, into: &writer)
            left -= length
        }
        literal(256, into: &writer)
        var adler: (low: UInt32, high: UInt32) = (1, 0)
        for _ in 0..<count { adler.high = (adler.high + adler.low) % 65521 }
        return wrap(writer.finish(), adler: adler.high << 16 | adler.low)
    }

    /// A transfer code's text form for `json`, as encodeTransfer writes it (message ID `TEST`).
    static func textCode(_ json: String) -> String {
        TransferCodec.textCode(payload: TransferCodec.base45Encode(zlib(Array(json.utf8))), msg: "TEST")
    }

    static func frames(_ json: String) -> [String] {
        TransferCodec.frames(payload: TransferCodec.base45Encode(zlib(Array(json.utf8))), msg: "TEST")
    }
}

/// Containers for the importer's tests, built from parts.
enum TransferSamples {
    static let exportedAt = "2026-10-04T06:00:00.000Z"

    static func envelope(date: String = "2026-10-04", exportedAt: String = exportedAt, morning: String = "{}",
                         evening: String = "{}", targets: String = #"{"morning":{},"evening":{}}"#,
                         completedAt: String = #"{"morning":null,"evening":null}"#,
                         manual: String = #"{"morning":false,"evening":false}"#, history: String = "[]",
                         preferences: String = #"{"theme":"system","textSize":"medium","lineSpacing":"comfortable","haptics":true,"longOrder":"original","longOrderPromptAnswered":false}"#,
                         calculation: String = #""calculationMethod":"mwl","asrSchool":"standard""#) -> String {
        """
        {"meta":{"format":1,"app":"athkar-pwa","exportedAt":"\(exportedAt)","timeZone":"Asia/Riyadh"},\
        "adhkar":{"today":{"date":"\(date)","progress":{"morning":\(morning),"evening":\(evening)},\
        "targets":\(targets),"completedAt":\(completedAt),"manualCompletion":\(manual)},"history":\(history)},\
        "reminders":{"morning":{"enabled":false},"evening":{"enabled":false},\(calculation),\
        "lastShown":{"morning":null,"evening":null}},"preferences":\(preferences)}
        """
    }

    static func suwar(date: String = "2026-10-04", read: String = "{}", completedAt: String = "{}",
                      history: String = "{}", resets: String = "{}") -> String {
        #"{"date":"\#(date)","selected":"kahf","read":\#(read),"completedAt":\#(completedAt),"history":\#(history),"resets":\#(resets)}"#
    }

    static func tasbih(date: String = "2026-10-04", counts: String = "{}", firstUse: String = "[]", custom: String = "[]",
                       history: String = "{}", resets: String = "{}") -> String {
        #"{"date":"\#(date)","selected":"subhan","target":33,"counts":\#(counts),"firstUse":\#(firstUse),"custom":\#(custom),"history":\#(history),"resets":\#(resets)}"#
    }

    static func code(envelope: String = envelope(), adhkarResets: String = "{}", adhkarHistory: String = "[]",
                     suwar: String = suwar(), tasbih: String = tasbih()) -> String {
        #"{"transfer":1,"app":"athkar-pwa","envelope":\#(envelope),"athkar":{"adhkar":{"resets":\#(adhkarResets),"history":\#(adhkarHistory)},"suwar":\#(suwar),"tasbih":\#(tasbih)}}"#
    }

    /// The validated container of `json`; traps on bad test input.
    static func container(_ json: String) throws -> TransferContainer {
        try TransferValidator.validateCode(try TransferJSON.parse(json)).get()
    }
}
