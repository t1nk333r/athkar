import SwiftUI

/// «حول التطبيق» in الإعدادات: the version, the installed content packs and the sources.
struct AboutView: View {
    let app: AppModel

    @Environment(\.palette) private var palette

    var body: some View {
        let report = AboutReport(installs: app.contentInstalls(), info: Bundle.main.infoDictionary ?? [:])
        List {
            PageSection("الإصدارات") {
                ForEach(report.versions) { row in
                    LabeledContent(row.title, value: row.value)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.title)
                        .accessibilityValue(row.value)
                        .accessibilityIdentifier("about.\(row.id)")
                }
            }
            PageSection("المصادر") {
                ForEach(report.sources) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title).font(.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        Text(row.value).font(.footnote).foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("about.\(row.id)")
                }
            }
        }
        .pageList()
        .navigationTitle("حول التطبيق")
        .navigationBarTitleDisplayMode(.inline)
    }
}
