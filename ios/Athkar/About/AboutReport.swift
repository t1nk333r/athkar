import AthkarCore
import Foundation

/// «حول التطبيق» (MOBILE_APP_PLAN.md §9, §15): the app's version, each bundled pack's installed version as
/// `content_installs` records it, and the sources the app already cites elsewhere (content/REVIEW.md, fonts/README.md,
/// spec/prayer-times/README.md). Nothing here is the user's own data.
struct AboutReport: Equatable {
    struct Row: Equatable, Identifiable {
        /// The accessibility identifier's last part, `about.<id>`.
        let id: String
        let title: String
        let value: String
    }

    let versions: [Row]
    let sources: [Row]

    /// The Quran text's edition in the ruqyah and «سور» packs (`edition` in `content/*.v1.json`).
    static let quranEdition = "alquran-cloud:quran-uthmani"

    /// - Parameters:
    ///   - installs: the `content_installs` rows.
    ///   - info: the app's Info.plist (`CFBundleShortVersionString`, `CFBundleVersion`).
    init(installs: [ContentInstall], info: [String: Any]) {
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        versions = [Row(id: "appVersion", title: "إصدار التطبيق", value: "\(version) (\(build))")]
            + installs.sorted { $0.packId < $1.packId }.map { install in
                Row(id: "content.\(install.packId)", title: DiagnosticsReport.packTitle(install.packId),
                    value: install.version)
            }
        sources = [
            Row(id: "adhkar", title: "الأذكار",
                value: "يُذكر مصدر كل ذكر في «المصدر والتفاصيل» على بطاقته."),
            Row(id: "quran", title: "نص القرآن",
                value: "آيات الرقية وسور «سور» بالرسم العثماني من إصدار \(Self.quranEdition)، وقد قوبلت بنص quran.com."),
            Row(id: "fonts", title: "الخطوط",
                value: "خطّا مجمع الملك فهد لطباعة المصحف الشريف (fonts.qurancomplex.gov.sa): KFGQPC HAFS Uthmanic Script 3.0 لنص القرآن، وKFGQPC Uthman Taha Naskh 2.0 لعلامتي الآية ﴿ ﴾، دون تعديل."),
            Row(id: "prayerTimes", title: "مواقيت الصلاة",
                value: "تُحسب على جهازك بمكتبة Adhan من Batoul Apps (رخصة MIT)، بالطريقة والمذهب المختارين في «أوقات الصلاة»."),
            Row(id: "prohibitedTimes", title: "أوقات النهي عن الصلاة",
                value: "كما في فتوى الشيخ عبد العزيز بن باز رقم ١٠٦٩٣ (binbaz.org.sa)."),
        ]
    }
}
