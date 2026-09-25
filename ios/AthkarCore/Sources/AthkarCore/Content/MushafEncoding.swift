/// The ruqyah pack stores Quran text in Tanzil's Uthmani encoding. The KFGQPC HAFS font that sets it expects the King
/// Fahd Complex's encoding of the same text, which writes a few marks differently:
///
/// | Mark                         | Pack                    | KFGQPC                  |
/// |------------------------------|-------------------------|-------------------------|
/// | sukun                        | U+0652                  | U+06E1                  |
/// | rounded zero (silent letter) | U+06DF                  | U+0652                  |
/// | open tanween                 | ً ٌ + U+06ED, ٍ + U+06E2 | U+08F0, U+08F1, U+08F2  |
/// | iqlab                        | ً ٌ + U+06E2, ٍ + U+06ED | َ ُ ِ + the same meem   |
/// | undotted final ya            | ى U+0649                | ي U+064A (drawn undotted) |
/// | waqf sign                    | after a space           | on the word             |
///
/// A true alef maksura stays ى: after a bare fatha with no mark of its own, or carrying a dagger alef.
/// `content/reference/kfgqpc-hafs.ruqyah.json` holds the Complex's text of every ruqyah ayah; the tests check the
/// conversion against it.
public enum MushafEncoding {
    public static func kfgqpc(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        func scalar(_ offset: Int) -> UInt32? {
            scalars.indices.contains(index + offset) ? scalars[index + offset].value : nil
        }
        func append(_ values: UInt32...) {
            for value in values { result.append(Unicode.Scalar(value)!) }
        }

        while index < scalars.count {
            let current = scalars[index].value
            let next = scalar(1)
            switch (current, next) {
            case (0x064B, 0x06ED): append(0x08F0)
            case (0x064C, 0x06ED): append(0x08F1)
            case (0x064D, 0x06E2): append(0x08F2)
            case (0x064B, 0x06E2): append(0x064E, 0x06E2)
            case (0x064C, 0x06E2): append(0x064F, 0x06E2)
            case (0x064D, 0x06ED): append(0x0650, 0x06ED)
            default:
                switch current {
                case 0x0652:
                    append(0x06E1)
                case 0x06DF:
                    append(0x0652)
                case 0x0649:
                    let marked = next.map { (0x064B...0x0652).contains($0) } ?? false
                    let maksura = next == 0x0670 || (scalar(-1) == 0x064E && !marked)
                    append(maksura ? 0x0649 : 0x064A)
                case 0x0020 where next.map { (0x06D6...0x06DC).contains($0) } ?? false:
                    break
                default:
                    append(current)
                }
                index += 1
                continue
            }
            index += 2
        }
        return String(result)
    }
}
