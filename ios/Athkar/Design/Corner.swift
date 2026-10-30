import SwiftUI

/// The one corner radius every rounded box shares: cards, panels, list rows, buttons, chips and badges. A box shorter
/// than twice the radius comes out as a pill. A box drawn inside another with a small gap takes the gap off, so the
/// two curves stay parallel. Thin bars and lines stay capsules, and round icon buttons stay circles.
enum Corner {
    static let radius: CGFloat = 16

    static var box: RoundedRectangle { inner(gap: 0) }

    /// A box drawn `gap` points inside a ``box``.
    static func inner(gap: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: max(radius - gap, 0), style: .continuous)
    }
}
