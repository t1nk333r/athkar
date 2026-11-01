import Foundation
#if canImport(Compression)
import Compression
#endif

/// The zlib stream (RFC 1950) inside a transfer code: header, DEFLATE data (RFC 1951) and Adler-32 trailer, with nothing
/// after it (spec/transfer/transfer-v1.md §4 "Inflate").
///
/// A deflate bomb is cut off: once the output passes ``cap`` bytes, inflation stops with `inflate-cap`. On Apple
/// platforms the DEFLATE data goes through the Compression framework, 256 compressed bytes at a time into a 4 KiB
/// buffer, so at most `cap` + 4 KiB is ever inflated. Elsewhere (the Linux core suite) ``Inflater`` decodes it, one
/// byte of output at a time against the cap. Both read the same header and trailer.
enum TransferInflate {
    /// `transferMaxInflatedBytes`: the JSON is at most 256 KiB.
    static let cap = 262_144

    enum Failure: Error, Equatable {
        /// Not a valid zlib stream: header, DEFLATE data, checksum, truncation or trailing bytes (`inflate`).
        case invalid
        /// The output passed the cap (`inflate-cap`).
        case cap

        var reason: String { self == .cap ? "inflate-cap" : "inflate" }
    }

    static func inflate(_ zlib: [UInt8], cap: Int = cap) -> Result<[UInt8], Failure> {
        #if canImport(Compression)
        return inflateWithCompression(zlib, cap: cap)
        #else
        return inflatePortable(zlib, cap: cap)
        #endif
    }

    /// The portable decoder, also used by the tests on every platform.
    static func inflatePortable(_ zlib: [UInt8], cap: Int = cap) -> Result<[UInt8], Failure> {
        guard headerIsValid(zlib) else { return .failure(.invalid) }
        var inflater = Inflater(input: zlib, position: 2, cap: cap)
        do {
            try inflater.run()
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.invalid)
        }
        // The trailer starts at the next byte boundary after the last block.
        let end = inflater.position
        guard zlib.count - end == 4, adler32(inflater.output) == trailer(zlib) else { return .failure(.invalid) }
        return .success(inflater.output)
    }

    /// CMF and FLG: method 8 (deflate), a window of at most 32 KiB, a valid check, and no preset dictionary.
    static func headerIsValid(_ zlib: [UInt8]) -> Bool {
        guard zlib.count >= 6 else { return false }
        let cmf = Int(zlib[0])
        let flg = Int(zlib[1])
        return cmf & 0x0F == 8 && cmf >> 4 <= 7 && (cmf * 256 + flg) % 31 == 0 && flg & 0x20 == 0
    }

    private static func trailer(_ zlib: [UInt8]) -> UInt32 {
        zlib.suffix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    static func adler32<Bytes: Sequence>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
        var low: UInt32 = 1
        var high: UInt32 = 0
        for byte in bytes {
            low = (low + UInt32(byte)) % 65521
            high = (high + low) % 65521
        }
        return high << 16 | low
    }

    #if canImport(Compression)
    /// Apple's `COMPRESSION_ZLIB` is raw DEFLATE, so the header and trailer are read here. The DEFLATE data is every
    /// byte between them: it must end exactly where the trailer starts, which rejects both truncation and bytes after
    /// the stream (they would sit before the last four bytes, or make the checksum differ).
    static func inflateWithCompression(_ zlib: [UInt8], cap: Int) -> Result<[UInt8], Failure> {
        guard headerIsValid(zlib) else { return .failure(.invalid) }
        let deflate = Array(zlib[2..<(zlib.count - 4)])
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
        else { return .failure(.invalid) }
        defer { compression_stream_destroy(stream) }
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        var output: [UInt8] = []
        let result: Failure? = deflate.withUnsafeBufferPointer { source -> Failure? in
            var fed = 0
            stream.pointee.src_size = 0
            while true {
                if stream.pointee.src_size == 0, fed < source.count, let base = source.baseAddress {
                    let slice = min(256, source.count - fed)
                    stream.pointee.src_ptr = base + fed
                    stream.pointee.src_size = slice
                    fed += slice
                }
                let finalize = fed == source.count
                let before = stream.pointee.src_size
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = bufferSize
                let status = compression_stream_process(
                    stream, finalize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                let produced = bufferSize - stream.pointee.dst_size
                output.append(contentsOf: UnsafeBufferPointer(start: buffer, count: produced))
                if output.count > cap { return .cap }
                switch status {
                case COMPRESSION_STATUS_END:
                    // The stream must end exactly where the trailer starts.
                    return stream.pointee.src_size == 0 && fed == source.count ? nil : .invalid
                case COMPRESSION_STATUS_OK:
                    let consumed = before - stream.pointee.src_size
                    // No input left and nothing more to give: the DEFLATE data stops before its last block ends.
                    if produced == 0, consumed == 0, stream.pointee.src_size == 0, fed == source.count {
                        return .invalid
                    }
                    if produced == 0, consumed == 0, stream.pointee.src_size > 0 { return .invalid }
                default:
                    return .invalid
                }
            }
        }
        if let result { return .failure(result) }
        guard adler32(output) == trailer(zlib) else { return .failure(.invalid) }
        return .success(output)
    }
    #endif
}

/// RFC 1951 inflate (after Mark Adler's `puff`), with an output cap.
struct Inflater {
    let input: [UInt8]
    /// The next unread byte. After ``run()`` it is the byte after the last block (bits left in a partly read byte are
    /// dropped, as the trailer starts on a byte boundary).
    var position: Int
    let cap: Int
    var output: [UInt8] = []
    private var bitBuffer = 0
    private var bitCount = 0

    init(input: [UInt8], position: Int, cap: Int) {
        self.input = input
        self.position = position
        self.cap = cap
    }

