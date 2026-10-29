import Foundation

/// The athkar PWA's «مسبحة» text rules, on UTF-16 code units as JavaScript reads strings: the presets, how typed
/// phrases are cleaned and matched (`cleanTasbihPhrase`, `tasbihMatchKey`, `findTasbihPhrase`, `tasbihIdentity`), the
/// typed target (`parseTasbihTarget`) and the status line (`tasbihStatusText`).
/// `spec/sessions/fixtures/tasbih-text.json` records what the PWA returns for each.
enum TasbihText {
    /// One of the picker's suggested phrases. `id` is stored and never changes; `label` is shown with tashkeel, `short`
    /// is used in labels and announcements.
    struct Preset: Equatable, Sendable {
        var id: String
        var label: String
        var short: String
    }

    /// `tasbihPresets`, in picker order.
    static let presets = [
        Preset(id: "subhan", label: "سُبْحَانَ اللَّهِ", short: "سبحان الله"),
        Preset(id: "hamd", label: "الْحَمْدُ لِلَّهِ", short: "الحمد لله"),
        Preset(id: "takbir", label: "اللَّهُ أَكْبَرُ", short: "الله أكبر"),
        Preset(id: "tahlil", label: "لَا إِلَٰهَ إِلَّا اللَّهُ", short: "لا إله إلا الله"),
        Preset(id: "istighfar", label: "أَسْتَغْفِرُ اللَّهَ", short: "أستغفر الله"),
        Preset(id: "subhan-bihamdih", label: "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ", short: "سبحان الله وبحمده"),
        Preset(id: "hawqala", label: "لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ", short: "لا حول ولا قوة إلا بالله"),
        Preset(id: "salawat", label: "اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ", short: "اللهم صل على محمد"),
    ]
    static let defaultTarget = 33
    static let maxTarget = 9999
    static let maxCustom = 8
    static let maxPhraseLength = 60
    /// The prefix of a saved phrase's key.
    static let customPrefix = "c:"

    static func preset(_ id: String) -> Preset? {
        presets.first { $0.id == id }
    }

    /// `tasbihPhrase`: a key's label and short form. A saved phrase is its own label; its short form drops tashkeel.
    static func phrase(_ key: String) -> (label: String, short: String) {
        if let preset = preset(key) { return (preset.label, preset.short) }
        let text = savedText(of: key)
        return (text, stripTashkeel(text))
    }

    static func customKey(_ phrase: String) -> String {
        customPrefix + phrase
    }

    /// Whether `key` is `c:` and a saved phrase. Read in code units: a phrase may begin with a combining mark, which
    /// Swift would join to the colon.
    static func isCustomKey(_ key: String) -> Bool {
        key.utf16.starts(with: customPrefix.utf16)
    }

    /// The phrase of a `c:` key (`key.slice(2)`).
    static func savedText(of key: String) -> String {
        string(Array(key.utf16.dropFirst(customPrefix.utf16.count)))
    }

    /// Whether two strings are the same code units, as JavaScript's `===` compares them; Swift's `==` would also
    /// equate canonically equivalent spellings.
    static func same(_ a: String, _ b: String) -> Bool {
        a.utf16.elementsEqual(b.utf16)
    }

    // MARK: Cleaning and matching

    /// `stripTashkeel`: U+064B–U+065F and U+0670 removed.
    static func stripTashkeel(_ text: String) -> String {
        string(units(text).filter { !isTashkeel($0) })
    }

    /// `tasbihMatchKey`: typed phrases compare without tashkeel, tatweel and invisible characters, with أ إ آ ٱ read as
    /// ا, ى as ي, and runs of whitespace as one space.
    static func matchKey(_ text: String) -> String {
        let folded = stripInvisibles(units(text)).filter { !isTashkeel($0) }.map { unit -> UInt16 in
            switch unit {
            case 0x0623, 0x0625, 0x0622, 0x0671: 0x0627
            case 0x0649: 0x064A
            default: unit
            }
        }
        return string(trim(collapseSpaces(folded)))
    }

    /// `cleanTasbihPhrase`: the saved spelling of a typed phrase, at most 60 UTF-16 code units, or "" when nothing is
    /// left once tashkeel and invisible characters are removed. A cut that would split a surrogate pair drops the
    /// pair's first half, where the PWA keeps it alone.
    static func cleanPhrase(_ text: String) -> String {
        var cleaned = trim(collapseSpaces(stripInvisibles(units(text))))
        if cleaned.count > maxPhraseLength {
            cleaned = Array(cleaned.prefix(maxPhraseLength))
            if let last = cleaned.last, UTF16.isLeadSurrogate(last) { cleaned.removeLast() }
            cleaned = trim(cleaned)
        }
        return trim(cleaned.filter { !isTashkeel($0) }).isEmpty ? "" : string(cleaned)
    }

    /// `findTasbihPhrase`: the preset or saved phrase a typed phrase stands for, as its key, or `nil`.
    static func findPhrase(_ text: String, custom: [String]) -> String? {
        let wanted = matchKey(text)
        if let preset = presets.first(where: { same(matchKey($0.label), wanted) }) { return preset.id }
        return custom.first { same(matchKey($0), wanted) }.map(customKey)
    }

    /// `tasbihIdentity`: the unit a stored key counts for. Keys that differ only in spelling are one unit.
    static func identity(_ key: String) -> String {
        if preset(key) != nil { return key }
        let text = savedText(of: key)
        if let preset = findPhrase(text, custom: []) { return preset }
        let match = matchKey(text)
        return match.isEmpty ? key : "m:" + match
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

    private static func isTashkeel(_ unit: UInt16) -> Bool {
        (0x064B...0x065F).contains(unit) || unit == 0x0670
    }

    /// `stripTasbihInvisibles`: ZWNJ reads as a space; tatweel, ZWSP, ZWJ, LRM, RLM and ALM are dropped; Urdu heh goal
    /// (ہ) reads as heh (ه).
    private static func stripInvisibles(_ units: [UInt16]) -> [UInt16] {
        units.compactMap { unit in
            switch unit {
            case 0x200C: 0x0020
            case 0x0640, 0x200B, 0x200D, 0x200E, 0x200F, 0x061C: nil
            case 0x06C1: 0x0647
            default: unit
            }
        }
    }

    /// JavaScript's `\s` and what `trim()` removes.
    private static func isWhitespace(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }

    /// `.replace(/\s+/g, " ")`.
    private static func collapseSpaces(_ units: [UInt16]) -> [UInt16] {
        var result: [UInt16] = []
        for unit in units {
            if isWhitespace(unit) {
                if result.last != 0x20 { result.append(0x20) }
            } else {
                result.append(unit)
            }
        }
        return result
    }

    private static func trim(_ units: [UInt16]) -> [UInt16] {
        guard let first = units.firstIndex(where: { !isWhitespace($0) }),
              let last = units.lastIndex(where: { !isWhitespace($0) })
        else { return [] }
        return Array(units[first...last])
    }
}
