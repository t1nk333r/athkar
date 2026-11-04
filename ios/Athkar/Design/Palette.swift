import SwiftUI

/// The PWA's CSS colour variables, one set per colour scheme: paper and ink, with one accent for every deck. The
/// accent marks the selected tab, the progress line, the counter and a screen's main button; rules (`border`) separate the parts
/// of a screen instead of boxes.
struct Palette: Sendable {
    /// The scheme these colours are for. A sheet takes the palette from the screen that opened it, and the sheet's
    /// own `colorScheme` can lag behind a theme changed while it is open, so an asset that has light and dark
    /// versions picks by this.
    var colorScheme: ColorScheme
    var background: Color
    var surface: Color
    var surfaceRaised: Color
    var textPrimary: Color
    var textSecondary: Color
    var reference: Color
    var accent: Color
    var accentStrong: Color
    var accentSoft: Color
    /// Text and symbols on an `accent` or `completed` fill.
    var onAccent: Color
    var border: Color
    var divider: Color
    var completed: Color
    var completedSoft: Color
    var warning: Color
    var warningSoft: Color

    static func resolve(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? dark : light
    }

    private static let light = Palette(
        colorScheme: .light,
        background: Color(hex: 0xf5f1e8), surface: Color(hex: 0xf9f6ef), surfaceRaised: Color(hex: 0xfdfbf6),
        textPrimary: Color(hex: 0x1e1c17), textSecondary: Color(hex: 0x6d675b), reference: Color(hex: 0x4f4a40),
        accent: Color(hex: 0x8f3424), accentStrong: Color(hex: 0x74281b), accentSoft: Color(hex: 0xefe1d6),
        onAccent: Color(hex: 0xfbf7f0), border: Color(hex: 0xddd6c7), divider: Color(hex: 0xddd6c7),
        completed: Color(hex: 0x2e6a4e), completedSoft: Color(hex: 0xe2ebdf), warning: Color(hex: 0x87602a),
        warningSoft: Color(hex: 0xf3e8d2))

    private static let dark = Palette(
        colorScheme: .dark,
        background: Color(hex: 0x161512), surface: Color(hex: 0x1f1d1a), surfaceRaised: Color(hex: 0x26241f),
        textPrimary: Color(hex: 0xece6d9), textSecondary: Color(hex: 0x9d978b), reference: Color(hex: 0xb9b2a5),
        accent: Color(hex: 0xdb8f71), accentStrong: Color(hex: 0xf0b59c), accentSoft: Color(hex: 0x3b2a21),
        onAccent: Color(hex: 0x1b130e), border: Color(hex: 0x3a3731), divider: Color(hex: 0x3a3731),
        completed: Color(hex: 0x82c49a), completedSoft: Color(hex: 0x1e3227), warning: Color(hex: 0xe0bc70),
        warningSoft: Color(hex: 0x3a3121))
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }

    /// CSS `color-mix(in srgb, self fraction, other)`.
    func mixed(_ fraction: Double, with other: Color) -> Color {
        let resolvedSelf = UIColor(self)
        let resolvedOther = UIColor(other)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        resolvedSelf.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        resolvedOther.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let p = CGFloat(fraction)
        return Color(.sRGB, red: r1 * p + r2 * (1 - p), green: g1 * p + g2 * (1 - p), blue: b1 * p + b2 * (1 - p),
                     opacity: a1 * p + a2 * (1 - p))
    }
}

extension EnvironmentValues {
    @Entry var palette = Palette.resolve(.light)
}
