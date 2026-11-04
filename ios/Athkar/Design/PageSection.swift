import SwiftUI

/// A list section on the page, like the PWA's settings sheet: its title in the secondary ink, rows on the paper with
/// no box around them, and a ``Rule``-coloured line between rows. The list it sits in takes ``pageList()``.
struct PageSection<Content: View, Footer: View>: View {
    private let title: String?
    private let content: Content
    private let footer: Footer

    @Environment(\.palette) private var palette

    init(_ title: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        Section {
            content
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(palette.border)
        } header: {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .textCase(nil)
            }
        } footer: {
            footer
                .font(.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .listSectionSeparator(.hidden)
    }
}

extension PageSection where Footer == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, content: content) { EmptyView() }
    }
}

extension View {
    /// The list ``PageSection``s sit in: edge to edge, on the page's paper instead of the grouped grey.
    func pageList() -> some View {
        modifier(PageList())
    }
}

private struct PageList: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .listStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(palette.background)
    }
}
