@testable import AthkarCore
import Foundation
import Testing

/// One `cases` entry of `spec/transfer/fixtures/codec.json`.
struct TransferCodecCase: Sendable, CustomTestStringConvertible {
    let name: String
    let input: TransferJSON
    let result: TransferJSON

    var testDescription: String { name }

    static var all: [TransferCodecCase] {
        get throws {
            try (TransferFixtures.load("codec.json")["cases"]?.array ?? []).map {
                TransferCodecCase(name: $0["name"]!.string!, input: $0["input"]!, result: $0["result"]!)
            }
        }
    }
}

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

struct TransferCodecFixtureTests {
    @Test func everyDecodeCaseIsPresent() throws {
        #expect(try TransferCodecCase.all.count == 58)
    }

    @Test(arguments: try TransferCodecCase.all)
    func decodesAsThePWA(_ fixture: TransferCodecCase) throws {
        let result: Result<TransferContainer, TransferError>
        if let code = fixture.input["code"]?.string {
            result = TransferCodec.decode(text: code)
        } else if let frames = fixture.input["frames"]?.array {
            result = TransferCodec.decode(frames: frames.map { $0.string! })
        } else {
            result = TransferCodec.decode(fileText: try #require(fixture.input["file"]?.string))
        }
        switch result {
        case let .success(container):
            #expect(fixture.result["ok"] == .bool(true))
            #expect(fixture.result["source"]?.string == container.source.rawValue)
            var expected = fixture.result["container"]
            // The generator writes this for the typical device's container, the first round trip's.
            if expected == .string("equals input container") {
                expected = try TransferFixtures.load("codec.json")["roundTrip"]?.array?.first?["expected"]?["container"]
            }
            #expect(container.json == expected)
        case let .failure(error):
            #expect(fixture.result["ok"] == .bool(false))
            #expect(error.kind.rawValue == fixture.result["error"]?.string)
            #expect(error.reason == fixture.result["reason"]?.string)
            #expect(error.path == fixture.result["path"]?.string)
        }
    }

    @Test func base45MatchesRFC9285() throws {
        let fixture = try TransferFixtures.load("codec.json")
        for vector in fixture["base45"]?.array ?? [] {
            let bytes = Array(vector["text"]!.string!.utf8)
            #expect(hex(bytes) == vector["bytes"]?.string)
            #expect(TransferCodec.base45Encode(bytes) == vector["encoded"]?.string)
            #expect(TransferCodec.base45Decode(vector["encoded"]!.string!) == bytes)
        }
        for vector in fixture["base45Invalid"]?.array ?? [] {
            #expect(TransferCodec.base45Decode(vector["text"]!.string!) == nil, "\(vector["text"]!.string!)")
        }
    }

    @Test func frameChecksumIsAdler32OfTheText() throws {
        for vector in try TransferFixtures.load("codec.json")["checksum"]?.array ?? [] {
            #expect(TransferCodec.checksum(vector["text"]!.string!) == vector["checksum"]?.string)
        }
    }

    @Test func framesSplitThePayloadAsThePWA() throws {
        let fixture = try #require(try TransferFixtures.load("codec.json")["frames"])
        let alphabet = String(decoding: TransferCodec.base45Alphabet, as: UTF8.self)
        let length = try #require(fixture["payloadLength"]?.integer)
        let payload = String(String(repeating: alphabet, count: length / alphabet.count + 1).prefix(length))
        let frames = TransferCodec.frames(payload: payload, msg: fixture["msg"]!.string!)
        #expect(frames == fixture["frames"]?.array?.map { $0.string! })
    }

    /// Each `roundTrip` container, written as encodeTransfer writes it (here with this test's own zlib writer), reads
    /// back unchanged from the text form and from its QR frames.
    @Test func roundTripsThroughTextAndFrames() throws {
        for entry in try TransferFixtures.load("codec.json")["roundTrip"]?.array ?? [] {
            let container = try #require(entry["expected"]?["container"])
            let json = container.serialized
            #expect(json.utf8.count == entry["expected"]?["jsonBytes"]?.integer, "\(entry["name"]!.string!)")
            let text = TestDeflate.textCode(json)
            #expect(text.utf16.count <= TransferCodec.maxTextLength)
            #expect(try TransferCodec.decode(text: text).get().json == container)
            let frames = TestDeflate.frames(json)
            #expect(try TransferCodec.decode(frames: frames.reversed()).get().json == container)
        }
    }

    /// The PWA's `inflateBounds`: a bomb is refused at the cap, whatever its inflated size.
    @Test func deflateBombsStopAtTheCap() throws {
        for entry in try TransferFixtures.load("codec.json")["inflateBounds"]?.array ?? [] {
            let size = try #require(entry["inflatedSize"]?.integer)
            #expect(entry["cap"]?.integer == TransferInflate.cap)
            let bomb = TestDeflate.zeros(size)
            #expect(TransferInflate.inflatePortable(bomb, cap: TransferInflate.cap) == .failure(.cap))
            #expect(TransferInflate.inflate(bomb) == .failure(.cap))
            #expect(entry["result"]?["reason"]?.string == TransferInflate.Failure.cap.reason)
        }
        // Just under the cap is fine, one byte over is not.
        let fits = TestDeflate.zeros(TransferInflate.cap)
        #expect(TransferInflate.inflate(fits) == .success([UInt8](repeating: 0, count: TransferInflate.cap)))
        #expect(TransferInflate.inflate(TestDeflate.zeros(TransferInflate.cap + 1)) == .failure(.cap))
    }

    @Test func inflaterReadsStoredFixedAndDynamicBlocks() throws {
        let text = Array(#"{"a":"مرحبا مرحبا مرحبا","b":[1,2,3,1,2,3,1,2,3]}"#.utf8)
        // Stored: one final block.
        let stored = [0x78, 0x01, 0x01, UInt8(text.count & 0xFF), UInt8(text.count >> 8),
                      UInt8(~text.count & 0xFF), UInt8((~text.count >> 8) & 0xFF)] + text
            + withUnsafeBytes(of: TestDeflate.adler32(text).bigEndian, Array.init)
        #expect(TransferInflate.inflatePortable(stored, cap: TransferInflate.cap) == .success(text))
        #expect(TransferInflate.inflatePortable(TestDeflate.zlib(text), cap: TransferInflate.cap) == .success(text))
        // Fixed Huffman (zlib level 9, from Python's zlib) and dynamic Huffman (the same, on a longer text).
        let fixed: [UInt8] = [0x78, 0xDA, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xC8, 0xC0, 0x20, 0xCB, 0xF3, 0x8B, 0x72, 0x52,
                              0xB8, 0x00, 0xAE, 0x8D, 0x0B, 0x03]
        let hello = Array("hello hello hello hello world\n".utf8)
        #expect(TransferInflate.inflatePortable(fixed, cap: TransferInflate.cap) == .success(hello))
        #expect(TransferInflate.inflate(fixed) == .success(hello))
        let dynamic: [UInt8] = [
            0x78, 0xDA, 0x9D, 0xCB, 0xD7, 0x19, 0x83, 0x20, 0x00, 0x45, 0xE1, 0x55, 0x6E, 0x16, 0xC8, 0x97, 0x5E, 0xB6, 0xC8,
            0x83, 0x0B, 0x80, 0xD2, 0x94, 0x22, 0x48, 0x11, 0xA6, 0x0F, 0x2B, 0x24, 0xCF, 0xE7, 0x3F, 0x83, 0x64, 0xF0, 0x49,
            0x8D, 0x0B, 0x68, 0x70, 0xC5, 0x82, 0xBB, 0x1D, 0x73, 0x32, 0xEB, 0x06, 0x97, 0x59, 0x40, 0xEC, 0x59, 0x93, 0x56,
            0x31, 0x39, 0x71, 0xC4, 0xF0, 0x0B, 0xFE, 0x90, 0xEE, 0x4C, 0x05, 0xED, 0xA8, 0xA8, 0x28, 0xC1, 0x55, 0x66, 0x3D,
            0x35, 0x66, 0xA1, 0x95, 0x4F, 0x2E, 0xF4, 0x57, 0x6C, 0x07, 0x9C, 0xCE, 0x97, 0xEB, 0xED, 0xFE, 0x78, 0xBE, 0xDE,
            0x20, 0x74, 0x9C, 0x18, 0x17, 0x52, 0xCD, 0x8B, 0x36, 0xD6, 0xAD, 0x3E, 0x6C, 0x31, 0xE5, 0xB2, 0xD7, 0xF6, 0x4F,
            0xF9, 0x02, 0x52, 0xFE, 0x52, 0x83,
        ]
        let pangrams = Array(("The quick brown fox jumps over the lazy dog. " + "The quick brown fox jumps over the lazy dog. "
            + "Pack my box with five dozen liquor jugs! 0123456789 "
            + String(repeating: "abcdefghijklmnopqrstuvwxyz", count: 3)).utf8)
        #expect(dynamic[2] >> 1 & 3 == 2)
        #expect(TransferInflate.inflatePortable(dynamic, cap: TransferInflate.cap) == .success(pangrams))
        #expect(TransferInflate.inflate(dynamic) == .success(pangrams))
    }

    @Test func refusesBrokenZlibStreams() {
        let good = TestDeflate.zlib(Array("transfer".utf8))
        var badAdler = good
        badAdler[badAdler.count - 1] ^= 1
        #expect(TransferInflate.inflate(badAdler) == .failure(.invalid))
        #expect(TransferInflate.inflate(good + [0]) == .failure(.invalid))
        #expect(TransferInflate.inflate(Array(good.dropLast(5))) == .failure(.invalid))
        #expect(TransferInflate.inflate([0x78, 0x9C]) == .failure(.invalid))
        var badHeader = good
        badHeader[1] = 0x02
        #expect(TransferInflate.inflate(badHeader) == .failure(.invalid))
    }
}

struct TransferFileTests {
    @Test func aFileOverTheSizeBoundIsRefusedBeforeReading() {
        let data = Data(repeating: 0x20, count: TransferCodec.maxFileBytes + 1)
        #expect(TransferCodec.decode(fileData: data) == .failure(TransferError(.tooLong)))
    }

    @Test func aFileWithTwoByteOrderMarksReadsAsTheBrowserReadsIt() throws {
        let file = try RepoFile.data("spec/backup/examples/athkar-pwa.athkarbackup")
        let marked = Data([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF]) + file
        let container = try TransferCodec.decode(fileData: marked).get()
        #expect(container.source == .backup)
        #expect(container.athkar == nil)
        #expect(container.envelope.reminders?.location == nil)
    }

    @Test func aRuqyahBackupIsAnotherApp() throws {
        let file = try RepoFile.data("spec/backup/examples/ruqyah-pwa.athkarbackup")
        let error = TransferError(.wrongApp, reason: "app", path: "envelope/meta/app")
        #expect(TransferCodec.decode(fileData: file) == .failure(error))
    }
}

