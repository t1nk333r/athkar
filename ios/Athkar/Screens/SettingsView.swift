import AthkarCore
import SwiftUI

/// «الإعدادات»: reading and appearance, the app icon, reminders, long-order and haptics, manual completion, the data,
/// mostly in the athkar PWA's wording, laid out like its settings sheet: sections on the page, rules between rows.
/// Every change is written to the `settings` table (or the adhkar session) as it is made, except the icon, which iOS
/// keeps.
struct SettingsView: View {
    let app: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var transfer: TransferImportModel?
    @State private var choosesBackup = false
    /// «حذف كل البيانات»: the first question, then the second.
    @State private var asksDelete = false
    @State private var confirmsDelete = false
    @State private var isDeleting = false

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            List {
                PageSection("القراءة والمظهر") {
                    segmented("المظهر", selection: $settings.theme, identifier: "settings.theme",
                              options: [(.system, "تلقائي"), (.light, "فاتح"), (.dark, "داكن")])
                    segmented("حجم نص الأذكار", selection: $settings.textSize, identifier: "settings.textSize",
                              options: [(.small, "صغير"), (.medium, "متوسط"), (.large, "كبير")])
                    segmented("تباعد السطور", selection: $settings.lineSpacing, identifier: "settings.lineSpacing",
                              options: [(.compact, "متقارب"), (.comfortable, "مريح"), (.wide, "واسع")])
                    Toggle(isOn: $settings.homePrayerRow) {
                        toggleCopy("المواقيت في أعلى الصفحة",
                                   "الأذان القادم والتاريخ الهجري وتنبيه أوقات النهي عن الصلاة، مكان عنوان «بكرة وأصيلا».")
                    }
                    .accessibilityIdentifier("settings.homePrayerRow")
                }

                if AppIconChoice.isAvailable {
                    AppIconSection()
                }

                AdhkarReminderSection(app: app)

                PageSection("أثناء القراءة") {
                    Toggle(isOn: Binding(get: { app.settings.longOrder == .last }, set: { enabled in
                        app.setLongOrder(enabled)
                        guard app.settings.longOrder == (enabled ? .last : .original) else { return }
                        announce(enabled ? "ستُقرأ الأذكار الطويلة قبل الذكر الأخير" : "عاد ترتيب الأذكار كما هو")
                    })) {
                        toggleCopy("تأخير الأذكار الطويلة",
                                   "الأذكار التي تُكرَّر ١٠ مرات فأكثر تُقرأ في آخر الورد قبل الذكر الأخير، دون تغيير أرقامها ولا عدّاداتها.")
                    }
                    .accessibilityIdentifier("settings.longOrder")
                    Toggle(isOn: Binding(get: { settings.haptics }, set: { enabled in
                        settings.haptics = enabled
                        guard settings.haptics == enabled else { return }
                        if enabled { Haptics.shared.playCompletion() }
                        announce(enabled ? "شُغّل الاهتزاز" : "أُوقف الاهتزاز")
                    })) {
                        toggleCopy("الاهتزاز عند إكمال العداد",
                                   "عند إكمال ذكر يُكرَّر أكثر من مرة أو مقطع من الرقية أو صفحة من السور، وعند بلوغ هدف المسبحة وكل دورة بعده.")
                    }
                    .accessibilityIdentifier("settings.haptics")
                }

                PageSection("إكمال الورد يدويًا") {
                    manualCompletionToggle(.morning)
                    manualCompletionToggle(.evening)
                } footer: {
                    Text("فعّله إذا أكملت الورد خارج التطبيق. يُسجَّل الورد مكتملًا ويتوقف تذكيره اليوم، ثم يعود الخيار إلى الإيقاف غدًا. لا تتغير العدادات، وتُفتح كل بطاقات الورد للتصفح.")
                }

                PageSection("البيانات") {
                    Button {
                        transfer = app.makeTransferImport()
                    } label: {
                        rowCopy("استيراد من تطبيق الويب",
                                "انقل تقدّمك من «أذكار المسلم» على الويب برمز النقل أو ملفه أو رمز QR. لا يتغيّر شيء على هذا الجهاز قبل أن تراجعه وتؤكده.")
                    }
                    .accessibilityIdentifier("settings.transferImport")
                    NavigationLink {
                        BackupExportView(app: app)
                    } label: {
                        toggleCopy("تصدير نسخة احتياطية",
                                   "ملف واحد فيه كل ما سجّلته وإعداداتك، تحتفظ به أو تنقله إلى جهاز آخر.")
                    }
                    .accessibilityIdentifier("settings.backupExport")
                    Button {
                        choosesBackup = true
                    } label: {
                        rowCopy("استعادة نسخة احتياطية",
                                "ملف ‎.athkarbackup من هذا التطبيق أو من تطبيقَي الويب. يُضاف ما ينقص هذا الجهاز فقط، بعد أن تراجعه وتؤكده.")
                    }
                    .accessibilityIdentifier("settings.backupRestore")
                }

                PageSection {
                    link("الخصوصية", identifier: "settings.privacy") { PrivacyView() }
                    link("حول التطبيق", identifier: "settings.about") { AboutView(app: app) }
                    link("التشخيص", identifier: "settings.diagnostics") { DiagnosticsView(app: app) }
                }

                PageSection {
                    Button(role: .destructive) {
                        asksDelete = true
                    } label: {
                        Text(isDeleting ? "يُحذف…" : "حذف كل البيانات")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(isDeleting)
                    .accessibilityIdentifier("settings.deleteAll")
                } footer: {
                    Text("يحذف من هذا الجهاز كل ما سجّلته وإعداداتك، ويلغي التذكيرات المجدولة.")
                }
            }
            .pageList()
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                        .accessibilityIdentifier("settings.close")
                }
            }
        }
        .tint(palette.accentStrong)
        .sheet(item: $transfer) { model in
            TransferImportView(model: model)
                .environment(\.palette, palette)
        }
        .fileImporter(isPresented: $choosesBackup, allowedContentTypes: TransferImportView.fileTypes) { picked in
            guard case let .success(url) = picked else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let model = app.makeTransferImport()
            model.open(fileData: TransferImportModel.read(url))
            transfer = model
        }
        .alert("حذف كل البيانات؟", isPresented: $asksDelete) {
            Button("متابعة", role: .destructive) { confirmsDelete = true }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("يُحذف من هذا الجهاز كل ما سجّلته: الأذكار والرقية والسور والمسبحة وسجل الصلوات والتذكيرات والموقع والإعدادات. لا يمكن التراجع عن ذلك، فصدّر نسخة احتياطية أولًا إن أردت الاحتفاظ به.")
        }
        .alert("تأكيد الحذف", isPresented: $confirmsDelete) {
            Button("حذف كل البيانات", role: .destructive) {
                isDeleting = true
                Task {
                    let deleted = await app.deleteAllData()
                    isDeleting = false
                    guard deleted else { return }
                    announce("حُذفت كل البيانات من هذا الجهاز")
                    dismiss()
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("هل تريد حذف كل البيانات من هذا الجهاز نهائيًا؟")
        }
    }

    private func segmented<Value: Hashable>(_ title: String, selection: Binding<Value>, identifier: String,
                                            options: [(Value, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(palette.textPrimary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 4)
    }

    private func toggleCopy(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
            Text(note).font(.footnote).foregroundStyle(palette.textSecondary)
        }
    }

    /// A button row's copy: the whole row is the tap target, in ink rather than the button tint.
    private func rowCopy(_ title: String, _ note: String) -> some View {
        toggleCopy(title, note)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func link(_ title: String, identifier: String, @ViewBuilder to destination: () -> some View) -> some View {
        NavigationLink(destination: destination) {
            Text(title).font(.body).foregroundStyle(palette.textPrimary)
        }
        .accessibilityIdentifier(identifier)
    }

    /// `updateManualCompletionControls` / `setManualCompletion`: on while complete; locked on when the counters
    /// completed the period in the app.
    private func manualCompletionToggle(_ period: Period) -> some View {
        let title = AdhkarSessionModel.title(period)
        let byCounters = app.adhkar.countersComplete(period)
        let manually = app.adhkar.isManuallyComplete(period)
        let status = byCounters ? "اكتملت داخل التطبيق" : manually ? "اكتملت خارج التطبيق" : "لم تُسجل كمكتملة"
        return Toggle(isOn: Binding(get: { byCounters || manually }, set: { completed in
            guard app.adhkar.setManualCompletion(period, completed: completed) else {
                // Refused because the counters complete the period, or not saved: a failure is reported, and a
                // change that did not happen is not announced.
                if app.adhkar.countersComplete(period) { announce("\(title) مكتملة داخل التطبيق") }
                return
            }
            guard app.adhkar.isManuallyComplete(period) == completed else { return }
            announce(completed ? "سُجلت \(title) مكتملة خارج التطبيق" : "أُلغي الإكمال اليدوي لـ\(title)")
        })) {
            toggleCopy(title, status)
        }
        .disabled(byCounters)
        // The PWA's `.settings-toggle-control:has(:disabled)`: the whole row fades, not only the switch.
        .opacity(byCounters ? 0.6 : 1)
        .accessibilityIdentifier("settings.manual.\(period.rawValue)")
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
