import Foundation

/// The PWA's transfer code (spec/transfer/transfer-v1.md §1–§4, §7): its frames, base45, zlib and JSON layers, and the
/// three ways a code arrives (pasted text, scanned QR frames, a chosen file). Each `decode` returns the validated
/// container or the error the PWA reports for the same input; `spec/transfer/fixtures/codec.json` pins both.
public enum TransferCodec {
    public static let version = 1
    public static let app = "athkar-pwa"
    /// Characters (UTF-16 code units) of a pasted code, a file, or all scanned frames together.
    public static let maxTextLength = 65_536
    public static let maxInflatedBytes = TransferInflate.cap
    public static let maxFrames = 64
    public static let frameChunk = 880
    /// A file larger than this is refused before it is read (`readTransferFile`).
    public static let maxFileBytes = maxTextLength * 4

    static let base45Alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".utf8)

    // MARK: Decoding

    /// `decodeTransfer`: a pasted code (the text form, one frame).
    public static func decode(text: String) -> Result<TransferContainer, TransferError> {
        guard text.utf16.count <= maxTextLength else { return .failure(TransferError(.tooLong)) }
        switch parseFrame(text) {
        case let .failure(error): return .failure(error)
        case let .success(frame):
            guard frame.count == 1 else { return .failure(TransferError(.oneFrame)) }
            return decodePayload([frame])
        }
    }

    /// `decodeTransferFrames`: the texts of scanned QR frames, in any order; a repeat must be identical.
    public static func decode(frames texts: [String]) -> Result<TransferContainer, TransferError> {
        guard !texts.isEmpty else { return .failure(TransferError(.notCode)) }
        guard texts.count <= maxFrames, texts.reduce(0, { $0 + $1.utf16.count }) <= maxTextLength else {
            return .failure(TransferError(.tooLong))
        }
        var frames: [Frame] = []
        for text in texts {
            switch parseFrame(text) {
            case let .failure(error): return .failure(error)
            case let .success(frame): frames.append(frame)
            }
        }
        return decodePayload(frames)
    }

    /// `decodeTransferFile`: the text of a chosen file, a transfer code or an athkar `.athkarbackup` (whose envelope
    /// imports without suwar, tasbih or reset epochs). A ruqyah backup is `wrong-app` here, as in the PWA.
    public static func decode(fileText text: String) -> Result<TransferContainer, TransferError> {
        guard text.utf16.count <= maxTextLength else { return .failure(TransferError(.tooLong)) }
        var clean = text
        if clean.unicodeScalars.first == "\u{FEFF}" { clean.unicodeScalars.removeFirst() }
        clean = trim(clean)
        if clean.hasPrefix("AQ") { return decode(text: clean) }
        guard let value = try? TransferJSON.parse(clean) else { return .failure(TransferError(.notCode)) }
        return TransferValidator.validateBackup(value)
    }

    /// A chosen file's bytes, read as the browser's `file.text()` reads them: UTF-8 with replacement characters and
    /// one leading byte-order mark dropped.
    public static func decode(fileData data: Data) -> Result<TransferContainer, TransferError> {
        guard data.count <= maxFileBytes else { return .failure(TransferError(.tooLong)) }
        var bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        return decode(fileText: String(decoding: bytes, as: UTF8.self))
    }

    // MARK: Frames

    struct Frame: Equatable {
        var app: String
        var msg: String
        var index: Int
        var count: Int
        var chunk: String
    }

