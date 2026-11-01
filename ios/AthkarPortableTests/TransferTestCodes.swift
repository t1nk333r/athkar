import Foundation

/// Transfer codes for the tests, built as the PWA's `encodeTransfer` frames them (spec/transfer/transfer-v1.md §1–§3)
/// with the zlib payload in stored blocks: any inflater reads them as it reads the PWA's compressed codes.
enum TransferTestCodes {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")

    /// The typical device's container (spec/transfer/fixtures/codec.json, first round trip) on `today`, its history
    /// the day before.
    static func typical(today: String, yesterday: String, exportedAt: String) -> String {
        #"""
        {"transfer":1,"app":"athkar-pwa","envelope":{"meta":{"format":1,"app":"athkar-pwa","exportedAt":"EXPORTED","timeZone":"Asia/Riyadh"},"adhkar":{"today":{"date":"TODAY","progress":{"morning":{"morning-01":1,"morning-02":1},"evening":{}},"targets":{"morning":{},"evening":{}},"completedAt":{"morning":null,"evening":null},"manualCompletion":{"morning":false,"evening":false}},"history":[{"date":"YESTERDAY","morning":true,"evening":true,"morningAt":"YESTERDAYT03:00:00.000Z","eveningAt":"YESTERDAYT15:00:00.000Z"}]},"reminders":{"morning":{"enabled":false},"evening":{"enabled":false},"calculationMethod":"mwl","asrSchool":"standard","lastShown":{"morning":null,"evening":null}},"preferences":{"theme":"dark","textSize":"medium","lineSpacing":"comfortable","haptics":true,"longOrder":"original","longOrderPromptAnswered":false}},"athkar":{"adhkar":{"resets":{"TODAY|morning":"TODAYT04:00:00.000Z"},"history":[{"date":"YESTERDAY","morning":true,"evening":true,"morningAt":"YESTERDAYT03:00:00.000Z","eveningAt":"YESTERDAYT15:00:00.000Z"}]},"suwar":{"date":"TODAY","selected":"kahf","read":{"kahf":{},"yasin":{},"saffat":{},"waqiah":{},"mulk":{"mulk-1-4":true,"mulk-5-8":true}},"completedAt":{"kahf":null,"yasin":null,"saffat":null,"waqiah":null,"mulk":null},"history":{"YESTERDAY":{"kahf":"YESTERDAYT18:00:00.000Z"}},"resets":{}},"tasbih":{"date":"TODAY","selected":"subhan","target":33,"counts":{"subhan":33,"c:يا حي يا قيوم":7},"firstUse":["subhan","c:يا حي يا قيوم"],"custom":["يا حي يا قيوم"],"history":{"YESTERDAY":{"hamd":100}},"resets":{}}}}
        """#
        .replacingOccurrences(of: "EXPORTED", with: exportedAt)
        .replacingOccurrences(of: "YESTERDAY", with: yesterday)
        .replacingOccurrences(of: "TODAY", with: today)
    }

    /// The one-frame text form, spaces written as "=" (`transferTextCode`).
    static func text(_ json: String, msg: String = "TEST") -> String {
        let payload = base45(zlib(Array(json.utf8)))
        return frames(payload: payload, msg: msg, chunk: max(1, payload.count))[0]
            .replacingOccurrences(of: " ", with: "=")
    }

    /// The QR frames (`transferFrames`): equal slices of at most 880 characters.
    static func frames(_ json: String, msg: String = "TEST") -> [String] {
        frames(payload: base45(zlib(Array(json.utf8))), msg: msg, chunk: 880)
    }

    private static func frames(payload: String, msg: String, chunk: Int) -> [String] {
        let characters = Array(payload)
        let count = max(1, (characters.count + chunk - 1) / chunk)
        let size = (characters.count + count - 1) / count
        return (0..<count).map { index in
            let slice = String(characters[min(characters.count, index * size)..<min(characters.count, (index + 1) * size)])
            let body = "AQ1:A:\(msg):\(index + 1):\(count):\(slice)"
            return "\(body):\(checksum(body))"
        }
    }

    /// Adler-32 of the text's UTF-16 code units, 8 uppercase hex digits.
    private static func checksum(_ text: String) -> String {
        let value = adler32(text.utf16.map(Int.init))
        let hex = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: 8 - hex.count) + hex
    }

    private static func adler32(_ values: [Int]) -> Int {
        var low = 1
        var high = 0
        for value in values {
            low = (low + value) % 65521
            high = (high + low) % 65521
        }
        return high * 65536 + low
    }

    /// RFC 1950 with RFC 1951 stored blocks.
    private static func zlib(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var index = 0
        repeat {
            let end = min(index + 65535, bytes.count)
            let length = end - index
            out.append(end == bytes.count ? 1 : 0)
            out += [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8((~length >> 8) & 0xFF)]
            out += bytes[index..<end]
            index = end
        } while index < bytes.count
        let adler = adler32(bytes.map(Int.init))
        return out + [UInt8(adler >> 24 & 0xFF), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)]
    }

    /// RFC 9285.
    private static func base45(_ bytes: [UInt8]) -> String {
        var text: [Character] = []
        var index = 0
        while index < bytes.count {
            if index + 1 < bytes.count {
                let value = Int(bytes[index]) * 256 + Int(bytes[index + 1])
                text += [alphabet[value % 45], alphabet[value / 45 % 45], alphabet[value / 2025]]
            } else {
                text += [alphabet[Int(bytes[index]) % 45], alphabet[Int(bytes[index]) / 45]]
            }
            index += 2
        }
        return String(text)
    }
}
