import AthkarCore
import SwiftUI

@main
struct AthkarApp: App {
    @State private var launch = Result { try AppModel.launch() }

    var body: some Scene {
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
    }
}

/// Applies the theme and runs the day rollover (NATIVE_APP_PLAN.md §6.3): on `NSCalendarDayChanged` (local
/// midnight while the app runs), on a clock or time-zone change, and whenever the app comes to the foreground.
private struct RootView: View {
    let app: AppModel

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HomeView(app: app)
            .preferredColorScheme(Self.colorScheme(app.settings.theme))
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { app.ensureCurrentDay() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) {
                _ in app.ensureCurrentDay()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) {
                _ in app.ensureCurrentDay()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) {
                _ in app.ensureCurrentDay()
            }
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