    /// `parseTransferFrame`: line breaks and the ends' whitespace are dropped; text containing "=" is the text form,
    /// so every other whitespace goes and "=" reads as a space.
    static func parseFrame(_ text: String) -> Result<Frame, TransferError> {
        var units = trimUnits(text.utf16.filter { $0 != 0x0A && $0 != 0x0D })
        if units.contains(0x3D) {
            units = units.filter { !isWhitespace($0) }.map { $0 == 0x3D ? 0x20 : $0 }
        }
        // `/^AQ(\d+):/`
        guard units.count > 3, units[0] == 0x41, units[1] == 0x51 else { return .failure(TransferError(.notCode)) }
        let digits = units.dropFirst(2).prefix { (0x30...0x39).contains($0) }
        guard !digits.isEmpty, units.count > 2 + digits.count, units[2 + digits.count] == 0x3A else {
            return .failure(TransferError(.notCode))
        }
        if let number = Double(String(decoding: digits, as: UTF16.self)), number > Double(version) {
            return .failure(TransferError(.newer, reason: "version"))
        }
        guard let fields = matchFrame(units) else { return .failure(TransferError(.notCode)) }
        if checksum(Array(units.dropLast(9))) != fields.checksum {
            return .failure(TransferError(.corrupt, reason: "checksum"))
        }
        guard fields.frame.app == "A" else { return .failure(TransferError(.wrongApp)) }
        guard fields.frame.count <= maxFrames else { return .failure(TransferError(.tooLong)) }
        guard fields.frame.index <= fields.frame.count else { return .failure(TransferError(.notCode)) }
        return .success(fields.frame)
    }

