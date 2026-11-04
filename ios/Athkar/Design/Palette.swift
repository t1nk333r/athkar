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
        background: Color(hex: 0xf6f2eb), surface: Color(hex: 0xf9f6f0), surfaceRaised: Color(hex: 0xfcfaf6),
        textPrimary: Color(hex: 0x38332c), textSecondary: Color(hex: 0x736b60), reference: Color(hex: 0x5a544a),
        accent: Color(hex: 0xa14f3c), accentStrong: Color(hex: 0x8a4130), accentSoft: Color(hex: 0xf2e6dd),
        onAccent: Color(hex: 0xfcf8f3), border: Color(hex: 0xe5dfd3), divider: Color(hex: 0xe5dfd3),
        completed: Color(hex: 0x3f7158), completedSoft: Color(hex: 0xe6ede3), warning: Color(hex: 0x82602f),
        warningSoft: Color(hex: 0xf4ebda))

    private static let dark = Palette(
        colorScheme: .dark,
        background: Color(hex: 0x1d1c19), surface: Color(hex: 0x24221f), surfaceRaised: Color(hex: 0x2a2824),
        textPrimary: Color(hex: 0xe0dacd), textSecondary: Color(hex: 0xa29c90), reference: Color(hex: 0xbab3a6),
        accent: Color(hex: 0xd29a80), accentStrong: Color(hex: 0xe6b8a3), accentSoft: Color(hex: 0x3a2e27),
        onAccent: Color(hex: 0x211813), border: Color(hex: 0x383530), divider: Color(hex: 0x383530),
        completed: Color(hex: 0x8bbd9d), completedSoft: Color(hex: 0x24352b), warning: Color(hex: 0xd8bb80),
        warningSoft: Color(hex: 0x393226))
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
