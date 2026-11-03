import SwiftUI

/// The one corner radius the few rounded boxes share: the counter, filled buttons, fields and panels. Text, tabs and
/// list rows sit on the page between ``Rule``s instead. A box drawn inside another with a small gap takes the gap off,
/// so the two curves stay parallel. Round icon buttons stay circles.
enum Corner {
    static let radius: CGFloat = 10

    static var box: RoundedRectangle { inner(gap: 0) }

    /// A box drawn `gap` points inside a ``box``.
    static func inner(gap: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: max(radius - gap, 0), style: .continuous)
    }
}

/// The line that separates the parts of a screen: the PWA's `border-block-*: 1px solid var(--border)`.
struct Rule: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle().fill(palette.border).frame(height: 1).accessibilityHidden(true)
    }
}

/// `.progress-track`: a 2 pt line, `value` of `total` filled in `tint` from the leading edge.
struct ProgressLine: View {
    var value: Double
    var total: Double
    var tint: Color
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(tint)
                .frame(width: proxy.size.width * min(max(value / max(total, 1), 0), 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.border)
        }
        .frame(height: 2)
    }
}
