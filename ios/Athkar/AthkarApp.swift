import AthkarCore
import SwiftUI
import UserNotifications

@main
struct AthkarApp: App {
    @State private var launch: Result<AppModel, any Error>

    init() {
        let launch = Result { try AppModel.launch() }
        _launch = State(initialValue: launch)
        if case let .success(app) = launch {
            app.reminders.refreshScheduler = AppRefreshScheduler()
            // A background launch for «سجّل الصلاة» has no scene, so the action is attached here, with the app.
            ReminderNotificationDelegate.shared.attachActions { payload, date in
                await app.recordPrayer(payload, shownAt: date)
            }
        }
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories(ReminderModel.categories)
        // Before launch finishes, so the tap that opens the app is delivered (NATIVE_APP_PLAN.md §7.5).
        center.delegate = ReminderNotificationDelegate.shared
    }

    var body: some Scene {
        let app = try? launch.get()
        WindowGroup {
            Group {
                switch launch {
                case let .success(app):
                    RootView(app: app)
                case let .failure(error):
                    LaunchFailureView(error: error)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
        }
        // The opportunistic refresh (NATIVE_APP_PLAN.md §7.5): it asks for the next one, then replans.
        .backgroundTask(.appRefresh(ReminderModel.refreshTaskIdentifier)) {
            await app?.reminders.runBackgroundRefresh()
        }
    }
}

/// Applies the theme and runs the day rollover (NATIVE_APP_PLAN.md §6.3): on `NSCalendarDayChanged` (local
/// midnight while the app runs), on a clock or time-zone change, and whenever the app comes to the foreground.
/// The same events, and anything the reminder plan depends on, replan the reminders (§7.5).
private struct RootView: View {
    let app: AppModel

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HomeView(app: app)
            .preferredColorScheme(Self.colorScheme(app.settings.theme))
            .task {
                ReminderNotificationDelegate.shared.attach(
                    onShown: { payload, date in
                        app.reminders.markShown(payload, localDate: SessionCalendar.localDate(of: date,
                                                                                               in: app.prayer.zone))
                    },
                    onOpen: { payload in app.open(payload) })
                app.reminders.replan()
            }
            // A transfer code or backup file opened in the app: «استيراد من تطبيق الويب» shows its review.
            .onOpenURL { url in
                if url.isFileURL { app.openTransferFile(url) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
                // iOS may then run a refresh while the app is not opened; it decides when.
                if phase == .background { app.reminders.scheduleBackgroundRefresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) {
                _ in refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) {
                _ in refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) {
                _ in refresh()
            }
            .onChange(of: app.prayer.location) { app.reminders.replan() }
            .onChange(of: app.prayer.settings) { app.reminders.replan() }
            .onChange(of: app.adhkar.isComplete(.morning)) { app.reminders.replan() }
            .onChange(of: app.adhkar.isComplete(.evening)) { app.reminders.replan() }
    }

    private func refresh() {
        app.ensureCurrentDay()
        app.reminders.replan()
    }

    private static func colorScheme(_ theme: Theme) -> ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Shown only if the database or the bundled content cannot be opened.
private struct LaunchFailureView: View {
    let error: any Error

    var body: some View {
        VStack(spacing: 12) {
            Text("تعذّر فتح بيانات التطبيق").font(.title3.weight(.bold))
            Text(error.localizedDescription).font(.footnote).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}
