import AthkarCore
import SwiftUI
import UIKit

/// Reading sizes from the PWAs' CSS in points: `clamp(min rem, vw, max rem)` with 1rem = 16pt and 1vw = 1% of the
/// window width, then scaled by Dynamic Type relative to its default size, so the three text-size settings stay
/// three steps and still follow the system text size.
struct ReadingMetrics: Equatable, Sendable {
    var viewportWidth: CGFloat
    var textSize: TextSize
    var lineSpacing: LineSpacing
    /// `UIFontMetrics` body scaling for the current Dynamic Type size; 1 at the default size.
    var typeScale: CGFloat

    static func typeScale(for size: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        return UIFontMetrics(forTextStyle: .body).scaledValue(for: 100, compatibleWith: traits) / 100
    }

    private func clamp(_ minRem: CGFloat, _ vw: CGFloat, _ maxRem: CGFloat) -> CGFloat {
        min(max(minRem * 16, viewportWidth * vw / 100), maxRem * 16) * typeScale
    }

    private func bySize(_ small: (CGFloat, CGFloat, CGFloat), _ medium: (CGFloat, CGFloat, CGFloat),
                        _ large: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        let value = switch textSize {
        case .small: small
        case .medium: medium
        case .large: large
        }
        return clamp(value.0, value.1, value.2)
    }

    private func bySpacing(_ compact: CGFloat, _ comfortable: CGFloat, _ wide: CGFloat) -> CGFloat {
        switch lineSpacing {
        case .compact: compact
        case .comfortable: comfortable
        case .wide: wide
        }
    }

    // MARK: Athkar PWA (`--dhikr-text-size` and friends)

    var dhikrText: CGFloat { bySize((1.08, 4.7, 1.5), (1.24, 5.35, 1.72), (1.4, 6, 1.95)) }
    var detailText: CGFloat { bySize((0.9, 3.7, 1.12), (1, 4.1, 1.27), (1.08, 4.5, 1.4)) }
    var quranPrefix: CGFloat { bySize((1.05, 4.45, 1.4), (1.2, 5, 1.58), (1.35, 5.75, 1.82)) }
    var quranText: CGFloat { bySize((1.15, 5, 1.62), (1.3, 5.6, 1.82), (1.45, 6.4, 2.12)) }
    var dhikrLineHeight: CGFloat { bySpacing(1.7, 1.95, 2.16) }
    var detailLineHeight: CGFloat { bySpacing(1.62, 1.85, 2.05) }
    var quranLineHeight: CGFloat { bySpacing(1.82, 2.05, 2.3) }

    /// The body of an adhkar card at one `fitCardContent` step.
    struct AdhkarBody: Equatable {
        var text: CGFloat
        var textLineHeight: CGFloat
        var detail: CGFloat
        var detailLineHeight: CGFloat
        var detailsGap: CGFloat
        var detailsTop: CGFloat
    }

    /// `fitCardContent`: Quran cards keep their size (and scroll if they must); other cards may step down to
    /// `.is-content-dense` then `.is-content-tight`. A step never enlarges text (the CSS dense sizes are fixed and
    /// would grow text the small setting made smaller).
    func adhkarBodies(quran: Bool) -> [AdhkarBody] {
        let normal = AdhkarBody(
            text: quran ? quranText : dhikrText, textLineHeight: quran ? quranLineHeight : dhikrLineHeight,
            detail: detailText, detailLineHeight: detailLineHeight, detailsGap: 11.2, detailsTop: 18.4)
        guard !quran else { return [normal] }
        let dense = AdhkarBody(
            text: min(normal.text, clamp(1.12, 4.9, 1.54)), textLineHeight: min(normal.textLineHeight, 1.76),
            detail: min(normal.detail, clamp(0.94, 3.85, 1.1)), detailLineHeight: min(normal.detailLineHeight, 1.62),
            detailsGap: 7.2, detailsTop: 10.9)
        let tight = AdhkarBody(
            text: min(normal.text, clamp(1.08, 4.7, 1.48)), textLineHeight: min(normal.textLineHeight, 1.65),
            detail: min(normal.detail, clamp(0.9, 3.7, 1.04)), detailLineHeight: min(normal.detailLineHeight, 1.5),
            detailsGap: 4.8, detailsTop: 8)
        return [normal, dense, tight]
    }

