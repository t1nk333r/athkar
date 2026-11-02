import Foundation

/// The places the app can be opened at from outside it (spec/routes.md): a URL, a home-screen quick action, or a
/// tapped adhkar reminder. Every one of them goes through ``AppModel/open(_:)``.
enum AppRoute: String, CaseIterable, Sendable {
    /// أذكار الصباح.
    case morning
    /// أذكار المساء.
    case evening
    /// رقية القرين.
    case ruqyah
    /// «اليوم»: today's five prayers, where a prayer is recorded.
    case prayers

    /// `athkar://<route>`: a custom scheme declared in Info.plist (`CFBundleURLTypes`). No universal links: they
    /// need an associated domain, which waits for the publisher identity (NATIVE_APP_PLAN.md §8.1).
    static let scheme = "athkar"

    /// `athkar://morning`. The route is the host; `athkar:///morning` and `athkar:morning` read the same. Case is
    /// ignored, a query or fragment is not read, and any other path makes the URL unknown.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let host = components.host ?? ""
        let path = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let name: String
        switch (host.isEmpty, path.count) {
        case (false, 0): name = host
        case (true, 1): name = path[0]
        default: return nil
        }
        self.init(rawValue: name.lowercased())
    }

    var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    // MARK: Quick actions

    /// `UIApplicationShortcutItemType` in Info.plist (`UIApplicationShortcutItems`).
    var shortcutType: String { "athkar.route.\(rawValue)" }

    init?(shortcutType: String) {
        guard let route = Self.allCases.first(where: { $0.shortcutType == shortcutType }) else { return nil }
        self = route
    }

    // MARK: Reminders

    /// A tapped adhkar reminder opens its deck. A prayer reminder is not a route: it opens أوقات الصلاة, as before.
    init?(reminder payload: ReminderPayload) {
        switch payload.deck {
        case .morning?: self = .morning
        case .evening?: self = .evening
        default: return nil
        }
    }

    /// The deck the route opens, or `nil` for «اليوم».
    var deck: DeckID? {
        switch self {
        case .morning: .morning
        case .evening: .evening
        case .ruqyah: .ruqyah
        case .prayers: nil
        }
    }
}
