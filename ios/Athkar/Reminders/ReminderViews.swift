import AthkarCore
import SwiftUI
import UIKit

/// «التذكيرات المرتبطة بالصلاة» in الإعدادات: the athkar PWA's two toggles, fajr + 60 and asr + 60, with today's times.
struct AdhkarReminderSection: View {
    let app: AppModel

    var body: some View {
        Section {
            toggle(.morning, note: "بعد الفجر بساعة", prayer: .fajr)
            toggle(.evening, note: "بعد العصر بساعة", prayer: .asr)
        } header: {
            Text("التذكيرات المرتبطة بالصلاة")
        } footer: {
            ReminderStatusNote(reminders: app.reminders, hasLocation: app.prayer.location != nil,
                               enabled: app.reminders.isEnabled(.morning) || app.reminders.isEnabled(.evening))
        }
        .task { await app.reminders.refreshAuthorization() }
    }

    private func toggle(_ period: Period, note: String, prayer: PrayerTime) -> some View {
        let today = app.prayer.schedule(dayOffset: 0)
        let time = (prayer == .asr && today?.asrClamped == true) ? nil : today?[prayer]
        let detail = time.map { "\(note) · \(ArabicFormat.time($0.addingTimeInterval(3600), in: app.prayer.zone))" }
        return Toggle(isOn: Binding(get: { app.reminders.isEnabled(period) }, set: { enabled in
            Task { await app.reminders.setAdhkar(period, enabled: enabled) }
        })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AdhkarSessionModel.title(period)).font(.body.weight(.semibold))
                Text(detail ?? note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("settings.reminder.\(period.rawValue)")
    }
}

/// «تنبيهات الصلاة»: a reminder per prayer, at the adhan or a few minutes before it.
struct PrayerRemindersView: View {
    let reminders: ReminderModel
    let prayer: PrayerTimesModel

    @Environment(\.dismiss) private var dismiss

    private static let keys: [ReminderRule.PrayerKey] = [.fajr, .dhuhr, .asr, .maghrib, .isha]
    private static let offsets = [0, -5, -10, -15, -30]

    var body: some View {
        NavigationStack {
            Form {
                ForEach(Self.keys, id: \.self) { key in
                    Section {
                        row(key)
                    }
                }
                Section {
                } footer: {
                    ReminderStatusNote(reminders: reminders, hasLocation: prayer.location != nil,
                                       enabled: Self.keys.contains { reminders.prayerRule($0)?.enabled == true })
                }
            }
            .navigationTitle("تنبيهات الصلاة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                        .accessibilityIdentifier("prayer.reminders.done")
                }
            }
            .task { await reminders.refreshAuthorization() }
        }
    }

    @ViewBuilder
    private func row(_ key: ReminderRule.PrayerKey) -> some View {
        let rule = reminders.prayerRule(key)
        let enabled = rule?.enabled ?? false
        let offset = rule?.offsetMinutes ?? 0
        Toggle(isOn: Binding(get: { enabled }, set: { value in
            Task { await reminders.setPrayer(key, enabled: value, offsetMinutes: offset) }
        })) {
            Text("صلاة \(PrayerNames.name(key.prayerTime))").font(.body.weight(.semibold))
        }
        .accessibilityIdentifier("prayer.reminder.\(key.rawValue)")
        if enabled {
            Picker("موعد التنبيه", selection: Binding(get: { offset }, set: { value in
                Task { await reminders.setPrayer(key, enabled: true, offsetMinutes: value) }
            })) {
                ForEach(Self.offsets, id: \.self) { minutes in
                    Text(Self.offsetLabel(minutes)).tag(minutes)
                }
            }
            .accessibilityIdentifier("prayer.reminder.\(key.rawValue).offset")
        }
    }

    static func offsetLabel(_ minutes: Int) -> String {
        minutes == 0 ? "عند الأذان" : "قبل الأذان بـ\(ReminderModel.minutesLabel(-minutes))"
    }
}

/// The PWA's `reminder-status` note, for iOS: what keeps reminders from being delivered, if anything.
struct ReminderStatusNote: View {
    let reminders: ReminderModel
    let hasLocation: Bool
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
            if enabled, reminders.authorization == .denied,
               let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                Link("فتح إعدادات الإشعارات", destination: url)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("reminders.openSettings")
            }
        }
        .accessibilityIdentifier("reminders.status")
    }

    /// «اليوم ٥:٥٥ ص»، «غدًا ٤:٤٥ م»، or the weekday beyond that.
    private static func when(_ date: Date) -> String {
        let time = ArabicFormat.time(date)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "اليوم \(time)" }
        if calendar.isDateInTomorrow(date) { return "غدًا \(time)" }
        return date.formatted(Date.FormatStyle(locale: Locale(identifier: "ar")).weekday(.wide)) + " " + time
    }

    private var message: String {
        if !hasLocation { return "حدّد الموقع في «أوقات الصلاة» لحساب المواعيد محليًا دون إرسال موقعك." }
        if !enabled { return "التذكيرات متوقفة ومحفوظة محليًا على هذا الجهاز." }
        switch reminders.authorization {
        case .denied: return "الإشعارات غير مسموح بها لهذا التطبيق. اسمح بها من الإعدادات لتصلك التذكيرات."
        case .notDetermined: return "سيُطلب إذن الإشعارات عند تشغيل أول تذكير."
        case .allowed:
            let base = "المواعيد محسوبة محليًا، وتصل التذكيرات ولو كان التطبيق مغلقًا."
            guard let next = reminders.nextPending else { return base }
            return base + " التذكير القادم: \(next.title) \(Self.when(next.fireAt))."
        }
    }
}
