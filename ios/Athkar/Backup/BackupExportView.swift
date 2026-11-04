import SwiftUI
import UIKit

/// «تصدير نسخة احتياطية» in الإعدادات: says what the file holds and that it is plaintext, offers «تضمين الموقع» (off each
/// time the screen opens), then writes the file and hands it to the share sheet.
struct BackupExportView: View {
    @State private var model: BackupExportModel
    /// A location is saved on this device, so «تضمين الموقع» has something to include.
    let hasLocation: Bool

    @Environment(\.palette) private var palette

    init(app: AppModel) {
        _model = State(initialValue: app.makeBackupExport())
        hasLocation = app.prayer.location != nil
    }

    var body: some View {
        List {
            PageSection {
                Text("تحفظ النسخة الاحتياطية في ملف واحد كل ما سجّلته في التطبيق: الأذكار والرقية والسور والمسبحة وسجل الصلوات والتذكيرات والإعدادات.")
                    .foregroundStyle(palette.textPrimary)
                Text("الملف نص مقروء غير مشفّر. لا يغادر جهازك إلا إذا شاركته أنت، فاحفظه في مكان تثق به.")
                    .foregroundStyle(palette.textSecondary)
            }
            .font(.subheadline)

            PageSection {
                Toggle(isOn: $model.includesLocation) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("تضمين الموقع").font(.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        Text(hasLocation
                             ? "يُضاف موقعك المحفوظ لحساب مواقيت الصلاة، مقرّبًا إلى منزلتين عشريتين. لا يُضاف ما لم تفعّل هذا."
                             : "لا يوجد موقع محفوظ على هذا الجهاز.")
                            .font(.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .disabled(!hasLocation)
                .opacity(hasLocation ? 1 : 0.6)
                .accessibilityIdentifier("export.includeLocation")
            }

            PageSection {
                Button {
                    model.export()
                } label: {
                    Text("تصدير ومشاركة")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("export.share")
                if let error = model.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(palette.warning)
                        .accessibilityIdentifier("export.error")
                }
            } footer: {
                Text("لاستعادتها افتح الملف بهذا التطبيق، أو اختر «استعادة نسخة احتياطية» في الإعدادات.")
            }
        }
        .pageList()
        .navigationTitle("النسخة الاحتياطية")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $model.file, onDismiss: { model.clear() }) { file in
            ShareSheet(url: file.url)
                .ignoresSafeArea()
        }
        .onDisappear { if model.file == nil { model.clear() } }
    }
}

/// The system share sheet for one file.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.view.accessibilityIdentifier = "export.shareSheet"
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
