@testable import AthkarCore
import Foundation
import Testing

/// The PWA's `handleTransferScanText`: QR texts collected into one code's frames.
struct TransferScanTests {
    private var typical: (json: String, container: TransferJSON) {
        get throws {
            let container = try #require(try TransferFixtures.load("codec.json")["roundTrip"]?.array?.first?["expected"]?["container"])
            return (container.serialized, container)
        }
    }

    @Test func framesAssembleInAnyOrderAndRepeatsCountOnce() throws {
        let (json, container) = try typical
        // Stored blocks, so the code takes several frames.
        let frames = TransferCodec.frames(payload: TransferCodec.base45Encode(stored(Array(json.utf8))), msg: "TEST")
        let count = frames.count
        try #require(count >= 3)
        var scan = TransferScan()
        #expect(scan.scan("https://example.com") == .ignored(foreign: true))
        #expect(scan.scan(frames[count - 1]) == .progress(read: 1, count: count, restarted: false))
        #expect(scan.scan(" \(frames[count - 1])\n") == .ignored(foreign: false))
        for (read, frame) in frames.dropLast(2).enumerated() {
            #expect(scan.scan(frame) == .progress(read: read + 2, count: count, restarted: false))
        }
        guard case let .finished(.success(decoded)) = scan.scan(frames[count - 2]) else {
            Issue.record("the last frame read finishes the code")
            return
        }
        #expect(decoded.json == container)
    }

    /// `bytes` as one zlib stream of stored blocks.
    private func stored(_ bytes: [UInt8]) -> [UInt8] {
        [0x78, 0x01, 0x01, UInt8(bytes.count & 0xFF), UInt8(bytes.count >> 8), UInt8(~bytes.count & 0xFF),
         UInt8((~bytes.count >> 8) & 0xFF)] + bytes + withUnsafeBytes(of: TestDeflate.adler32(bytes).bigEndian, Array.init)
    }

    @Test func anotherCodeStartsOver() throws {
        let payload = TransferCodec.base45Encode(stored(Array(try typical.json.utf8)))
        let first = TransferCodec.frames(payload: payload, msg: "TEST")
        let second = TransferCodec.frames(payload: payload, msg: "OTHR")
        var scan = TransferScan()
        _ = scan.scan(first[0])
        _ = scan.scan(first[1])
        #expect(scan.scan(second[0]) == .progress(read: 1, count: second.count, restarted: true))
        #expect(scan.read == 1)
    }

    @Test func framesThatCanNeverBeReadHereEndTheScan() throws {
        let frame = TestDeflate.frames(try typical.json)[0]
        var damaged = Array(frame)
        damaged[20] = damaged[20] == "0" ? "1" : "0"
        var scan = TransferScan()
        #expect(scan.scan(String(damaged)) == .finished(.failure(TransferError(.corrupt, reason: "checksum"))))
        var newer = TransferScan()
        let next = frame.replacingOccurrences(of: "AQ1:", with: "AQ2:")
        #expect(newer.scan(next) == .finished(.failure(TransferError(.newer, reason: "version"))))
        // A malformed frame is someone else's QR code: ignored.
        var other = TransferScan()
        #expect(other.scan("AQ1:nothing") == .ignored(foreign: true))
        #expect(other.scan(String(repeating: "A", count: TransferCodec.maxTextLength + 1)) == .ignored(foreign: true))
    }
}
