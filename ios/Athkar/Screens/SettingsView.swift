import AthkarCore
import SwiftUI

/// «الإعدادات» for this slice: reading and appearance, long-order, manual completion, haptics, with the athkar
/// PWA's wording. Every change is written to the `settings` table (or the adhkar session) as it is made.
struct SettingsView: View {
    let app: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            Form {
                Section("القراءة والمظهر") {
                    segmented("المظهر", selection: $settings.theme, identifier: "settings.theme",
                              options: [(.system, "تلقائي"), (.light, "فاتح"), (.dark, "داكن")])
                    segmented("حجم نص الأذكار", selection: $settings.textSize, identifier: "settings.textSize",
                              options: [(.small, "صغير"), (.medium, "متوسط"), (.large, "كبير")])
                    segmented("تباعد السطور", selection: $settings.lineSpacing, identifier: "settings.lineSpacing",
                              options: [(.compact, "متقارب"), (.comfortable, "مريح"), (.wide, "واسع")])
                }

                Section("ترتيب الأذكار الطويلة") {
                    Toggle(isOn: Binding(get: { app.settings.longOrder == .last }, set: { enabled in
                        app.setLongOrder(enabled)
                        announce(enabled ? "ستُقرأ الأذكار الطويلة قبل الذكر الأخير" : "عاد ترتيب الأذكار كما هو")
                    })) {
                        toggleCopy("تأخير الأذكار الطويلة",
                                   "الأذكار التي تُكرَّر ١٠ مرات فأكثر تُقرأ في آخر الورد قبل الذكر الأخير، دون تغيير أرقامها ولا عدّاداتها.")
                    }
                    .accessibilityIdentifier("settings.longOrder")
                }

                Section {
                    manualCompletionToggle(.morning)
                    manualCompletionToggle(.evening)
                } header: {
                    Text("إكمال الورد يدويًا")
                } footer: {
                    Text("فعّله إذا أكملت الورد خارج التطبيق. سيُسجل كمكتمل ويوقف تذكيره اليوم، ثم يُعاد تلقائيًا غدًا. لا تتغير العدادات، ويمكنك تصفح بطاقات الورد بحرية.")
                }

                Section("الاهتزاز") {
                    Toggle(isOn: Binding(get: { settings.haptics }, set: { enabled in
                        settings.haptics = enabled
                        if enabled { Haptics.shared.playCompletion() }
                        announce(enabled ? "تم تشغيل الاهتزاز" : "تم إيقاف الاهتزاز")
                    })) {
                        toggleCopy("الاهتزاز عند إكمال الذكر", "اهتزاز لمدة ٤٥ مللي ثانية عند إكمال الذكر.")
                    }
                    .accessibilityIdentifier("settings.haptics")
                }
            }
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
    }

    private func segmented<Value: Hashable>(_ title: String, selection: Binding<Value>, identifier: String,
                                            options: [(Value, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
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
            Text(title).font(.body.weight(.semibold))
            Text(note).font(.footnote).foregroundStyle(.secondary)
        }
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
                announce("\(title) مكتملة داخل التطبيق")
                return
            }
            announce(completed ? "سُجلت \(title) مكتملة خارج التطبيق" : "أُلغي الإكمال اليدوي لـ\(title)")
        })) {
            toggleCopy(title, status)
        }
        .disabled(byCounters)
        .accessibilityIdentifier("settings.manual.\(period.rawValue)")
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
