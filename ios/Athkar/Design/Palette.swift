import SwiftUI

/// The PWAs' CSS colour variables: a shared base per colour scheme, with the accent family of the deck on screen
/// (the athkar PWA's morning rose, its default teal for the evening, and the ruqyah PWA's blue).
struct Palette: Sendable {
    var background: Color
    var backgroundGlow: Color
    var surface: Color
    var surfaceRaised: Color
    var textPrimary: Color
    var textSecondary: Color
    var reference: Color
    var accent: Color
    var accentStrong: Color
    var accentSoft: Color
    var border: Color
    var divider: Color
    var completed: Color
    var completedSoft: Color
    var warning: Color
    var warningSoft: Color

    static func resolve(_ deck: DeckID, _ scheme: ColorScheme) -> Palette {
        var palette = scheme == .dark ? darkBase : lightBase
        switch (deck, scheme) {
        case (.morning, .dark):
            palette.accent(0xef8d86, strong: 0xffc1bb, soft: 0x4c302f, divider: 0x704b4a, reference: 0x8cc7ef,
                           glow: 0x3b3038)
        case (.morning, _):
            palette.accent(0xb85f59, strong: 0x914640, soft: 0xf7e6e3, divider: 0xe6c2bf, reference: 0x143872,
                           glow: 0xfaeeee)
        case (.ruqyah, .dark):
            palette.accent(0x6fa8dc, strong: 0xa6cdf0, soft: 0x1d3852, divider: 0x52657a, reference: 0x28b6d2,
                           glow: 0x24384a)
        case (.ruqyah, _):
            palette.accent(0x3f6ea8, strong: 0x2f5a8f, soft: 0xe4ecf7, divider: 0xc7d3e2, reference: 0x15557a,
                           glow: 0xeef2f7)
        case (.evening, _):
            break
        }
        return palette
    }

    private mutating func accent(_ accent: UInt32, strong: UInt32, soft: UInt32, divider: UInt32, reference: UInt32,
                                 glow: UInt32) {
        self.accent = Color(hex: accent)
        accentStrong = Color(hex: strong)
        accentSoft = Color(hex: soft)
        self.divider = Color(hex: divider)
        self.reference = Color(hex: reference)
        backgroundGlow = Color(hex: glow)
    }

    private static let lightBase = Palette(
        background: Color(hex: 0xf7f5ef), backgroundGlow: Color(hex: 0xeef7f7), surface: Color(hex: 0xfffefa),
        surfaceRaised: Color(hex: 0xffffff), textPrimary: Color(hex: 0x18232d), textSecondary: Color(hex: 0x69747d),
        reference: Color(hex: 0x15557a), accent: Color(hex: 0x137d91), accentStrong: Color(hex: 0x0d6879),
        accentSoft: Color(hex: 0xe2f1f1), border: Color(hex: 0xdeddd5), divider: Color(hex: 0xc9d7d9),
        completed: Color(hex: 0x327557), completedSoft: Color(hex: 0xe8f2e9), warning: Color(hex: 0x8a622c),
        warningSoft: Color(hex: 0xfbf1dd))

    private static let darkBase = Palette(
        background: Color(hex: 0x202c38), backgroundGlow: Color(hex: 0x263b47), surface: Color(hex: 0x293946),
        surfaceRaised: Color(hex: 0x30414f), textPrimary: Color(hex: 0xf6f3ec), textSecondary: Color(hex: 0xaeb8c1),
        reference: Color(hex: 0x28b6d2), accent: Color(hex: 0x23b4cf), accentStrong: Color(hex: 0x6bd2e2),
        accentSoft: Color(hex: 0x183f4a), border: Color(hex: 0x435361), divider: Color(hex: 0x536775),
        completed: Color(hex: 0x70c58d), completedSoft: Color(hex: 0x254838), warning: Color(hex: 0xe0bc70),
        warningSoft: Color(hex: 0x4b4028))
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
    @Entry var palette = Palette.resolve(.morning, .light)
}
