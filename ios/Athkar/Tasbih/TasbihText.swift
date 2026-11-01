import AthkarCore
import Foundation

/// The athkar PWA's «مسبحة» text rules, on UTF-16 code units as JavaScript reads strings: the presets, how typed
/// phrases are cleaned and matched (`cleanTasbihPhrase`, `tasbihMatchKey`, `findTasbihPhrase`, `tasbihIdentity`), the
/// typed target (`parseTasbihTarget`) and the status line (`tasbihStatusText`). The phrase rules live in AthkarCore's
/// ``TasbihPhrase``, which the transfer import shares; these names forward to it.
/// `spec/sessions/fixtures/tasbih-text.json` records what the PWA returns for each.
enum TasbihText {
    typealias Preset = TasbihPhrase.Preset

    /// `tasbihPresets`, in picker order.
    static let presets = TasbihPhrase.presets
    static let defaultTarget = 33
    static let maxTarget = 9999
    static let maxCustom = TasbihPhrase.maxCustom
    static let maxPhraseLength = TasbihPhrase.maxPhraseLength
    /// The prefix of a saved phrase's key.
    static let customPrefix = TasbihPhrase.customPrefix

    static func preset(_ id: String) -> Preset? {
        TasbihPhrase.preset(id)
    }

    /// `tasbihPhrase`: a key's label and short form. A saved phrase is its own label; its short form drops tashkeel.
    static func phrase(_ key: String) -> (label: String, short: String) {
        if let preset = preset(key) { return (preset.label, preset.short) }
        let text = savedText(of: key)
        return (text, stripTashkeel(text))
    }

    static func customKey(_ phrase: String) -> String {
        TasbihPhrase.customKey(phrase)
    }

    /// Whether `key` is `c:` and a saved phrase.
    static func isCustomKey(_ key: String) -> Bool {
        TasbihPhrase.isCustomKey(key)
    }

    /// The phrase of a `c:` key (`key.slice(2)`).
    static func savedText(of key: String) -> String {
        TasbihPhrase.savedText(of: key)
    }

    /// Whether two strings are the same code units, as JavaScript's `===` compares them.
    static func same(_ a: String, _ b: String) -> Bool {
        TasbihPhrase.same(a, b)
    }

    // MARK: Cleaning and matching

    /// `stripTashkeel`.
    static func stripTashkeel(_ text: String) -> String {
        TasbihPhrase.stripTashkeel(text)
    }

    /// `tasbihMatchKey`.
    static func matchKey(_ text: String) -> String {
        TasbihPhrase.matchKey(text)
    }

    /// `cleanTasbihPhrase`.
    static func cleanPhrase(_ text: String) -> String {
        TasbihPhrase.cleanPhrase(text)
    }

    /// `findTasbihPhrase`.
    static func findPhrase(_ text: String, custom: [String]) -> String? {
        TasbihPhrase.findPhrase(text, custom: custom)
    }

    /// `tasbihIdentity`.
    static func identity(_ key: String) -> String {
        TasbihPhrase.identity(key)
    }

    // MARK: Target and status

    /// `parseTasbihTarget`: Arabic-Indic (٠–٩), Persian (۰–۹) and Latin digits; an integer from 1 to 9999, or `nil`.
    static func parseTarget(_ value: String) -> Int? {
        let digits = trim(units(value)).map { unit -> UInt16 in
            switch unit {
            case 0x0660...0x0669: unit - 0x0660 + 0x30
            case 0x06F0...0x06F9: unit - 0x06F0 + 0x30
            default: unit
            }
        }
        guard (1...4).contains(digits.count), digits.allSatisfy({ (0x30...0x39).contains($0) }),
              let target = Int(string(digits)), (1...maxTarget).contains(target)
        else { return nil }
        return target
    }

    /// `tasbihStatusText`: the status under the count, and whether it shows «✓». A pure function of the count and the
    /// target (`nil`: no target).
    static func status(count: Int, target: Int?) -> (text: String, check: Bool) {
        guard let target, target > 0 else { return ("بلا هدف", false) }
        if count == 0 { return ("الهدف \(ArabicFormat.number(target))", false) }
        if count < target { return ("\(ArabicFormat.number(count)) من \(ArabicFormat.number(target))", false) }
        if count == target { return ("بلغت الهدف", true) }
        let lap = (count - 1) / target + 1
        let rest = (count - 1) % target + 1
        if rest == target { return ("اكتملت الدورة \(ArabicFormat.number(lap))", true) }
        let progress = "\(ArabicFormat.number(rest)) من \(ArabicFormat.number(target))"
        return ("الدورة \(ArabicFormat.number(lap)): \(progress)", false)
    }

    // MARK: UTF-16

    private static func units(_ text: String) -> [UInt16] { Array(text.utf16) }

    private static func string(_ units: [UInt16]) -> String { String(decoding: units, as: UTF16.self) }

    /// JavaScript's `\s` and what `trim()` removes.
    private static func isWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    private static func trim(_ units: [UInt16]) -> [UInt16] {
        guard let first = units.firstIndex(where: { !isWhitespace($0) }),
              let last = units.lastIndex(where: { !isWhitespace($0) })
        else { return [] }
        return Array(units[first...last])
    }
}
