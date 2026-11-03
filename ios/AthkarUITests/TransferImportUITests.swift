import XCTest

/// «استيراد من تطبيق الويب»: a code from the athkar PWA pasted in Settings, reviewed, imported and shown on the home
/// screen.
final class TransferImportUITests: DeckTestCase {
    func testAPastedCodeIsReviewedThenImported() throws {
        launch()
        openSettings()
        let entry = reveal(app.buttons["settings.transferImport"])
        XCTAssertTrue(entry.exists, "«استيراد من تطبيق الويب»")
        entry.tap()
        XCTAssertTrue(app.navigationBars["استلام التقدّم"].waitForExistence(timeout: 5))

        let field = app.textViews["transfer.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["transfer.continue"].isEnabled)
        field.tap()
        field.typeText("hello")
        app.buttons["transfer.continue"].tap()
        XCTAssertTrue(app.staticTexts["transfer.code.error"].waitForExistence(timeout: 3))

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
        XCTAssertTrue(wait { !self.app.staticTexts["transfer.code.error"].exists }, "editing clears the error")
        field.typeText(TransferUITestCode.morningMarkedComplete())
        app.buttons["transfer.continue"].tap()

        XCTAssertTrue(app.navigationBars["المراجعة"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["سيُضاف إلى هذا الجهاز:"].exists)
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "يُسجَّل الورد مكتملًا")).firstMatch
        XCTAssertTrue(row.exists, "«أذكار الصباح اليوم» row")
        let confirm = app.buttons["transfer.confirm"]
        XCTAssertEqual(confirm.label, "إضافة التقدّم")
        confirm.tap()

        XCTAssertTrue(app.staticTexts["transfer.result.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["transfer.result.title"].label, "نُقل التقدّم إلى هذا الجهاز")
        app.buttons["transfer.done"].tap()
        XCTAssertTrue(wait { !self.app.navigationBars["استلام التقدّم"].exists && !self.app.navigationBars["تمّ النقل"].exists })
        closeSettings()
        expectLabel(summary, "اكتملت أذكار الصباح خارج التطبيق")
    }
}

/// A PWA transfer code for the tests, in the text form `encodeTransfer` writes (spec/transfer/transfer-v1.md §1–§3):
/// greedy LZ77 with the fixed Huffman code keeps it short to type.
enum TransferUITestCode {
    /// Today (this device's date) with «أذكار الصباح» marked complete outside the app a minute ago.
    static func morningMarkedComplete(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)
        let instant = ISO8601DateFormatter()
        instant.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let at = instant.string(from: now.addingTimeInterval(-60))
        let json = #"""
        {"transfer":1,"app":"athkar-pwa","envelope":{"meta":{"format":1,"app":"athkar-pwa","exportedAt":"AT","timeZone":"Asia/Riyadh"},"adhkar":{"today":{"date":"TODAY","progress":{"morning":{},"evening":{}},"targets":{"morning":{},"evening":{}},"completedAt":{"morning":"AT","evening":null},"manualCompletion":{"morning":true,"evening":false}},"history":[]},"reminders":{"morning":{"enabled":false},"evening":{"enabled":false},"calculationMethod":"mwl","asrSchool":"standard","lastShown":{"morning":null,"evening":null}},"preferences":{"theme":"system","textSize":"medium","lineSpacing":"comfortable","haptics":true,"longOrder":"original","longOrderPromptAnswered":false}},"athkar":{"adhkar":{"resets":{},"history":[]},"suwar":{"date":"TODAY","selected":"kahf","read":{},"completedAt":{},"history":{},"resets":{}},"tasbih":{"date":"TODAY","selected":"subhan","target":33,"counts":{},"firstUse":[],"custom":[],"history":{},"resets":{}}}}
        """#
        .replacingOccurrences(of: "TODAY", with: today)
        .replacingOccurrences(of: "AT", with: at)
        let payload = base45(zlib(Array(json.utf8)))
        let body = "AQ1:A:TEST:1:1:\(payload)"
        return "\(body):\(checksum(body))".replacingOccurrences(of: " ", with: "=")
    }

    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")

    private static func checksum(_ text: String) -> String {
        let hex = String(adler32(text.utf16.map(Int.init)), radix: 16, uppercase: true)
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

    // MARK: zlib (RFC 1950/1951, one fixed-Huffman block)

    private struct BitWriter {
        var bytes: [UInt8] = []
        var buffer = 0
        var count = 0

        mutating func write(_ value: Int, bits: Int) {
            buffer |= value << count
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

    private static func zlib(_ bytes: [UInt8]) -> [UInt8] {
        var writer = BitWriter()
        writer.write(1, bits: 1)
        writer.write(1, bits: 2)
        var heads: [Int: [Int]] = [:]
        func hash(_ at: Int) -> Int { Int(bytes[at]) << 16 | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) }
        var index = 0
        while index < bytes.count {
            var best = (length: 0, distance: 0)
            if index + 3 <= bytes.count {
                for candidate in (heads[hash(index)] ?? []).reversed().prefix(64) {
                    var length = 0
                    while length < 258, index + length < bytes.count, bytes[candidate + length] == bytes[index + length] {
                        length += 1
                    }
                    if length > best.length { best = (length, index - candidate) }
                }
            }
            let step = best.length >= 3 ? best.length : 1
            if best.length >= 3 {
                let lengthCode = lengthBase.lastIndex { $0 <= best.length }!
                literal(257 + lengthCode, into: &writer)
                writer.write(best.length - lengthBase[lengthCode], bits: lengthExtra[lengthCode])
                let distanceCode = distanceBase.lastIndex { $0 <= best.distance }!
                writer.code(distanceCode, bits: 5)
                writer.write(best.distance - distanceBase[distanceCode], bits: distanceExtra[distanceCode])
            } else {
                literal(Int(bytes[index]), into: &writer)
            }
            for position in index..<(index + step) where position + 3 <= bytes.count {
                heads[hash(position), default: []].append(position)
            }
            index += step
        }
        literal(256, into: &writer)
        if writer.count > 0 { writer.bytes.append(UInt8(writer.buffer & 0xFF)) }
        let adler = adler32(bytes.map(Int.init))
        return [0x78, 0x01] + writer.bytes
            + [UInt8(adler >> 24 & 0xFF), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)]
    }
}
