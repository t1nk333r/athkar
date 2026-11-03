import SwiftUI

/// «التشخيص» in الإعدادات: the reminder counts and times, the permission, and the bundled content and app versions.
struct DiagnosticsView: View {
    let app: AppModel

    var body: some View {
        let report = DiagnosticsReport(diagnostics: app.reminders.diagnostics,
                                       authorization: app.reminders.authorization, zone: app.prayer.zone,
                                       contentVersions: app.contentVersions,
                                       info: Bundle.main.infoDictionary ?? [:])
        List {
            PageSection("التذكيرات") {
                rows(report.reminders)
            } footer: {
                Text("يقرّر iOS متى يجري التحديث في الخلفية، وقد لا يجريه إذا قلّ استخدام التطبيق.")
            }
            PageSection("المحتوى") { rows(report.content) }
            PageSection {
                rows(report.app)
            } footer: {
                Text("تعرض هذه الصفحة أعدادًا وأوقاتًا وإصدارات فقط، دون شيء من أذكارك أو صلواتك، فيمكن مشاركتها عند الإبلاغ عن مشكلة.")
            }
        }
        .pageList()
        .navigationTitle("التشخيص")
        .navigationBarTitleDisplayMode(.inline)
        .task { await app.reminders.refreshDiagnostics() }
    }

    private func rows(_ rows: [DiagnosticsReport.Row]) -> some View {
        ForEach(rows) { row in
            LabeledContent(row.title, value: row.value)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.title)
                .accessibilityValue(row.value)
                .accessibilityIdentifier("diagnostics.\(row.id)")
        }
    }
}
