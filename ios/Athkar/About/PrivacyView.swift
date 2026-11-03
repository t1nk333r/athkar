import SwiftUI

/// «الخصوصية» in الإعدادات (MOBILE_APP_PLAN.md §15, NATIVE_APP_PLAN.md §7.4): what stays on the device, the location,
/// the reminders, the lock-screen widget and the backups.
struct PrivacyView: View {
    static let sections: [(id: String, title: String, text: String)] = [
        ("device", "على جهازك فقط",
         "كل ما تسجّله في التطبيق من أذكار وصلوات وإعدادات يبقى على هذا الجهاز. لا يجمع التطبيق أي بيانات ولا يرسلها إلى أي جهة، ولا حساب فيه ولا إعلانات ولا تتبّع."),
        ("location", "الموقع",
         "يُطلب الموقع مرة واحدة عند الحاجة، لحساب مواقيت الصلاة واتجاه القبلة فقط، ولا يُطلب في الخلفية. يُحفظ على جهازك مقرّبًا إلى منزلتين عشريتين (نحو كيلومتر واحد)."),
        ("reminders", "التذكيرات",
         "تُجدول التذكيرات على جهازك نفسه، ولا يمرّ شيء منها بأي خادم. لا يحمل نص التذكير شيئًا من سجل صلواتك."),
        ("widget", "أداة شاشة القفل",
         "يحفظ التطبيق على جهازك أوقات الأذان والإقامة للأيام الثلاثين القادمة لتعرضها الأداة. لا تحمل موقعك ولا سجل صلواتك، لكنها تدلّ على منطقتك تقريبًا. يحذفها «حذف كل البيانات»، أما حذف التطبيق فلا يحذفها."),
        ("backups", "النسخ الاحتياطية",
         "النسخة الاحتياطية ملف نصي غير مشفّر يُنشأ على جهازك، ولا يغادره إلا إذا شاركته أنت. لا يُضاف إليه موقعك إلا إذا اخترت ذلك عند التصدير."),
        ("delete", "حذف البيانات",
         "يحذف «حذف كل البيانات» في الإعدادات كل ما سجّلته على هذا الجهاز، ويلغي التذكيرات المجدولة."),
    ]

    @Environment(\.palette) private var palette

    var body: some View {
        List {
            ForEach(Self.sections, id: \.id) { section in
                PageSection(section.title) {
                    Text(section.text)
                        .font(.subheadline)
                        .foregroundStyle(palette.textPrimary)
                        .accessibilityIdentifier("privacy.\(section.id)")
                }
            }
        }
        .pageList()
        .navigationTitle("الخصوصية")
        .navigationBarTitleDisplayMode(.inline)
    }
}