    mutating func run() throws {
        var last = false
        repeat {
            last = try bits(1) == 1
            switch try bits(2) {
            case 0: try stored()
            case 1: try codes(Self.fixedLengths, Self.fixedDistances)
            case 2: try dynamic()
            default: throw TransferInflate.Failure.invalid
            }
        } while !last
        bitBuffer = 0
        bitCount = 0
    }

    private mutating func bits(_ count: Int) throws -> Int {
        var value = bitBuffer
        while bitCount < count {
            guard position < input.count else { throw TransferInflate.Failure.invalid }
            value |= Int(input[position]) << bitCount
            position += 1
            bitCount += 8
        }
        bitBuffer = value >> count
        bitCount -= count
        return value & ((1 << count) - 1)
    }

    private mutating func emit(_ byte: UInt8) throws {
        output.append(byte)
        if output.count > cap { throw TransferInflate.Failure.cap }
    }

    private mutating func stored() throws {
        bitBuffer = 0
        bitCount = 0
        guard position + 4 <= input.count else { throw TransferInflate.Failure.invalid }
        let length = Int(input[position]) | Int(input[position + 1]) << 8
        let complement = Int(input[position + 2]) | Int(input[position + 3]) << 8
        position += 4
        guard length == ~complement & 0xFFFF, position + length <= input.count else {
            throw TransferInflate.Failure.invalid
        }
        for byte in input[position..<(position + length)] { try emit(byte) }
        position += length
    }

    /// A canonical Huffman code: how many codes of each length, and the symbols in code order.
    struct Huffman {
        var counts: [Int]
        var symbols: [Int]

        /// `nil` when the lengths oversubscribe the code, or leave it incomplete: an incomplete literal or distance
        /// code is allowed only when it has a single code, and the code-length code must be complete. The fixed
        /// distance code (30 of 32 five-bit codes) is incomplete by definition (`fixed`).
        init?(lengths: [Int], complete: Bool = false, fixed: Bool = false) {
            counts = Array(repeating: 0, count: 16)
            for length in lengths { counts[length] += 1 }
            var left = 1
            for length in 1...15 {
                left <<= 1
                left -= counts[length]
                if left < 0 { return nil }
            }
            if left > 0, !fixed, complete || lengths.count - counts[0] != 1 { return nil }
            var offsets = Array(repeating: 0, count: 16)
            for length in 1..<15 { offsets[length + 1] = offsets[length] + counts[length] }
            symbols = Array(repeating: 0, count: lengths.count)
            for (symbol, length) in lengths.enumerated() where length != 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
        }
    }

    private mutating func decode(_ huffman: Huffman) throws -> Int {
        var code = 0
        var first = 0
        var index = 0
        for length in 1...15 {
            code |= try bits(1)
            let count = huffman.counts[length]
            if code - count < first { return huffman.symbols[index + (code - first)] }
            index += count
            first += count
            first <<= 1
            code <<= 1
        }
        throw TransferInflate.Failure.invalid
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99,
                                     115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
                                       1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
                                        12, 12, 13, 13]

    private static let fixedLengths = Huffman(
        lengths: Array(repeating: 8, count: 144) + Array(repeating: 9, count: 112) + Array(repeating: 7, count: 24)
            + Array(repeating: 8, count: 8))!
    private static let fixedDistances = Huffman(lengths: Array(repeating: 5, count: 30), fixed: true)!

    private mutating func codes(_ lengths: Huffman, _ distances: Huffman) throws {
        while true {
            let symbol = try decode(lengths)
            if symbol < 256 {
                try emit(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let lengthIndex = symbol - 257
                guard lengthIndex < 29 else { throw TransferInflate.Failure.invalid }
                let length = Self.lengthBase[lengthIndex] + (try bits(Self.lengthExtra[lengthIndex]))
                let distanceIndex = try decode(distances)
                guard distanceIndex < 30 else { throw TransferInflate.Failure.invalid }
                let distance = Self.distanceBase[distanceIndex] + (try bits(Self.distanceExtra[distanceIndex]))
                guard distance <= output.count else { throw TransferInflate.Failure.invalid }
                for _ in 0..<length { try emit(output[output.count - distance]) }
            }
        }
    }

    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private mutating func dynamic() throws {
        let literalCount = try bits(5) + 257
        let distanceCount = try bits(5) + 1
        let codeCount = try bits(4) + 4
        guard literalCount <= 286, distanceCount <= 30 else { throw TransferInflate.Failure.invalid }
        var codeLengths = Array(repeating: 0, count: 19)
        for index in 0..<codeCount { codeLengths[Self.codeLengthOrder[index]] = try bits(3) }
        guard let codeLengthCode = Huffman(lengths: codeLengths, complete: true) else { throw TransferInflate.Failure.invalid }
        var lengths: [Int] = []
        while lengths.count < literalCount + distanceCount {
            let symbol = try decode(codeLengthCode)
            if symbol < 16 {
                lengths.append(symbol)
                continue
            }
            var repeated = 0
            var times: Int
            switch symbol {
            case 16:
                guard let previous = lengths.last else { throw TransferInflate.Failure.invalid }
                repeated = previous
                times = 3 + (try bits(2))
            case 17: times = 3 + (try bits(3))
            default: times = 11 + (try bits(7))
            }
            guard lengths.count + times <= literalCount + distanceCount else { throw TransferInflate.Failure.invalid }
            lengths.append(contentsOf: Array(repeating: repeated, count: times))
        }
        guard lengths[256] != 0,
              let literalCode = Huffman(lengths: Array(lengths[0..<literalCount])),
              let distanceCode = Huffman(lengths: Array(lengths[literalCount...]))
        else { throw TransferInflate.Failure.invalid }
        try codes(literalCode, distanceCode)
    }
}
