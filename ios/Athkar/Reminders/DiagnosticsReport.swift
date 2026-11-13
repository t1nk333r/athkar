import AthkarCore
import Foundation

/// «التشخيص» (NATIVE_APP_PLAN.md §7.5, §8.4): what a tester can report without screenshots of worship data. Only
/// counts, times, the permission and versions; no adhkar progress, prayer record or tracker state is read here.
struct DiagnosticsReport: Equatable {
    struct Row: Equatable, Identifiable {
        /// The accessibility identifier's last part, `diagnostics.<id>`.
        let id: String
        let title: String
        let value: String
    }

    let reminders: [Row]
    let content: [Row]
    let app: [Row]

    /// - Parameters:
    ///   - zone: the zone times are shown in.
    ///   - contentVersions: the bundled packs' versions from `manifest.json`.
    ///   - info: the app's Info.plist (`CFBundleShortVersionString`, `CFBundleVersion`).
    init(diagnostics: ReminderModel.Diagnostics, authorization: ReminderModel.Authorization, zone: TimeZone,
         contentVersions: [(pack: String, version: String)], info: [String: Any]) {
        func count(_ value: Int?) -> String { value.map(ArabicFormat.number) ?? "—" }
        func when(_ date: Date) -> String {
            "\(ArabicFormat.shortDate(date, in: zone)) \(ArabicFormat.time(date, in: zone))"
        }
        let permission = switch authorization {
        case .allowed: "مسموح"
        case .denied: "غير مسموح"
        case .notDetermined: "لم يُطلب بعد"
        }
        let request = switch diagnostics.refreshRequest {
        case let .accepted(earliest)?: "لا يبدأ قبل \(when(earliest))"
        case .refused?: "غير متاح على هذا الجهاز"
        case nil: "لم يُطلب بعد"
        }
        reminders = [
            Row(id: "planned", title: "التذكيرات المخطَّطة", value: count(diagnostics.planned)),
            Row(id: "pending", title: "المعلَّقة لدى iOS", value: count(diagnostics.pending)),
            Row(id: "dropped", title: "خارج حدّ الطلبات", value: count(diagnostics.droppedByBudget)),
            Row(id: "horizon", title: "مدى الجدولة", value: ArabicFormat.dayCount(ReminderPlanner.horizonDays)),
            Row(id: "budget", title: "حدّ الطلبات المعلَّقة", value: ArabicFormat.number(ReminderPlanner.budget)),
            Row(id: "authorization", title: "إذن الإشعارات", value: permission),
            Row(id: "lastReplan", title: "آخر جدولة",
                value: diagnostics.lastReplanAt.map(when) ?? "لم تحدث بعد"),
            Row(id: "lastRefresh", title: "آخر تحديث في الخلفية",
                value: diagnostics.lastBackgroundRefreshAt.map(when) ?? "لم يحدث بعد"),
            Row(id: "refreshRequest", title: "التحديث التالي في الخلفية", value: request),
        ]
        content = contentVersions.map { pack in
            Row(id: "content.\(pack.pack)", title: Self.packTitle(pack.pack), value: pack.version)
        }
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        app = [Row(id: "appVersion", title: "إصدار التطبيق", value: "\(version) (\(build))")]
    }

    static func packTitle(_ pack: String) -> String {
        switch pack {
        case "adhkar": "محتوى الأذكار"
        case "ruqyah": "محتوى رقية القرين"
        case "suwar": "محتوى السور"
        case "salawat": "محتوى الصلاة على النبي ﷺ"
        default: "محتوى \(pack)"
        }
    }
}