    /// `^AQ1:([A-Z]):([0-9A-Z]{4}):([1-9][0-9]?):([1-9][0-9]?):([0-9A-Z $%*+\-./:]+):([0-9A-F]{8})$`
    private static func matchFrame(_ units: [UInt16]) -> (frame: Frame, checksum: String)? {
        guard units.allSatisfy({ $0 < 0x80 }) else { return nil }
        let text = String(decoding: units, as: UTF16.self)
        let parts = text.split(separator: ":", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        // The chunk may contain ":", so the checksum is the text after the last one.
        guard parts.count == 6, parts[0] == "AQ1", let lastColon = text.lastIndex(of: ":") else { return nil }
        let chunkAndSum = parts[5]
        let sum = String(text[text.index(after: lastColon)...])
        let chunk = String(chunkAndSum.dropLast(sum.count + 1))
        guard chunkAndSum.count > sum.count else { return nil }
        let upper = { (c: UInt8) in (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(c) }
        let digit = { (c: UInt8) in (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(c) }
        func number(_ field: String) -> Int? {
            let bytes = Array(field.utf8)
            guard (1...2).contains(bytes.count), bytes[0] != UInt8(ascii: "0"), bytes.allSatisfy(digit) else { return nil }
            return Int(field)
        }
        let app = Array(parts[1].utf8)
        let msg = Array(parts[2].utf8)
        let sumBytes = Array(sum.utf8)
        guard app.count == 1, upper(app[0]),
              msg.count == 4, msg.allSatisfy({ upper($0) || digit($0) }),
              let index = number(parts[3]), let count = number(parts[4]),
              !chunk.isEmpty, chunk.utf8.allSatisfy({ base45Alphabet.contains($0) }),
              sumBytes.count == 8, sumBytes.allSatisfy({ digit($0) || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains($0) })
        else { return nil }
        return (Frame(app: parts[1], msg: parts[2], index: index, count: count, chunk: chunk), sum)
    }

    /// `decodeTransferPayload`.
    static func decodePayload(_ frames: [Frame]) -> Result<TransferContainer, TransferError> {
        let first = frames[0]
        var chunks: [Int: String] = [:]
        for frame in frames {
            guard frame.msg == first.msg, frame.count == first.count else { return .failure(TransferError(.mixed)) }
            if let known = chunks[frame.index], known != frame.chunk { return .failure(TransferError(.mixed)) }
            chunks[frame.index] = frame.chunk
        }
        guard (1...first.count).allSatisfy({ chunks[$0] != nil }) else { return .failure(TransferError(.incomplete)) }
        guard let bytes = base45Decode((1...first.count).map { chunks[$0]! }.joined()) else {
            return .failure(.corrupt("base45"))
        }
        let inflated: [UInt8]
        switch TransferInflate.inflate(bytes) {
        case let .success(output): inflated = output
        case let .failure(failure): return .failure(.corrupt(failure.reason))
        }
        // `new TextDecoder("utf-8", { fatal: true })`, which also drops one leading byte-order mark.
        var text = String(decoding: inflated, as: UTF8.self)
        guard Array(text.utf8) == inflated else { return .failure(.corrupt("json")) }
        if text.unicodeScalars.first == "\u{FEFF}" { text.unicodeScalars.removeFirst() }
        guard let value = try? TransferJSON.parse(text) else { return .failure(.corrupt("json")) }
        return TransferValidator.validateCode(value)
    }

    // MARK: Base45 and checksum

    /// RFC 9285.
    static func base45Encode(_ bytes: [UInt8]) -> String {
        var text: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if index + 1 < bytes.count {
                let value = Int(bytes[index]) * 256 + Int(bytes[index + 1])
                text += [base45Alphabet[value % 45], base45Alphabet[value / 45 % 45], base45Alphabet[value / 2025]]
            } else {
                text += [base45Alphabet[Int(bytes[index]) % 45], base45Alphabet[Int(bytes[index]) / 45]]
            }
            index += 2
        }
        return String(decoding: text, as: UTF8.self)
    }

    /// The bytes, or `nil` when the text is not base45: a character outside the alphabet, one dangling character, a
    /// group above 65535 or a final pair above 255.
    static func base45Decode(_ text: String) -> [UInt8]? {
        let units = Array(text.utf16)
        guard units.count % 3 != 1 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(units.count / 3 * 2 + 1)
        var index = 0
        while index < units.count {
            let group = units[index..<min(index + 3, units.count)]
            var digits: [Int] = []
            for unit in group {
                guard unit < 0x80, let digit = base45Alphabet.firstIndex(of: UInt8(unit)) else { return nil }
                digits.append(digit)
            }
            let value = digits[0] + digits[1] * 45 + (digits.count == 3 ? digits[2] * 2025 : 0)
            guard value <= (digits.count == 3 ? 65535 : 255) else { return nil }
            if digits.count == 3 { bytes.append(UInt8(value / 256)) }
            bytes.append(UInt8(value % 256))
            index += 3
        }
        return bytes
    }

    /// `transferChecksum`: Adler-32 of a frame's text (UTF-16 code units) up to its checksum field, as 8 uppercase hex
    /// digits.
    static func checksum(_ units: [UInt16]) -> String {
        var low = 1
        var high = 0
        for unit in units {
            low = (low + Int(unit)) % 65521
            high = (high + low) % 65521
        }
        let hex = String(high * 65536 + low, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 8 - hex.count)) + hex
    }

    static func checksum(_ text: String) -> String {
        checksum(Array(text.utf16))
    }

    // MARK: Encoding (tests and previews of codes built here)

    /// `transferFrames`: the QR frames of a base45 payload, `n` equal slices of at most `chunk` characters.
    static func frames(payload: String, msg: String, chunk: Int = frameChunk) -> [String] {
        let characters = Array(payload)
        let count = max(1, (characters.count + chunk - 1) / chunk)
        let size = (characters.count + count - 1) / count
        return (0..<count).map { index in
            let slice = String(characters[min(characters.count, index * size)..<min(characters.count, (index + 1) * size)])
            let body = "AQ1:A:\(msg):\(index + 1):\(count):\(slice)"
            return "\(body):\(checksum(body))"
        }
    }

    /// `transferTextCode`: the one-frame text form, spaces written as "=".
    static func textCode(payload: String, msg: String) -> String {
        frames(payload: payload, msg: msg, chunk: max(1, payload.count))[0].replacingOccurrences(of: " ", with: "=")
    }

    // MARK: JavaScript whitespace

    /// `\s` and what `trim()` removes.
    static func isWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    private static func trimUnits(_ units: [UInt16]) -> [UInt16] {
        guard let first = units.firstIndex(where: { !isWhitespace($0) }),
              let last = units.lastIndex(where: { !isWhitespace($0) })
        else { return [] }
        return Array(units[first...last])
    }

    static func trim(_ text: String) -> String {
        String(decoding: trimUnits(Array(text.utf16)), as: UTF16.self)
    }
}