    // MARK: Ruqyah PWA (`--quran-text-size`, `fitCardText`)

    var ruqyahText: CGFloat { bySize((1.1, 4.7, 1.55), (1.26, 5.4, 1.78), (1.42, 6.2, 2.05)) }
    var ruqyahLineHeight: CGFloat { bySpacing(1.82, 2.05, 2.32) }
    var ruqyahSurah: CGFloat { clamp(1.02, 4.3, 1.3) }

    /// One `fitCardText` step: `.is-fit-N` scales the text and takes `lead` off the line height.
    struct RuqyahStep: Equatable {
        var scale: CGFloat
        var lead: CGFloat
    }

    /// Unfitted, then `.is-fit-1` … `.is-fit-5`, then two native steps: at the same width iOS sets these pages about
    /// one step taller than the PWA in Chromium, so with wide spacing and large text on a 375 pt screen some needed
    /// more than step 5; `(0.66, 0.54)` and `(0.62, 0.54)` keep them from scrolling. Before iOS 26 a line can be no
    /// shorter than the font's natural line height (1.685em for Uthman Taha), so the last steps save less height
    /// than the PWA's `line-height`; two more steps make up for it there.
    static var ruqyahSteps: [RuqyahStep] {
        let steps = [
            RuqyahStep(scale: 1, lead: 0), RuqyahStep(scale: 0.94, lead: 0.12), RuqyahStep(scale: 0.88, lead: 0.24),
            RuqyahStep(scale: 0.82, lead: 0.34), RuqyahStep(scale: 0.76, lead: 0.44), RuqyahStep(scale: 0.70, lead: 0.54),
            RuqyahStep(scale: 0.66, lead: 0.54), RuqyahStep(scale: 0.62, lead: 0.54),
        ]
        if #available(iOS 26.0, *) { return steps }
        return steps + [RuqyahStep(scale: 0.58, lead: 0.54), RuqyahStep(scale: 0.54, lead: 0.54)]
    }
}

extension EnvironmentValues {
    @Entry var readingMetrics = ReadingMetrics(viewportWidth: 390, textSize: .medium, lineSpacing: .comfortable,
                                               typeScale: 1)
}

/// The reading faces: KFGQPC Uthman Taha Naskh for the adhkar's Quran text and the ayah markers (bundled, as in both
/// PWAs), KFGQPC HAFS Uthmanic Script for the ruqyah pages, and the system Arabic face for other adhkar (what the
/// athkar PWA's Naskh font stack falls back to on iOS).
enum ReadingFont {
    /// Which face a text is set in, for its natural line height.
    enum Face {
        case system, quran, mushaf
    }

    static let quranName = "KFGQPCUthmanTahaNaskh"
    /// The ruqyah text is Uthmani script with marks Uthman Taha has no glyphs for (ٱ, ۭ, ۢ, ۥ, ۦ, ۟, waqf signs). Core
    /// Text sets such a letter in a fallback font, which breaks its join with the letter before; HAFS covers them all.
    static let mushafName = "KFGQPCHAFSUthmanicScript-Regula"

    static func quran(_ size: CGFloat) -> Font { .custom(quranName, fixedSize: size) }

    static func mushaf(_ size: CGFloat) -> Font { .custom(mushafName, fixedSize: size) }

    static func dhikr(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }

    static func detail(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }

    static func naturalLineHeight(_ face: Face, size: CGFloat) -> CGFloat {
        switch face {
        case .system: UIFont.systemFont(ofSize: size, weight: .medium).lineHeight
        case .quran: UIFont(name: quranName, size: size)?.lineHeight ?? size * 1.685
        case .mushaf: UIFont(name: mushafName, size: size)?.lineHeight ?? size * 1.758
        }
    }
}

extension View {
    /// CSS `line-height: <multiple>` for text set at `size` points: exact from iOS 26, otherwise the difference to the
    /// font's natural line height as extra spacing (never negative, so tight steps are looser there).
    @ViewBuilder
    func cssLineHeight(_ multiple: CGFloat, size: CGFloat, face: ReadingFont.Face) -> some View {
        if #available(iOS 26.0, *) {
            lineHeight(.exact(points: multiple * size))
        } else {
            lineSpacing(max(0, multiple * size - ReadingFont.naturalLineHeight(face, size: size)))
        }
    }
}
