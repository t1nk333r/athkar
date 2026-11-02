import UIKit

/// The home-screen quick actions (`UIApplicationShortcutItems` in Info.plist, spec/routes.md): each names an
/// ``AppRoute`` by its `shortcutType`. iOS hands an action to the scene: at connection when it launched the app, or
/// through the scene delegate when the app was running. One that arrives before the app has attached its router waits.
@MainActor
final class QuickActions {
    static let shared = QuickActions()

    private var open: ((AppRoute) -> Void)?
    private var waiting: AppRoute?

    /// The app's router; a route already waiting is opened now.
    func attach(_ open: @escaping (AppRoute) -> Void) {
        self.open = open
        if let route = waiting {
            waiting = nil
            open(route)
        }
    }

    /// Returns whether the action names a route.
    @discardableResult
    func perform(_ item: UIApplicationShortcutItem) -> Bool {
        guard let route = AppRoute(shortcutType: item.type) else { return false }
        if let open {
            open(route)
        } else {
            waiting = route
        }
        return true
    }
}

/// Gives every scene ``QuickActionSceneDelegate``, which is where iOS delivers quick actions to a SwiftUI app.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { QuickActions.shared.perform(item) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(QuickActions.shared.perform(shortcutItem))
    }
}
